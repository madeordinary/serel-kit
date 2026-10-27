---
description: Watch a pull request through CI and review with one watcher, fix real findings, decline scope creep, and report when it is ready. Merges only when asked.
---

# /babysit-pr

See a pull request through CI and review. Use one watcher, fix what is really
broken, decline what is not worth doing with a written reason, and report
when the PR is ready. It merges only when the user explicitly asks.

Usage:

```text
/babysit-pr 482
/babysit-pr https://github.com/acme/shop/pull/482
/babysit-pr                          # the PR for the current branch
/babysit-pr 482 and merge when ready
```

## Trigger

Use it when the user asks to watch, monitor, or babysit a PR, or when
`/file-pr` was asked to babysit the PR it opened.

Do not use it to file a PR (`/file-pr`) or to revive an old one
(`/modernize-pr`). Do not use it to merge a PR nobody asked you to merge.

## Required reads

Read all of this before starting any watcher. pr-wait's first run for a PR
records what already exists as a baseline and reports only what comes after,
so anything you skip here you will never hear about.

1. `gh auth status`, and `python3 --version` (3.9 or newer) unless T3 Code's
   watcher will be used.
2. The PR: `gh pr view <pr> --json number,url,state,headRefName,headRefOid,baseRefName,mergeStateStatus,reviewDecision`.
3. The checks. The required checks for the base come from rulesets
   (`gh api repos/<owner>/<repo>/rules/branches/<base>`) and classic branch
   protection
   (`gh api repos/<owner>/<repo>/branches/<base>/protection/required_status_checks`;
   a 404 means none are set). Any other failure, such as HTTP 403, means the
   required checks are **unknown**. Then the checks reported on the head:
   `gh pr checks <pr>`.
4. Every existing review, comment, and review thread, resolved or not:
   `gh pr view <pr> --comments`, and the review threads with their
   `isResolved` state (`gh api graphql`, `pullRequest.reviewThreads`).
5. Whether the repository uses Greptile or Macroscope: their checks or
   comments on this PR or recent ones. If `.macroscope/check-run-agents/*.md`
   exists, read it before replying to a Macroscope finding; its findings cite
   those rules.
6. `.agents/skills/pr-comment/SKILL.md`, before posting any comment.
7. The repository's commit and attribution rules (`AGENTS.md`, `CLAUDE.md`,
   `CONTRIBUTING.md`), before pushing a fix.

Use the latest push only to discard superseded check results and news you
have already handled. A finding that is still open stays open after a push:
reassess it against the current code, and do not drop it because it is older
than the push.

## Allowed writes

Asking you to babysit a PR approves these, and only these:

- pr-wait's state and lock files under `~/.local/state/pr-wait/`, outside
  the repository. pr-wait writes them itself.
- Commits and pushes to the PR's own head branch, to fix findings or bring
  it up to date with its base. Plain pushes; after a rebase,
  `git push --force-with-lease=<branch>:<head sha you observed>` and nothing
  else. Never push to the base or any other branch.
- Comments and replies, and resolving a bot's thread after your reply has
  posted, following `.agents/skills/pr-comment/SKILL.md`.
- Re-running failed CI jobs once when their log shows an infrastructure
  flake: `gh run rerun <run-id> --failed`.
- T3 Code's `watch_pull_request` and `unwatch_pull_request` on this PR.

A merge needs the user's explicit request. Closing needs the user's answer to
a question you ask. Changing the base, the title, the description, or another
PR is not part of this workflow.

## Steps

1. Run the reads above. Stop on anything in Stop conditions.
2. Act on what already exists: failing checks, open findings, unresolved
   threads, and a BEHIND or DIRTY branch.
3. If nothing is configured to report, stop: see "No checks configured" in
   Stop conditions. Otherwise start exactly one watcher (below).
4. Each time the watcher reports something, act on it (below). When an event
   needs no action, end your turn without a message.
5. Whenever the watcher exits, run the readiness check on the current head.
6. Stop when the PR is ready, blocked on the user, merged, or closed, and
   print the output contract.

## Watching

Use one watcher per PR. Never write your own polling or `sleep` loop, and
never run two watchers on the same PR. Every watcher on a GitHub account
shares one rate limit.

### In T3 Code: `watch_pull_request`

- Only the thread that owns the PR watches it. A delegated child task, such
  as a reviewer, never calls `watch_pull_request`; its parent owns the PR.
- After step 2, call `watch_pull_request` and end your turn. T3 Code wakes
  you when a check fails, the required checks pass, someone comments or
  reviews, or the branch conflicts.
- A wake is news, not a merge decision. It reports conflicts but not BEHIND,
  so the readiness check still runs.
- Call `unwatch_pull_request` before you hand off: when the PR is ready, when
  you are blocked, and before you ask the user anything. A merge or close
  ends the watch by itself.
- "Stopped watching, could not read it" usually means the GitHub rate limit
  is used up. See GitHub rate limits below.

### Everywhere else: pr-wait

From the repository root (or with the script's absolute path):

```bash
python3 .agents/skills/babysit-pr/scripts/pr-wait <pr> --until green
```

- Use `--until ready` only when the repository uses Greptile or Macroscope.
  It also waits for their review and for no unresolved threads. Use
  `--until green` everywhere else.
- In Claude Code, run it under the Monitor tool with the longest timeout the
  tool allows. Each line pr-wait prints wakes you. When the monitor expires,
  start it again; the expired process releases its lock, and pr-wait's
  state file still knows what it has reported. If the Monitor tool is not
  available, run it as one background command; it ends on its own.
- Start it again after you push, after you handle an exit 1, after a resume,
  and after the monitor expires. If more than six hours passed since it last
  ran, pr-wait treats its state as stale and records a fresh, silent
  baseline: read the PR's comments and threads again first.

pr-wait's exit codes:

| Exit | Meaning | What you do |
|------|---------|-------------|
| 0 | The `--until` condition was met, or the PR merged | Readiness check |
| 1 | It needs action: a required check failed, the branch conflicts, the PR closed, `ready` is blocked by threads or BEHIND, or GitHub stayed unreachable | Act on the last line it printed, then the readiness check |
| 2 | Bad input, unknown PR, or another pr-wait already watches this PR | Fix the input. If another pid watches, do not start a second; kill the old one only if its events never reach you |

## Readiness check

Run it after every watcher exit, and again right before any merge. Check the
current head, which may not be the one the watcher saw:

1. The head SHA: `gh pr view <pr> --json headRefOid,state,mergeStateStatus,reviewDecision`.
2. Required checks on that head, read as in Required reads. A required check
   that has not reported is pending, not passed. If the base requires none,
   every reported check counts. If the required list could not be read, the
   answer is "unknown", never "green", whatever the reported checks show.
3. Reviews: `reviewDecision`, and how many review threads are unresolved.
4. Merge state: BEHIND or DIRTY means the branch must be updated first.
   UNKNOWN means GitHub is still computing it; read it once more before you
   report.

The PR is ready only when the required checks are green on the current head,
no review asks for changes, no thread is unresolved, and the merge state is
neither BEHIND nor DIRTY.

## Acting on news

- Verify every bot finding against the current source before changing code.
  Bots are useful and often wrong.
- Fix real findings and real CI failures in focused commits on the PR's
  branch. Run the focused checks for what you touched before you push.
- Read a failing job's log (`gh run view <run-id> --log-failed`) before
  deciding. A failure caused by the change or the branch is real: fix it.
  A lost runner, a network timeout, or an outage in an unrelated service is
  an infrastructure flake: do not change code for it. Re-run it once and say
  which log line shows it is a flake. If it fails the same way again, treat
  it as real or ask.
- When a finding is not worth acting on, reply with a written reason and
  resolve the bot's thread after the reply posts. Leave a person's thread for
  that person.
- CodeRabbit is advisory. Treat its findings like any other, but never wait
  for it and never hold a merge for it.
- Keep the PR at the size the user's goal needs. Review loops grow a PR one
  cheap-looking fix at a time. Fix real bugs in the intended case. Decline
  the rest with a written reason and list them as follow-ups: tests nobody
  needs, guards for cases that do not matter, extra integration or
  compatibility, and small performance costs. Prefer the fix that deletes or
  narrows code.
- Never say or post "still waiting". If nothing changed, say nothing.

## Base branch and merging

- pr-wait reports new base commits that touch this PR's files, and a BEHIND
  or DIRTY branch. To update the branch, rebase it onto the freshly fetched
  base and push with `--force-with-lease=<branch>:<head sha you observed>`.
  If the repository's rules say to merge the base in instead, do that. If a
  conflict is not mechanical, stop and ask.
- If an overlapping PR makes this one obsolete, stop watching, tell the user,
  and ask before closing it.
- Merge only when the user explicitly asked. Right before merging, run
  `git fetch` and the readiness check. Never merge with `--admin`. Never
  merge while the branch is BEHIND or DIRTY, while required checks are
  unknown, or when base commits that landed after the last green run touch
  this PR's files: update the branch, push, and wait for green again. Use
  the merge method the user or the repository asks for.
- Otherwise, report that the PR is ready and stop.

## GitHub rate limits

`gh pr create`, `gh pr view`, and `gh pr checks` use GraphQL. When GraphQL is
used up, REST has its own limit and usually has room: read the PR with
`gh api repos/<owner>/<repo>/pulls/<pr>` and checks with
`gh api repos/<owner>/<repo>/commits/<sha>/check-runs`. Before watching again,
run `gh api rate_limit --jq .resources.graphql`. If `remaining` is near 0,
wait for `reset` with one background command, then watch again. Never
restart a watcher in a tight loop.

## Output contract

When you stop, print:

```text
BABYSIT-PR: <ready | blocked | needs you | merged | closed | no checks configured> — <PR URL>
HEAD: <short sha>
CHECKS: <green | failing: <names> | pending | unknown — <why>> (required: <names | none set | unreadable>)
REVIEWS: <approved | changes requested | review required | none>; unresolved threads: <n>
MERGE STATE: <CLEAN | BEHIND | DIRTY | BLOCKED | UNSTABLE | UNKNOWN>
FIXED: <finding — commit> | none
DECLINED: <finding — reason, listed as a follow-up> | none
FLAKES: <check — log evidence — re-run result> | none
NEXT: <the one thing you need from the user> | ready; merge when you say so
```

Between events, print nothing when an event needs no action.

## Stop conditions

Stop and report, without starting a watcher or pushing, when:

- `gh` is missing or not authenticated.
- `python3` is missing or older than 3.9 and pr-wait is the watcher.
  pr-wait also needs macOS or Linux.
- **No checks configured.** The base requires no checks, or the list could
  not be read, and the head reports none. pr-wait would wait forever. Report
  `no checks configured`, adding `required checks: unknown` when the list
  could not be read. If the head was pushed moments ago, read the checks
  once more first; checks take a few seconds to register.
- The PR does not exist, is closed, or is merged.
- Another pr-wait already watches this PR.
- You are a delegated child task in T3 Code. Report to the thread that owns
  the PR instead of watching.

Stop and ask when:

- A finding needs a product, scope, or architecture decision.
- A rebase conflict is not mechanical.
- You cannot push to the PR's branch, for example a fork that does not allow
  maintainer edits. Report what needs fixing.
- A `--force-with-lease` push is rejected. Fetch and reassess; never
  overwrite work you have not seen.
- An overlapping PR makes this one obsolete.
- You were asked to merge and the readiness check does not pass.

## Where pr-wait comes from

`.agents/skills/babysit-pr/scripts/pr-wait` is copied byte for byte from
[tstack](https://github.com/t3dotgg/tstack) at commit
`7de017b3fc9d50c03cf3ecb98fb71e0ca65a78bd`
([source](https://github.com/t3dotgg/tstack/blob/7de017b3fc9d50c03cf3ecb98fb71e0ca65a78bd/skills/babysit-pr/scripts/pr-wait)),
sha256 `90393f85b95b78bff1b039744bdfb09dc88ff2b430e1c3df687ee6f449c97214`.
MIT, Copyright (c) 2026 Theo Browne; the license text is in
`.agents/skills/babysit-pr/LICENSE-tstack`. Do not edit the script: the hash
is how anyone can check it is still the upstream file.
