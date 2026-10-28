---
name: file-pr
description: "Open a real pull request for the current branch, with a title that says why it matters and a description that starts with the problem. Never merges."
---

# File PR

Open a pull request for the current branch that a reviewer can understand in
one read: a title that says why the change matters, and a description that
starts with the problem. It opens a real PR, not a draft, and never merges.

Call it as `/file-pr` in Claude Code or `$file-pr` in Codex, optionally with
`--base <branch>`. "File it and babysit it" continues with `babysit-pr` once
the PR exists. For example:

```text
file-pr
file-pr --base release/2.4
file-pr and babysit it        # files, then continues with babysit-pr
```

## Trigger

Use it when the user asks to file, open, or create a pull request for work on
the current branch.

Do not use it to update an existing PR, to merge, or to open a draft. If a PR
already exists for the branch, report it and stop.

## Required reads

1. `gh auth status`, the current branch, `git status`, and whether a PR
   already exists for the branch: `gh pr list --head <branch> --state all`.
2. The base branch: `--base` if given, otherwise the repository's default
   branch (`gh repo view --json defaultBranchRef`). Fetch it fresh
   (`git fetch origin <base>`).
3. The change against that base: `git log origin/<base>..HEAD` and
   `git diff origin/<base>...HEAD`. Check that it contains what the user's
   goal needs and nothing else.
4. The repository's PR template, if it has one:
   `.github/pull_request_template.md`, `.github/PULL_REQUEST_TEMPLATE.md`,
   `.github/PULL_REQUEST_TEMPLATE/`, `docs/pull_request_template.md`, or
   `pull_request_template.md` at the root.
5. The title convention: recent merged PRs
   (`gh pr list --state merged --limit 10 --json title`) and recent commits
   on the base.
6. Attribution rules, in this order: the repository's (`AGENTS.md`,
   `CLAUDE.md`, `CONTRIBUTING.md`), then your harness's own instructions.
7. The user's original request, in their words. The description's problem
   statement comes from it.

If a `gh` read above fails because the GraphQL rate limit is used up
(`gh api rate_limit --jq .resources.graphql`), read it through REST, which
has a separate limit:

- The default branch:
  `gh api repos/<owner>/<repo> --jq .default_branch`.
- An open PR for the branch:
  `gh api "repos/<owner>/<repo>/pulls?head=<head-owner>:<branch>&state=open"`.
  `<head-owner>` owns the repository the branch was pushed to: the fork's
  owner for a fork, otherwise `<owner>`. An empty list means none is open.
- Recent merged titles:
  `gh api "repos/<owner>/<repo>/pulls?state=closed&sort=updated&direction=desc&per_page=30" --jq '[.[] | select(.merged_at != null)] | .[:10] | .[].title'`.

## Allowed writes

- Pushing the current branch to its own remote branch when it is not there
  yet or the remote is behind: `git push -u origin <branch>`. A push that
  would need force stops the workflow.
- One pull request: `gh pr create`. The body goes through a temporary file
  outside the repository.
- No follow-up comment unless the user's request needs one. When it does,
  follow `.agents/skills/pr-comment/SKILL.md`.

The user asking for a PR is the approval to open it. Nothing else: no commits,
no merge, no edits to other PRs.

## Workflow

1. Run the preflight in Required reads. Stop on anything in Stop conditions.
2. Read the diff and commits. Confirm the change matches the goal: no
   unrelated files, no debugging leftovers.
3. Write the title. PR titles usually become commit messages, so follow the
   repository's convention. Say why the change matters, not which mechanism
   it uses:

   > Weak: `refactor(cache): add LRU eviction to the session store`
   >
   > Better: `fix(cache): stop the session store growing until the server runs out of memory`

4. Write the description. Open with the problem in plain words, from the
   user's original request, then the solution in a sentence or two. Do not
   lead with an inventory of changed files and functions:

   > Weak: Added an LRU wrapper to SessionStore, a maxEntries option, an
   > eviction counter, and tests for eviction order.
   >
   > Better: Busy servers ran out of memory after a few days because sessions
   > were never dropped. Now the oldest ones are evicted past a set limit.

   Fill in every section the template asks for. Write "not run" or "none"
   rather than inventing results. End with the attribution the rules in
   Required reads call for. If they say nothing, end with
   `Created with <model> in <harness>.`, naming any subagent models that
   wrote part of the change. Use the model name the harness reports; if it
   reports none, name only the harness.
5. Check the title, description, quotes, and attachments for secrets and
   private details: tokens, keys, internal URLs, personal data, and private
   memory bank content. If the diff itself appears to contain one, stop and
   ask.
6. Push the branch if needed, then open a real PR, not a draft, so review
   bots run:
   `gh pr create --base <base> --head <branch> --title <title> --body-file <file>`.
   If it fails because the GraphQL rate limit is used up
   (`gh api rate_limit --jq .resources.graphql`), open it through REST, which
   has a separate limit:
   `gh api repos/<owner>/<repo>/pulls -f title=<title> -f head=<branch> -f base=<base> -F body=@<file>`.
   For a branch pushed to a fork, send `-f head=<head-owner>:<branch>`
   instead, with `<head-owner>` as in Required reads.
7. Confirm GitHub returned the PR URL. If the user also asked to babysit it,
   continue with `babysit-pr` (`.agents/skills/babysit-pr/SKILL.md`).

## Output contract

```text
FILE-PR: <opened | already exists | not opened> — <PR URL>
TITLE: <title>
BASE: <base> <- <branch> (<n> commits, <n> files)
TEMPLATE: <path | none>
TITLE STYLE: <where the convention came from>
PRIVACY CHECK: <clean | removed: <what>>
ATTRIBUTION: <the line used, and the rule it came from>
```

Then the description exactly as filed.

## Stop conditions

Stop and ask, before pushing or opening anything, when:

- `gh` is missing or not authenticated.
- The current branch is the base branch, or HEAD is detached.
- A PR for this branch is already open. Print its URL and stop.
- The branch has no commits ahead of the base.
- There are uncommitted changes. Ask whether they belong in this PR; do not
  commit them yourself.
- The diff contains changes unrelated to the goal, or something that looks
  like a secret or private detail.
- Pushing would need force, or the branch has no GitHub remote.
- The template asks for something you do not have, such as a ticket number.
  Ask rather than invent it.
- `gh pr create` failed for any reason other than the GraphQL rate limit.
  Report the error.
