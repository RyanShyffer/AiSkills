---
name: pr-review-fixes
description: Fetch unresolved review comments on the current branch's PR (any reviewer, including Copilot), triage each for legitimacy and risk, fix and test the ones that warrant it, reply on threads, push, and re-request a Copilot review. Use when the user wants to work through open PR review feedback, mentions "address review comments," "fix Copilot's comments," or asks for another Copilot review pass.
---

# PR Review Fixes

Works through a PR's outstanding review feedback semi-autonomously: fetch → triage → fix/test → reply → commit → push → re-request review. One pass per invocation — it doesn't wait around for a new round of comments.

## 1. Identify the PR

```
gh pr view --json number,url,headRefName
```

If there's no PR for the current branch, stop and say so.

## 2. Fetch unresolved review threads

Only **unresolved inline review threads** count — not resolved threads, not top-level PR conversation comments. Use the GraphQL API (the REST comments endpoint doesn't expose thread resolution state):

```
gh api graphql -f query='
  query($owner: String!, $repo: String!, $number: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $number) {
        reviewThreads(first: 100) {
          pageInfo { hasNextPage endCursor }
          totalCount
          nodes {
            id
            isResolved
            comments(first: 50) {
              nodes { id databaseId author { login } body path line diffHunk url }
            }
          }
        }
      }
    }
  }' -f owner=<owner> -f repo=<repo> -F number=<pr-number>
```

**`reviewThreads` is paginated at 100 nodes per page — always check `pageInfo.hasNextPage` and `totalCount` before concluding there are zero (or "only these") unresolved threads.** A PR with >100 total threads (resolved + unresolved combined) will silently truncate the first page, and the missed tail is exactly as likely to hold unresolved threads as the front. If `hasNextPage` is true, repeat the query with `after: $cursor` (add `$cursor: String!` to the query variables) using `pageInfo.endCursor`, and keep paging until `hasNextPage` is false. Concatenate all pages' `nodes` before filtering.

Filter the full concatenated set to `isResolved == false`. Each thread's last comment is what a reply should attach to (use its `id` / `databaseId` for the reply mutation). Take reviewer identity from `comments[0].author.login` — do **not** filter by reviewer; Copilot and human threads get the same treatment.

If there are zero unresolved threads across *all* pages, say so and stop — nothing to do.

## 3. Triage each thread

For every unresolved thread, read the comment body plus enough surrounding code (`diffHunk`, then the live file at `path`/`line`) to judge it. Classify into exactly one bucket:

| Bucket | Criteria | Action |
|---|---|---|
| **Fix + test** | Legitimate, and about a clear logic/correctness bug (wrong behavior, missing validation, null/bounds/off-by-one, wrong exception, etc.) | Write a regression test, then fix |
| **Fix only** | Legitimate, but cosmetic/non-behavioral (typo, naming, comment wording, formatting, doc string) — nothing observable to test | Fix directly, no test |
| **Push back** | Not legitimate — the comment is wrong, the flagged pattern is intentional, or it doesn't apply here | No code change; reply explaining why |
| **Bail out** | Legitimate-looking but the fix is architecturally large, security-sensitive, or the right approach is genuinely ambiguous | No code change; reply flagging it for human judgment |

Before touching any code, print the full triage table (thread → reviewer → one-line summary → bucket) as a status update. This is informational, not a blocking question — proceed immediately after showing it.

## 4. Work each thread

Process **Fix + test** and **Fix only** threads one at a time, each as its own commit (matches this repo's existing convention of one commit per addressed review comment — see `git log --oneline` for examples like `Fix Copilot review comment on PR N: ...`).

### Fix + test

- Pick the seam directly — the public method/behavior the comment is actually about. Don't run a full `/tdd` seam negotiation; a single review comment doesn't warrant it.
- Red: write the test, confirm it fails for the right reason.
- Green: make the minimal fix that passes it.
- Follow the module-scoped test project layout already in the repo (`Common.Tests`, `Devices.Tests`, `LotusLApp.Tests`, `SynthesizerApp/SynthesizerApp.Tests`, `SynthesizerApp/SynthesizerScriptService.Tests`) — put the test in the project matching the code under test.

### Fix only

Make the change directly, no test.

### Both

- Commit with the message convention: `Fix <reviewer> review comment on PR <N>: <what changed>` (a short body explaining why if it's not obvious), plus the repo's standard `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` trailer.
- Reply on the thread (GraphQL `addPullRequestReviewThreadReply` with the thread's `id`, or `gh api repos/{owner}/{repo}/pulls/{number}/comments/{comment_id}/replies` for the REST equivalent) describing what changed and why. Do **not** call the resolve mutation — leave resolution to the reviewer/re-review.

### Push back / Bail out

No commit. Reply on the thread:
- **Push back**: explain concretely why the comment doesn't apply or is incorrect.
- **Bail out**: note that the change needs a design decision and you're flagging it rather than guessing — say what makes it risky (scope, security surface, ambiguity).

Leave the thread unresolved in both cases.

## 5. Push and request re-review

Once every **Fix** thread has its own commit:

```
git push
```

Then re-request a Copilot review. Copilot shows up as a PR review author with login `copilot-pull-request-reviewer` (get the exact login from the existing `reviews[].author.login` in `gh pr view --json reviews`); the requested-reviewers API generally wants the bot-suffixed form:

```
gh api repos/{owner}/{repo}/pulls/{number}/requested_reviewers -f "reviewers[]=copilot-pull-request-reviewer[bot]"
```

If that 4xx's, check `gh pr view --json reviewRequests` to see what login GitHub actually expects for this repo and retry with that.

## 6. Final summary

Report, per thread: bucket assigned, one-line outcome (commit SHA if fixed, or the gist of the reply if pushed back/bailed). End with counts: N fixed-with-test, N fixed-only, N pushed-back, N bailed-out.

## Notes

- Single pass only — this skill does not poll for a new round of Copilot comments after re-requesting review. Re-invoke it once new comments land.
- Never resolve threads yourself — resolution is reserved for the human reviewer or Copilot's own re-review.
- If `git status` shows unrelated uncommitted work before you start, stop and flag it rather than committing over it.
