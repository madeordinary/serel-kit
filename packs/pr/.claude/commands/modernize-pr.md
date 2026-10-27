---
description: Bring an old pull request up to date, or decide it should not land, with MODERNIZE, REWORK, or CLOSE and the evidence. Rebases with a lease; never merges, closes, or changes the base.
---

# /modernize-pr

Modernize the idea, not just the branch. A clean rebase does not prove that a
PR still belongs in the product. This workflow works out what the PR was for
and what changed around it, then recommends MODERNIZE, REWORK, or CLOSE. Only
MODERNIZE rebases and pushes.

Usage:

```text
/modernize-pr 311
/modernize-pr https://github.com/acme/shop/pull/311
/modernize-pr 311 --scope projects/storefront
```

## Trigger

Use it when the user asks to rebase, update, revive, or modernize an old PR,
or asks whether an old PR should still land.

Do not use it for a PR that only needs CI and review attention
(`/babysit-pr`). Do not use it to merge or close a PR.

## Required reads

1. `gh auth status`, and `git status` of the current checkout. Uncommitted
   changes there belong to the user.
2. Fresh refs: `git fetch origin <base> pull/<pr>/head`, plus any other
   branch related to the work.
3. The PR, recorded before anything else:
   `gh pr view <pr> --json url,state,baseRefName,headRefName,headRepositoryOwner,headRefOid,author,title,body,commits,reviewDecision,statusCheckRollup,closingIssuesReferences,maintainerCanModify`.
   Keep the head SHA you observed here: the push lease is tied to it.
4. The title, body, linked issues, commits, review threads, and the complete
   diff (`gh pr diff <pr>`).
5. The merge base, `git merge-base origin/<base> <head sha>`, and what the
   base gained since then: `git log --oneline <merge-base>..origin/<base>`
   and `git diff <merge-base> origin/<base> -- <paths the PR touches>`.
6. Merged and open PRs that might replace or compete with it:
   `gh pr list --state all --search "<keywords>"`.
7. Serel Memory's decisions, when `.serel-memory.json` exists (below).
8. `.agents/skills/pr-comment/SKILL.md`, only if the user asked for a comment.

### With Serel Memory

Memory is optional here. When the repository has `.serel-memory.json`, read
its decisions, read-only, in the current checkout **before** moving into any
disposable worktree. A fresh worktree does not contain ignored or
Git-excluded bank files, such as `memory-bank.local/`.

1. **Resolve the scope** ("Resolving scope" in `docs/workflow-contract.md`).
   `--scope <path>` selects it and `.` is the repo root; otherwise the project
   root the current directory sits in; otherwise the repo root. Exactly one
   scope per invocation, never a remembered one. A `--scope` that is not a
   project root stops the workflow with the list of valid selectors.
2. **Resolve the effective bank** ("Resolving the effective bank"). Inside
   that scope root, `memory-bank.local/` is the effective bank when it exists,
   otherwise `memory-bank/`.
3. **Read the decisions.** `decisionLog.md` in the effective bank, and any
   ADR it links that bears on what the PR changes.
4. **Apply accepted decisions whatever their date.** Dates are hints, not
   filters: a decision older than the merge base still binds the PR, and one
   recorded after it is the likeliest to conflict. A proposed decision is not
   a requirement; report it as an open question.
5. If the PR's files belong to a different project scope, say so and offer to
   re-run with that `--scope`. Never read across scopes.

A bank whose core files are missing, empty, or still only template
placeholders has no decisions to read. Say so and carry on; this workflow
does not need Memory. A `memory-bank.local/` overlay is partial by design,
and the files it lacks are not an uninitialized bank. Never write to the bank.

## Allowed writes

- `git fetch`.
- A disposable worktree outside the current checkout, at the recorded head,
  when the current checkout is dirty or in use for other work. Remove it when
  you are done, if you created it. Never stash, reset, or commit the user's
  own changes.
- For MODERNIZE, or for REWORK when the user also asked for the rework: the
  rebased commits on the PR's head branch, pushed with
  `git push --force-with-lease=<branch>:<observed sha> <remote> HEAD:<branch>`
  and nothing else. Never an unqualified `--force`, and never a lease without
  the SHA you observed.
- No PR comment unless the user asked for one. Then follow
  `.agents/skills/pr-comment/SKILL.md`.
- Nothing in the memory bank.

Asking to modernize a PR approves the rebase and the push. It does not
approve merging, closing, changing the base branch, or growing the scope.

## Steps

1. Run the preflight (reads 1 and 2). Stop on anything in Stop conditions.
2. **Establish the intent.** Record the PR's URL, state, base, head
   repository and branch, head SHA, author, checks, and review state. Read
   everything in read 4. State the smallest coherent goal the PR was trying
   to reach before judging how it reaches it.
3. **Read Memory's decisions now**, if the repository has them, before any
   worktree exists.
4. **Check what changed around it.** Read the base's commits since the merge
   base, and look for PRs that replaced or compete with this one. Look past
   overlapping lines:

   - Has the same user-facing problem already been solved?
   - Did APIs, types, schemas, dependencies, or boundaries change?
   - Do both sides now claim the same behavior or invariant?
   - Was the code it changes deleted, moved, or deliberately simplified?
   - Would landing it bring back old behavior, or create a second way to do
     the same thing?
   - Does an accepted decision now rule it out or reshape it?
   - Is the benefit still worth the cost of maintaining it?

   Git reporting no conflicts does not make the PR current.
5. **Choose a disposition before pushing anything:**

   - **MODERNIZE**: the goal still matters and the implementation is still
     the right shape. Rebase, resolve, check, push.
   - **REWORK**: the goal still matters, but a mechanical rebase would keep
     the wrong implementation. Describe the smallest credible rewrite and
     stop before pushing, unless the user also asked for the rework.
   - **CLOSE**: the PR is superseded, obsolete, pointed the wrong way, or no
     longer worth its cost. Cite the evidence and stop. Do not rebase an
     obsolete branch, and do not close it: that is the user's call.

   Be willing to recommend CLOSE. Age alone is not evidence, and effort
   already spent is not a reason to keep a PR alive.
6. **Rebase and push**, for MODERNIZE, or for a REWORK the user also asked
   for (make the rewrite once the rebase is done):

   1. Work at the recorded head, in a disposable worktree when the current
      checkout is dirty or busy:
      `git worktree add --detach <dir outside the repo> <head sha>`.
   2. Rebase onto the freshly fetched base: `git rebase origin/<base>`.
   3. Resolve each conflict by the PR's intent and the base's newer
      invariants, accepted decisions included. If a conflict shows a product
      or architecture disagreement, stop and reconsider the disposition
      instead of guessing.
   4. Compare the old and new series:
      `git range-diff <merge-base>..<old head> origin/<base>..HEAD`. Read the
      final diff (`git diff origin/<base>...HEAD`). Confirm no intended
      behavior disappeared and nothing already on the base came back.
   5. Run the repository's focused checks for the touched area. Tell real
      failures apart from ones that already fail on the base and from
      infrastructure trouble.
   6. Push with the lease tied to the head you observed. If the lease is
      rejected, someone pushed since you looked: fetch and reassess, never
      overwrite.
7. Report. Do not merge the PR.

## Output contract

```text
MODERNIZE-PR: <MODERNIZE | REWORK | CLOSE> — <PR URL>
WHY: <the reason, in one or two sentences>
INTENT: <the smallest coherent goal>
PR: <state>; base <base> at <sha>; head <owner:branch> at <observed sha>; merge base <sha>
BASE CHANGES: <meaningful changes since the merge base, with commits or PRs> | none that matter
CONFLICTS: <conceptual conflicts> | none found
DECISIONS: <accepted decisions that apply, and any conflict> | none apply | no Serel Memory
REBASE: <pushed <old sha> -> <new sha> | not performed — <why>>
RANGE-DIFF: <how the new series differs from the old> | not run
CHECKS: <command — result>, ... | not run
UNVERIFIED: <what you could not verify> | nothing
NEXT: <the remaining decision or work>
```

Keep what the commands showed apart from what you recommend. Say what could
not be verified instead of sounding sure.

## Stop conditions

Stop and report when:

- `gh` is missing or not authenticated.
- The PR does not exist, is merged, or is closed.
- The current checkout is dirty and a disposable worktree cannot be created.
- `--scope` names something that is not a project root. List the valid
  selectors.
- The disposition is REWORK and the user did not ask for the rework, or it is
  CLOSE.
- A conflict shows a product or architecture disagreement.
- The PR conflicts with an accepted decision. Report it; never rebase past
  it.
- You cannot push to the PR's branch, for example a fork that does not allow
  maintainer edits. Report the disposition and what the rebase needs.
- The push lease is rejected.
- Focused checks fail because of the rebase and the fix is not mechanical.
