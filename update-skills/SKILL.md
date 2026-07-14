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

## 4. Apply changes

For each **Upstream changed** skill, show the diff and ask the user whether to take it: **accept** (overwrite the local folder with the upstream one), **skip** (leave local as-is, revisit later), or **merge manually** (user will handle it themselves after this run). Never overwrite without a per-skill decision — a vendored skill may have been hand-edited locally since it was copied in, and the diff is the only way to catch that (it will show the upstream change tangled with the reverted local edit, which is exactly the signal to skip or merge instead of blindly accepting).

For each **accept**, mirror the upstream folder over the local one (replace the whole directory rather than patching file-by-file, so deleted upstream files are actually removed locally):

```
rm -rf "<repo-root>/<name>"
cp -r "<scratch>/<source-slug>/<dirname of skillPath>" "<repo-root>/<name>"
```

## 5. Update the lock file

For each accepted skill, recompute its hash and bump the timestamp:

```
find "<repo-root>/<name>" -type f | sort | xargs -I{} sh -c 'echo {}; cat {}' | sha1sum
```

Write the resulting hash into that entry's `vendoredHash`, and set `vendoredAt` to today's date (`date +%F`). Leave `source`/`sourceType`/`sourceUrl`/`skillPath` untouched.

This hash is this repo's own convention, recomputed by this skill — it has no relationship to whatever hashing scheme the original mattpocock-skills installer used (visible if you ever compare against `~/.agents/.skill-lock.json`). Don't try to reconcile the two; this lock file is the source of truth going forward.

## 6. Clean up and summarize

Delete the scratch clones. Report: N unchanged, N updated (list them), N skipped, N flagged as missing upstream. Remind the user the changes are unstaged — review with `git diff` and commit when ready; this skill never commits on its own.

## Adding a newly-tracked skill

Not this skill's job to discover new skills upstream — it only refreshes what's already in the lock file. To start tracking one:

1. Copy its folder in from the source repo.
2. Add an entry to `.skill-lock.json` with `source`, `sourceType`, `sourceUrl`, `skillPath`, plus a `vendoredHash` (per step 5) and today's `vendoredAt`.
