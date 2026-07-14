---
name: update-skills
description: Check the skills vendored into this repo against their upstream source repos, listed in .skill-lock.json, and pull in any changes. Use when the user wants to update, sync, or refresh skills from mattpocock/skills or another tracked source, or check whether any tracked skill is out of date.
disable-model-invocation: true
---

# Update Skills

Every skill folder in this repo is either **vendored** (copied in from an upstream repo, tracked in `.skill-lock.json`) or **local** (authored here, no upstream — not in the lock file). This skill refreshes vendored skills from their source; it never touches local ones.

## 1. Read the lock file

Load `.skill-lock.json`. Each entry under `skills` looks like:

```json
"ask-matt": {
  "source": "mattpocock/skills",
  "sourceType": "github",
  "sourceUrl": "https://github.com/mattpocock/skills.git",
  "skillPath": "skills/engineering/ask-matt/SKILL.md",
  "vendoredHash": "...",
  "vendoredAt": "2026-07-14"
}
```

`skillPath` points at the `SKILL.md` inside the upstream repo — the skill's folder is its parent directory (a skill can have sibling files like `GLOSSARY.md`, so always diff the whole folder, never just `SKILL.md`).

If `.skill-lock.json` doesn't exist, stop and tell the user there's nothing to update.

## 2. Fetch each source repo once

Group entries by `sourceUrl` — the same repo backs most entries, so clone it once, not once per skill. Shallow-clone each unique source into a scratch directory (the session's scratchpad dir if one is available, otherwise a plain temp dir):

```
git clone --depth 1 <sourceUrl> <scratch>/<source-slug>
```

Keep every intermediate file this run produces — entry lists, diff output, notes — inside that same scratch directory, not `/tmp` or elsewhere, so step 6's cleanup actually removes all of it.

**Do the whole pass in one toolchain.** If you parse `.skill-lock.json` with a scripting language (e.g. Python), don't hand its output paths to a filesystem check running in a different runtime than the shell that cloned the repos — a Windows-native Python interpreter silently fails on the `/c/...`-style paths a Windows Bash tool's `git`/`diff` produce (`os.path.isdir` returns `False` for a path that actually exists), which reads as "every skill is missing upstream" when nothing is actually wrong. Have the script emit plain `name|source-slug|skillPath` lines and do every filesystem-touching step from here on (dirname, `diff`, `cp`, `sha1sum`) in that same shell.

## 3. Diff each tracked skill

For every entry, compare the local folder (`<repo-root>/<name>/`) against the upstream folder (`<scratch>/<source-slug>/<dirname of skillPath>/`):

```
diff -rq "<repo-root>/<name>" "<scratch>/<source-slug>/<dirname of skillPath>"
```

Sort the result into three buckets:

| Bucket | Meaning |
|---|---|
| **Unchanged** | No diff. Nothing to do. |
| **Upstream changed** | Diff exists. Show the full `diff -r` output. |
| **Missing upstream** | `skillPath`'s directory no longer exists in the source repo (renamed or removed upstream). Flag it — don't guess at a replacement. |

Print a summary table (skill → bucket) before touching anything.

**Sanity-check the buckets before trusting them.** If most or all entries land in **Missing upstream** (or every entry reports the same surprising bucket), stop and manually inspect one upstream folder directly (`ls`) before reporting it — that pattern almost always means a path or tooling mismatch from step 2, not a genuine mass-removal upstream.

Within **Upstream changed**, separate two kinds of diff before presenting anything:

- **Content changed** — the diff touches the skill's own instructional files (`SKILL.md`, sibling reference `.md` files).
- **Non-essential files only** — the diff is entirely new sibling files/directories that aren't reference content for this skill, e.g. a source repo adding an `agents/` folder of per-other-agent-platform manifests. These carry no instructional change at all.

A skill can only be in one bucket for this split — if it has both, treat it as **content changed** (the non-essential files ride along with whatever decision is made there).

## 4. Apply changes

Handle the two changed-skill kinds separately, and batch the decision rather than asking once per skill — with 15+ skills a fixed per-skill question just makes the user answer the same thing repeatedly:

- **Non-essential files only**: ask once, covering every skill in this bucket at once — pull these files in, or skip them all (e.g. "this repo is Claude-Code-only, skip the other-platform manifests"). One answer applies to the whole bucket.
- **Content changed**: show the diffs (summarized if there are many, in full for anything a summary can't do justice to), then ask once whether to **accept all** (the diffs read as coherent upstream improvements, nothing conflicts with local edits) or **go one at a time** (accept/skip/merge per skill) — default to offering "accept all" as a choice rather than assuming it, and let the user's answer decide which mode to run in.

Never overwrite without at least this one round of confirmation — a vendored skill may have been hand-edited locally since it was copied in, and the diff is the only way to catch that (it will show the upstream change tangled with the reverted local edit, which is exactly the signal to skip or merge instead of blindly accepting).

For each **accept**, mirror the upstream folder over the local one (replace the whole directory rather than patching file-by-file, so deleted upstream files are actually removed locally):

```
rm -rf "<repo-root>/<name>"
cp -r "<scratch>/<source-slug>/<dirname of skillPath>" "<repo-root>/<name>"
```

If the **non-essential files** decision was skip, remove those specific paths from the freshly-copied folder afterward (e.g. `rm -rf "<repo-root>/<name>/agents"`) — the mirror above brings them back in even for a skill whose only upstream change *was* content.

## 5. Update the lock file

For each accepted skill, recompute its hash and bump the timestamp:

```
find "<repo-root>/<name>" -type f | sort | xargs -I{} sh -c 'echo {}; cat {}' | sha1sum
```

Write the resulting hash into that entry's `vendoredHash`, and set `vendoredAt` to today's date (`date +%F`). Leave `source`/`sourceType`/`sourceUrl`/`skillPath` untouched.

This hash is this repo's own convention, recomputed by this skill — it has no relationship to whatever hashing scheme the original mattpocock-skills installer used (visible if you ever compare against `~/.agents/.skill-lock.json`). Don't try to reconcile the two; this lock file is the source of truth going forward.

## 6. Clean up and summarize

Delete the scratch clones. Report: N unchanged, N updated (list them, noting whether non-essential files were included or stripped), N skipped, N flagged as missing upstream. Remind the user the changes are unstaged — review with `git diff` and commit when ready; this skill never commits on its own.

## Adding a newly-tracked skill

Not this skill's job to discover new skills upstream — it only refreshes what's already in the lock file. To start tracking one:

1. Copy its folder in from the source repo.
2. Add an entry to `.skill-lock.json` with `source`, `sourceType`, `sourceUrl`, `skillPath`, plus a `vendoredHash` (per step 5) and today's `vendoredAt`.
