# PR pack

Four workflows for pull requests, each in Claude Code and Codex:

| Workflow | Claude Code | Codex | What it does |
|----------|-------------|-------|--------------|
| file-pr | `/file-pr` | `$file-pr` | Opens a real PR whose title says why the change matters and whose description starts with the problem. |
| babysit-pr | `/babysit-pr` | `$babysit-pr` | Watches a PR through CI and review with one watcher, fixes real findings, declines scope creep, and reports when it is ready. |
| modernize-pr | `/modernize-pr` | `$modernize-pr` | Decides whether an old PR should still land: MODERNIZE, REWORK, or CLOSE. Rebases and pushes only for MODERNIZE. |
| pr-comment | `/pr-comment` | `$pr-comment` | The rules for every comment an agent posts on your behalf. The other three follow it. |

Serel Memory is not required. When it is present, modernize-pr reads its
accepted decisions.

## Requirements

- `gh`, the GitHub CLI, authenticated (`gh auth status`).
- For babysit-pr: `python3` 3.9 or newer on macOS or Linux, for the bundled
  pr-wait watcher. It writes state and lock files to
  `~/.local/state/pr-wait/`, outside your repository. Inside T3 Code,
  babysit-pr uses T3 Code's own `watch_pull_request` instead and needs no
  Python.

## What it does

- **file-pr** checks whether the branch already has a PR, reads the diff
  against the base, and follows the repository's PR template, title
  convention, and attribution rules. It checks the title and description
  for secrets and private details, then opens a real PR, not a draft, so
  review bots run. When GitHub's GraphQL limit is used up, it opens the PR
  through REST.
- **babysit-pr** reads every existing check, review, and thread first, then
  starts one watcher. It verifies each bot finding against the source,
  fixes real failures, tells flakes apart from them, and declines scope
  creep with a written reason listed as a follow-up. After every watcher
  exit it checks the current head afresh: required checks, reviews,
  unresolved threads, and whether the branch is BEHIND or DIRTY. A PR with
  no checks configured gets no watcher; it says so and stops.
- **modernize-pr** records the PR's state, intent, merge base, and what the
  base gained since. It looks for PRs that replaced this one, recommends
  MODERNIZE, REWORK, or CLOSE, and is willing to say CLOSE. For MODERNIZE it
  rebases, in a disposable worktree when your checkout is dirty, compares
  the series with `git range-diff`, runs focused checks, and pushes with
  `--force-with-lease=<branch>:<observed sha>`.
- **pr-comment** starts every comment with a GitHub note callout,
  `🤖 **<model> responding on behalf of <user>**`, leads with the
  conclusion, cites evidence, keeps facts apart from judgment, checks for
  secrets, confirms GitHub returned a URL, and resolves a thread only after
  the reply posted.

## What it never does

- **It never merges unless you ask.** Even then, never with `--admin`, and
  never while the branch is BEHIND or DIRTY or the required checks are
  unknown.
- **It never closes a PR.** babysit-pr asks first; modernize-pr only
  recommends CLOSE.
- **It never changes a PR's base**, and modernize-pr never grows its scope.
- **It never force-pushes without a lease.** A rewritten branch goes up
  with `--force-with-lease=<branch>:<observed sha>`, so work pushed since
  the agent looked is never overwritten.
- **It never runs two watchers on one PR**, writes its own polling loop, or
  says "still waiting".
- **It never calls checks green when the required checks could not be
  read.** That answer is "unknown".
- **It never writes to the memory bank.**

## Install

Serel Memory is not required for this pack.

```bash
bash /path/to/serel-kit/install.sh /path/to/your-repo --packs pr
```

Installs fourteen files:

```text
.claude/commands/babysit-pr.md
.claude/commands/file-pr.md
.claude/commands/modernize-pr.md
.claude/commands/pr-comment.md
.agents/skills/babysit-pr/SKILL.md
.agents/skills/babysit-pr/agents/openai.yaml
.agents/skills/babysit-pr/scripts/pr-wait
.agents/skills/babysit-pr/LICENSE-tstack
.agents/skills/file-pr/SKILL.md
.agents/skills/file-pr/agents/openai.yaml
.agents/skills/modernize-pr/SKILL.md
.agents/skills/modernize-pr/agents/openai.yaml
.agents/skills/pr-comment/SKILL.md
.agents/skills/pr-comment/agents/openai.yaml
```

Claude Code commands do not trigger on their own, so the other three
workflows point at `.agents/skills/pr-comment/SKILL.md` by path whenever
they post a comment. Keep that file.

Put your preferences, such as attribution lines, title style, or merge
method, in `AGENTS.md`, `CLAUDE.md`, or `.rules`. The workflows read the
repository's rules, and the pack files stay free to upgrade.

## Where pr-wait comes from

`.agents/skills/babysit-pr/scripts/pr-wait` is copied byte for byte from
[tstack](https://github.com/t3dotgg/tstack) by Theo Browne:

- Source: [`skills/babysit-pr/scripts/pr-wait`](https://github.com/t3dotgg/tstack/blob/7de017b3fc9d50c03cf3ecb98fb71e0ca65a78bd/skills/babysit-pr/scripts/pr-wait)
- Commit: `7de017b3fc9d50c03cf3ecb98fb71e0ca65a78bd`
- sha256: `90393f85b95b78bff1b039744bdfb09dc88ff2b430e1c3df687ee6f449c97214`
- License: MIT, Copyright (c) 2026 Theo Browne. The full text travels with
  the script, in `.agents/skills/babysit-pr/LICENSE-tstack`.

Check an installed copy with
`shasum -a 256 .agents/skills/babysit-pr/scripts/pr-wait`. The four
workflows adapt tstack's `file-pr`, `babysit-pr`, `modernize`, and
`leaving-pr-comments` skills; they are rewritten for this Kit, not copied.

## Acceptance exercise

Automated tests prove the pack installs byte for byte, that both adapters are
present and paired, and that pr-wait starts. They cannot prove the workflows
behave on a real pull request in either CLI: that takes actions on GitHub, so
a person runs it. Use a throwaway repository you own, with one CI check that
runs on pull requests and nobody else watching.

### Offline first

From the repository root:

```bash
python3 .agents/skills/babysit-pr/scripts/pr-wait --help     # exits 0
python3 .agents/skills/babysit-pr/scripts/pr-wait not-a-pr   # exits 2
```

### In Claude Code

1. On a branch with one small commit, type `/file-pr`.

   Expect `FILE-PR: opened — <URL>`. On GitHub it is a real PR, not a
   draft. Its title says why the change matters, and its description starts
   with the problem and ends with an attribution line.
2. Type `/babysit-pr <number>`.

   Expect it to read the existing checks, reviews, and threads before it
   starts one watcher: pr-wait under the Monitor tool, or T3 Code's watcher.
   Nothing is printed while the check runs. When it passes, expect a
   readiness check, then `BABYSIT-PR: ready — <URL>`. The PR is not merged.
3. Type `/pr-comment <number> "acceptance check: please ignore"`.

   Expect a `URL:` line. Open it: the comment starts with the note callout
   naming the model and your GitHub login.

### In Codex

1. Push one commit to the base branch that touches a file the PR touches,
   then type `$modernize-pr <number>`.

   Expect `MODERNIZE-PR: MODERNIZE - <URL>`, or a reasoned REWORK or CLOSE.
   The report lists the merge base, the base changes since, and a
   range-diff summary. If it pushed, it used
   `--force-with-lease=<branch>:<sha>`. The PR is not merged.
2. Type `$babysit-pr <number>`.

   Expect the same report shape as in Claude Code, with `-` in place of the
   em dash. pr-wait runs as one long command.

### With no checks configured

In a repository with no CI, open a PR and type `/babysit-pr <number>` or
`$babysit-pr <number>`. Expect `BABYSIT-PR: no checks configured`, and no
pr-wait process: `pgrep -f pr-wait` prints nothing.

### It failed if

- It merged, closed, or changed the base of a PR nobody asked it to.
- It opened a draft.
- It started a second watcher, or a polling or `sleep` loop of its own.
- It said or posted "still waiting".
- It called the checks green when the required checks could not be read.
- It pushed a rewritten branch without `--force-with-lease=<branch>:<sha>`.
- A comment lacks the callout, or a thread was resolved before its reply
  posted.
- It started pr-wait on a PR with no checks.

## Relationship to Serel Memory

Serel Memory is not required. When it is present, modernize-pr follows its
`docs/workflow-contract.md`: it resolves one scope and one effective bank,
reads the accepted decisions that apply to the PR whatever their date, treats
proposed decisions as open questions, and reads them before moving into a
disposable worktree, which would not contain an ignored or Git-excluded bank.
It never writes to the bank. The other three workflows do not read it. Serel
Kit never installs, upgrades, or reconfigures Serel Memory.
