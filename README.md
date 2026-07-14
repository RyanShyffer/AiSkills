# AiSkills

Personal collection of [Claude Code](https://claude.com/claude-code) skills — one folder per skill, each with a `SKILL.md`. This repo is the single copy; every place Claude Code needs these skills points *at* it rather than holding its own copy.

## Layout

```
<skill-name>/
  SKILL.md       # required — frontmatter (name, description, ...) + instructions
  <other>.md     # optional sibling reference files the skill points at
```

A skill is either:

- **Vendored** — copied in from an upstream repo, tracked in [`.skill-lock.json`](#skill-lockjson) (e.g. everything from `mattpocock/skills`, plus `find-skills` from `vercel-labs/skills`).
- **Local** — authored in this repo directly, no upstream. Not listed in the lock file. `pr-review-fixes` is the current example.

## Where this is consumed

- **`~/.claude/skills`** (this machine's live personal-skills directory) contains a symlink per skill folder pointing back into this repo. Claude Code reads skills from there, so editing a `SKILL.md` in this repo takes effect immediately, no copy step. If you ever see a skill listed as missing or a symlink broken, re-point it at `<this-repo>/<skill-name>` — don't recreate the folder by hand.
- **`docker-claude-windows`** (a sibling project that runs Claude Code in a Windows container) bind-mounts this whole repo to `C:\claude-config\skills` inside the container, so the containerized Claude sees the same skills as the host.

Both are just consumers pointing at this repo — this repo never points back at them.

## `.skill-lock.json`

Records, for every **vendored** skill, where it came from:

```json
"ask-matt": {
  "source": "mattpocock/skills",
  "sourceType": "github",
  "sourceUrl": "https://github.com/mattpocock/skills.git",
  "skillPath": "skills/engineering/ask-matt/SKILL.md",
  "vendoredHash": "<sha1 of the folder's contents, as of the last sync>",
  "vendoredAt": "2026-07-14"
}
```

This is a **static record**, not managed by an installer — nothing enforces it stays accurate except re-running the sync described below. `vendoredHash` is this repo's own convention (sorted file paths + contents, sha1'd — see the `update-skills` skill for the exact recipe); it has no relationship to any hash a third-party installer tool might compute for the same skill.

Local skills (no known upstream) are intentionally absent from the lock file — there's nothing to sync them against.

## Keeping vendored skills in sync

Run the `update-skills` skill (`/update-skills` in Claude Code, from this repo). It:

1. Reads `.skill-lock.json` and clones each unique `sourceUrl` once.
2. Diffs every tracked skill's folder against the corresponding path in its source repo.
3. Shows you the diff for anything that's changed upstream and lets you accept, skip, or merge manually per skill — it never overwrites blindly, since a vendored skill may have been hand-edited locally since it was copied in.
4. Updates `vendoredHash`/`vendoredAt` for whatever it pulled in.

It only refreshes skills already in the lock file. To start tracking a new one (a new skill from an already-tracked source, or a brand-new source repo), copy the folder in and add an entry to `.skill-lock.json` by hand — see the skill's own `SKILL.md` for the exact steps.

Nothing here auto-commits — review with `git diff` and commit once you're happy with what changed.
