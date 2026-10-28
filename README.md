# Serel Kit

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg) ![Works with Claude Code + Codex](https://img.shields.io/badge/works%20with-Claude%20Code%20%2B%20Codex-5436DA) ![Version 0.4.0](https://img.shields.io/badge/version-0.4.0-blue)

Optional workflow packs for AI coding agents, built to fit
[Serel Memory](https://github.com/madeordinary/serel-memory).

Created and maintained by [Gus Feliciano](https://github.com/gusfeliciano) through
[Made Ordinary](https://github.com/madeordinary).

## Do I need Memory first?

It depends on the pack:

- **writing** (`/polish`, `$polish`) needs nothing else — run [Guided setup](#guided-setup) below and use it.
- **verify** (`/verify-map`, `$verify-map`) needs [Serel Memory](https://github.com/madeordinary/serel-memory) installed before it can be added, and an initialized memory bank when it runs.
- **pr** (`/file-pr`, `/babysit-pr`, `/modernize-pr`, `/pr-comment`; `$file-pr` and so on in Codex) needs no Memory. It needs an authenticated `gh`, and `babysit-pr` needs `python3` 3.9 or newer on macOS or Linux. `modernize-pr` reads Memory's accepted decisions when Memory is present.

Want project continuity and Kit packs together? Use [Set up Memory and Kit together](https://github.com/madeordinary/serel-memory#set-up-memory-and-kit-together). One conversation handles new ideas and existing projects, preserves what is already installed, and helps you choose packs. You can keep Memory local while sharing Kit workflows with your team. Once setup is complete, skip Guided setup here.

Already installed? [Update an existing installation](#update-an-existing-installation) below upgrades Kit's packs only. Memory has its own update prompt. When updating both, start with Memory; writing-only Kit use does not require Memory.

## What this is

A workflow is a markdown file that tells a coding agent how to do one job:
what to read first, what it is allowed to change, what to hand back, and when
to stop and ask you. Both Claude Code and Codex read these as skills. Each
workflow has one source, `.agents/skills/polish/SKILL.md`, which Codex runs as
`$polish`. Claude Code runs a byte-identical copy at
`.claude/skills/polish/SKILL.md` as `/polish`. Both are plain text you can
read and edit. If you customize one, change the other the same way, or Claude
Code and Codex will run different text.

Serel Kit is a small collection of those, grouped into **packs**, plus an
installer that copies a pack into your repository. Every pack ships each
workflow once, with its Claude Code copy, so it works in Claude Code and in
Codex.

Serel Memory is the engine: it gives a project a memory bank the agent reads at
the start of every session. Serel Kit is optional workflows that follow Memory's
rules. You can use one pack here without the other.

## Who it's for

- **Product managers.** You do not need to write code to use this. The writing
  pack rewrites text — a status update, a spec section, release notes — to
  plain, concrete language and shows you what it changed. The verify pack keeps
  a written record of how to check each feature by hand, and when someone last
  did.
- **Developers new to coding agents.** Read the packs' markdown files.
  They are short. They are how you learn what a workflow file is made of.
- **Developers already using Serel Memory.** These are the workflows that did
  not belong in the core, held to the same contracts and the same one-source rule.

## The boundary rule

**Serel Memory owns bank structure, lifecycle, and compatibility. Serel Kit
supplies optional workflows that follow those contracts.**

In practice that means Serel Kit never installs, upgrades, or reconfigures
Serel Memory. The installer detects Memory and refuses a pack that needs it,
with a link to Memory's own install instructions. It never writes to
`memory-bank/`, `.rules`, `.serel-memory.json`, `AGENTS.md`, or `CLAUDE.md`,
and never adds, edits, or removes Memory's Git exclusions.

## Guided setup

Paste this into Claude Code or Codex at the root of your project. The agent
looks before it asks, and nothing is installed until you approve the plan.

```text
Set up Serel Kit (https://github.com/madeordinary/serel-kit) in this repository.

1. Inspect first and change nothing: the Git root and status, any .claude/ and .agents/ files, .serel-kit.json, and whether Serel Memory is present (.serel-memory.json, memory-bank/).
2. Ask me one question at a time, at most four in all, and skip any whose answer you already know: the project's stage, the capabilities I want, which agents I use (Claude Code, Codex, or both), and whether Kit files should be shared through Git or kept local to this clone.
3. Recommend the fewest supported packs that cover those capabilities. writing needs nothing else. verify needs Serel Memory to install and an initialized memory bank when it runs. pr needs no Memory, but needs an authenticated gh, and python3 3.9 or newer on macOS or Linux for babysit-pr.
4. Compare my existing commands and skills, installed ones included, with each chosen pack's workflows by what they do, not by name. The Claude Code copy and the Codex source of one Kit workflow are one workflow, not an overlap, and a specialized workflow with a different job is not a duplicate. Report each overlap in the plan: both paths, my rules to keep, which should be primary, and whether to keep both (with the reason recorded in my workflow docs), migrate, or leave that pack out. An unresolved overlap leaves that whole pack out. Always install complete packs. Do not delete, disable, merge, or move my workflows unless I approve a migration with concrete diffs.
5. If I want Serel Memory, or a chosen pack needs it, and it is missing, follow https://github.com/madeordinary/serel-memory/blob/main/docs/serel-setup.md. Do not install Memory silently or run its seeding interview from here.
6. Carry every answer I already gave into whichever setup runs next, so no question is asked twice.
7. Before writing anything, show me the exact install command, every path it writes, and what Git will share or keep local. For a local install, show me the installer's preview. Wait for my approval.
```

Answers carry forward: if the prompt hands off to Serel Memory's setup, that
setup receives what you already said instead of asking again. The Git
visibility answer is applied to Kit and Memory separately. Kit's `--local`
covers only Kit's files, and Memory's setup decides for Memory's files.
Mixing them is fine. You can share Kit skills through Git while keeping
the memory bank local, or the reverse.

The installer compares paths, not purposes. It never overwrites your files,
but a workflow of yours under another name, say a `/proofread` of your own,
can do the same job as a pack's and then compete with it. Both prompts ask
the agent to compare workflows by what they do, pack by pack, and to leave a
pack out until you choose. Keeping both is recorded in your own docs;
retiring one of yours is a separate change you approve. This is an
agent-guided review, not a guarantee, and it needs no Memory bank.

Inspect the project's actual per-agent discovery inventory, including
`.claude/commands/`, `.claude/skills/` and `.agents/skills/` when present,
plus relevant global workflows already surfaced by the CLI; do not search
unrelated private/global folders or modify global workflows. Same-path
customizations still follow the installer's conflict rules.

On setup reruns, inspect existing workflows even when no files would be
added. Respect previously recorded coexistence while its purpose still
applies. A migration proposal shows the custom behavior to preserve, exact
diffs, retired files, updated references, and where originals remain
recoverable. Preserve populated memory, decisions, and authorizations.
Committed Git history preserves only committed bytes; back up uncommitted,
untracked, or excluded originals before retirement, outside discoverable
command/skill directories. Setup alone authorizes no retirement. Resolve
choices in the existing plan approval without repeating answered questions.
After approved changes, check each agent's entry points and current workflow
docs against the installed files. These rules apply to upgrades too.

| Piece | Owner | Paths | Needs | Shared or local |
|-------|-------|-------|-------|-----------------|
| writing pack: `/polish`, `$polish` | Serel Kit | `.claude/skills/polish/SKILL.md`, `.agents/skills/polish/` | nothing | Kit's choice: shared by default, or `--local` |
| verify pack: `/verify-map`, `$verify-map` | Serel Kit | `.claude/skills/verify-map/SKILL.md`, `.agents/skills/verify-map/` | `.serel-memory.json` to install; an initialized bank to run | Kit's choice; the maps it writes live in the bank |
| pr pack: `/file-pr`, `/babysit-pr`, `/modernize-pr`, `/pr-comment`; `$file-pr` and so on in Codex | Serel Kit | `.claude/skills/<name>/SKILL.md` and `.agents/skills/<name>/` for `file-pr`, `babysit-pr`, `modernize-pr`, and `pr-comment` | an authenticated `gh`; `python3` 3.9+ on macOS or Linux for `babysit-pr` | Kit's choice; pr-wait keeps its state in `~/.local/state/pr-wait/`, outside the repo |
| Kit receipt | Serel Kit | `.serel-kit.json` | nothing | same as the Kit files |
| Bank, rules, anchor, agent instructions | Serel Memory | `memory-bank/`, `.rules`, `.serel-memory.json`, `AGENTS.md` | nothing from Kit | Memory's setup decides; Kit never changes it |
| Existing Claude instructions | your project | `CLAUDE.md` | nothing | yours; both tools preserve it, and Memory never creates it |

## Update an existing installation

Paste this into Claude Code or Codex opened at your project root.

```text
Upgrade this project's installed Serel Kit packs. This project is the target; a fresh clone only supplies the installer and instructions.

1. Inspect first, changing nothing: Git status, .serel-kit.json (installed packs, version, local mode), and whether Serel Memory is present. If there is no receipt, stop; do not install Kit.
2. Clone https://github.com/madeordinary/serel-kit into a temporary directory outside this project. Follow its README section "Upgrade installed packs", not an older checkout.
3. Preview without --apply: use the fresh clone's install.sh with this project's root as the target, --packs followed by a comma-separated list of installed packs to upgrade, and --upgrade. Quote paths that contain spaces. Select only packs recorded in the receipt. Use only documented flags; local mode carries over from the receipt. Adding packs is a separate setup.
4. Show me the installed version from the receipt, the proposed Kit commit and whether it is released, its benefits, diffs, and conflicts. Compare new or changed pack workflows with my own commands and skills by what they do, not by name; report any overlap with my rules to keep, and hold that whole pack until I choose. Never delete, disable, or merge my workflows unless I approve that change. Wait for approval; only rerun a conflict-free preview with --apply.
5. Handle conflicts only through the README's steps, with my approval. Never guess a baseline or edit the receipt to get past a conflict. If an old receipt needs its exact v<version> tag, fetch it into the temporary clone only.
6. Preserve my pack customizations, uncommitted work, and sharing choices. Do not commit or push. Leave Serel Memory's installation and version unchanged; if present, offer its update separately.
```

The installer has no force option or automatic merge: any conflict stops the
whole upgrade until you resolve it.

## Requirements

- `bash` (3.2 or newer), `git`, `jq`, and `sha256sum` or `shasum` to run
  the installer. macOS includes `shasum`.
- A git repository to install into. The target is its **repository root**,
  not a subdirectory.
- Claude Code or Codex to run the workflows.
- Serel Memory in the target repo — for the verify pack only.
- `gh`, the GitHub CLI, authenticated — for the pr pack. `babysit-pr` also
  needs `python3` 3.9 or newer on macOS or Linux, unless it runs inside
  T3 Code.

## Install

Clone the Kit somewhere, then install a pack into your project:

```bash
git clone https://github.com/madeordinary/serel-kit.git
bash serel-kit/install.sh /path/to/your-repo --packs writing
```

Several packs at once:

```bash
bash serel-kit/install.sh /path/to/your-repo --packs writing,verify
```

Then open your project in Claude Code or Codex. `/polish` and `$polish` are
there. Nothing else in your repo changed.

What the installer does:

- Copies each workflow's whole `.agents/skills/<name>/` directory, resources
  included, and its Claude Code copy, `.claude/skills/<name>/SKILL.md`.
  Kit 0.4.0 ships no `.claude/commands/` files.
- Checks the complete payload against your repo **before** writing anything.
  A file that is already identical is skipped. A file that exists and differs
  is a conflict: the run stops, lists the conflicts, and writes nothing. It
  never overwrites during a normal install.
- Writes `.serel-kit.json` last — a receipt saying which version installed
  which packs, with per-pack versions and upstream file hashes, and whether
  the installation is local. It is a
  receipt, not a config file, and it has no authority over
  Serel Memory's `.serel-memory.json` anchor. Unknown keys in an existing
  receipt are preserved.
- Running it again with the same packs changes nothing and exits 0. Adding a
  pack adds only that pack.

## Keep Kit files out of Git

`--local` is new in 0.3.0. The v0.2.0 installer does not have it.

By default the installed files are ordinary untracked files. Commit them and
everyone who clones the project gets the same workflows. To use Kit without
committing it, preview a local install, then apply it:

```bash
bash serel-kit/install.sh /path/to/your-repo --packs writing --local
bash serel-kit/install.sh /path/to/your-repo --packs writing --local --apply
```

The preview lists each file to add, then the exact-path line for each file and
for the receipt that will go into Git's exclude file. It writes nothing.
`--apply` adds the missing lines first. It then asks `git check-ignore` to
confirm Git ignores every Kit path, copies the files, and writes the receipt
last. If an ordinary write fails, the lines this run added are removed along
with the files.

- Only exact paths are excluded, such as `/.claude/skills/polish/SKILL.md`.
  The installer never ignores all of `.claude/` or `.agents/`, so your own
  files there stay visible to Git. It only appends. It never edits or
  reorders existing lines, including yours and Serel Memory's, and never adds
  a line that is already there. Kit's lines always sit under a
  `# Serel Kit local install` comment, never under another tool's comment.
- The exclude file is the one Git resolves for the repository, usually
  `.git/info/exclude`. In a linked worktree it lives in the main repository's
  `.git`, so the lines apply to every worktree of that repository.
- A Kit path that Git already tracks is refused, even when its bytes match,
  because an ignore rule cannot hide a tracked file. A `.gitignore` or exclude
  rule that re-includes a Kit path, such as `!/.claude/skills/polish/SKILL.md`, is
  refused too. The installer never removes files from Git and never edits
  `.gitignore`.
- The receipt records `"local": true`. Later runs, added packs, and upgrades
  stay local without `--local`. They also preview until you add `--apply`.
  Use this installer or a newer one for them: v0.2.0 does not read the key
  and would add files without exclusions.
- The installer never converts an installation. `--local` is refused when the
  receipt records a shared installation. To share a local installation, delete
  the Kit's lines from the exclude file and the `local` key from
  `.serel-kit.json`, then commit the files. To make a shared installation
  local, decide what happens to the committed copies yourself: removing them
  from Git deletes them for everyone else on their next pull. Once Git tracks
  no Kit path or receipt, delete `.serel-kit.json` and install with `--local`.

Local means not committed. It is not access control: anyone who can read this
clone can read the files. Excluded files do not travel with a clone, push,
or fork, so other machines and collaborators do not get them. `git clean -x`,
for example `git clean -fdx`, deletes them. Local-only does not mean backed
up either, so keep your own copy of any `RULES.md` edits you care about.

## Upgrade installed packs

From a newer Kit checkout, preview selected installed packs:

```bash
bash serel-kit/install.sh /path/to/your-repo --packs writing --upgrade
```

The preview lists every file and shows diffs for additions, updates and
conflicts. It writes nothing to your project. Apply a conflict-free plan with:

```bash
bash serel-kit/install.sh /path/to/your-repo --packs writing --upgrade --apply
```

The installer compares the recorded upstream bytes, your current file, and
the incoming file:

| Situation | Result |
|-----------|--------|
| Your file already matches incoming | Skip it |
| Only upstream changed | Update it |
| Only you changed it, including `RULES.md` | Keep your version |
| Both changed it differently | Stop the entire selected upgrade |
| A new upstream file has no local counterpart | Add it |
| A managed file was deleted locally | Stop; do not recreate it |
| Upstream retired a file | Leave it as-is and stop managing it, except the six retired Claude commands below |

A different local file at a new upstream path is also a conflict. Nothing is
deleted, except an unmodified retired Claude command in the 0.4.0 move below.
A local installation stays local: new files get their exclusion
lines before they are written. Unselected packs and unknown receipt metadata are preserved. Stored
hashes always describe upstream bytes, so keeping your edited `RULES.md` does
not turn your edits into the next upstream baseline.

There is no force option or automatic text merge. For a conflict, save your
local file outside the managed paths and compare it with the corresponding
file under `serel-kit/packs/<pack>/`. Put the incoming version at the conflict
path, rerun the upgrade, then reapply the customizations you want to keep.
A manually merged version that differs from both inputs remains a conflict
until the baseline has advanced this way.

Old v0.1 receipts record only a version. Their first upgrade needs that exact
`v<version>` tag in the local Kit checkout to reconstruct the original payload.
If it is missing, the installer stops and asks you to obtain it; it never
fetches or guesses a baseline. Modern receipts carry hashes and need no tag.
Receipts from 0.1.0, 0.2.0 and 0.3.0 all upgrade to 0.4.0.

### Upgrading to 0.4.0: commands become skills

Upgrade Serel Memory to 0.8.0 first. Kit 0.4.0 is tested against Memory 0.8.0,
which moved its own Claude Code workflows from `.claude/commands/` to
`.claude/skills/`. Then upgrade Kit.

Up to 0.3.0, each Kit workflow had a Claude Code command
(`.claude/commands/<name>.md`) beside its Codex skill. In 0.4.0 each workflow
is one skill, and Claude Code reads a copy of it at
`.claude/skills/<name>/SKILL.md`. An upgrade installs that copy. Leaving the
old command beside it would give Claude Code two files for one workflow, so
`--upgrade` retires the command.

Only these six files can ever be removed, and each only when its own pack is
being upgraded: `.claude/commands/polish.md` (writing),
`.claude/commands/verify-map.md` (verify), and `.claude/commands/file-pr.md`,
`.claude/commands/babysit-pr.md`, `.claude/commands/modernize-pr.md` and
`.claude/commands/pr-comment.md` (pr). The preview, run without `--apply`,
tells you what happens to each:

| Preview line | Meaning |
|--------------|---------|
| `REMOVE` | The command is exactly as Kit installed it and its skill replaces it. `--apply` removes it. |
| `ABSENT` | The command is already gone. Nothing to do. |
| `RETIRED (left as-is)` | Kept, and Kit stops managing it. It is not one of the six, or another installed pack records it, or its bytes match no Kit release. |
| `MODIFIED` | The command changed since Kit installed it. The new skill would hide your edits from Claude Code, so the whole run stops and nothing is written, with or without `--apply`. |

Removals are part of the same apply as the other writes, so they are backed up
and rolled back with the rest if something fails. In a local installation, a
retired command that Git tracks is refused like any other tracked Kit path,
and the command's exclude line stays, because a linked worktree may still
have the file. Kit leaves an emptied `.claude/commands/` folder in place on
purpose, since it is where your own commands live.

A plain install (without `--upgrade`) over an older install of a pack is
refused when the pack's old command is still there. The message points you to
`--upgrade`, and nothing is written.

### If an upgrade stops on a customized command

The stop lists each `MODIFIED` command and prints these steps with your
paths. Step 2 reads the original bytes from a release tag, so the Kit
checkout must be a git clone with its tags. Legacy 0.1 upgrades already need
that. `git -C <kit> tag` shows what you have.

1. Copy your customized files outside `.claude/` and `.agents/`. That is the
   command, and the Codex skill too if you changed it.
2. Put back the bytes Kit installed:
   - Restore the command from the tag that shipped it:
     `git -C <kit> show v<version>:packs/<pack>/.claude/commands/<name>.md > .claude/commands/<name>.md`.
     The installer prints this line with the right tag filled in.
   - If you changed `.agents/skills/<name>/SKILL.md`, restore it to the bytes
     Kit installed, or to the new ones:
     `cp <kit>/packs/<pack>/.agents/skills/<name>/SKILL.md .agents/skills/<name>/SKILL.md`.
     Leave the file in place. A missing Kit file also stops the upgrade.
3. Run the upgrade again: `--upgrade`, then `--upgrade --apply`. It removes
   the command, installs both new copies, and records their hashes.
4. Reapply your customizations to both
   `.agents/skills/<name>/SKILL.md` and `.claude/skills/<name>/SKILL.md`.
   Later upgrades keep them as KEEP LOCAL.

Do not port your edits into the new skill and retry: the installer would see
a changed file with no baseline at that path and report another conflict.
There is no force option.

Use one writer at a time and keep project changes in version control. Before
applying, the installer stages incoming bytes, checks destinations and the
receipt again, and rejects symlinks, hard links and invalid paths. It writes
the receipt last and rolls back ordinary copy failures, retaining recovery
backups if an apply fails. This is not a crash-atomic transaction; interruption
by a crash, concurrent writers, or an unrecoverable disk failure can still
require manual recovery. Repeating a successful upgrade changes nothing.

## The packs

| Pack | Claude Code | Codex | Needs Serel Memory |
|------|-------------|-------|--------------------|
| [writing](packs/writing/README.md) | `/polish` | `$polish` | no |
| [verify](packs/verify/README.md) | `/verify-map` | `$verify-map` | yes |
| [pr](packs/pr/README.md) | `/file-pr`, `/babysit-pr`, `/modernize-pr`, `/pr-comment` | `$file-pr`, `$babysit-pr`, `$modernize-pr`, `$pr-comment` | no |

### writing

`/polish` rewrites the text you name — a file, a section, or something you
paste — to a set of house rules in `RULES.md`, and shows you a diff. It writes
nothing. It preserves meaning, qualifications, open questions, decision status,
evidence pointers, and everything inside a code fence. `RULES.md` becomes yours
at install; edit it.

### verify

`/verify-map` keeps one file per feature in the memory bank:

- a **Recipe** — launch, drive, observe, clean up — for seeing that feature
  work with your own eyes, and
- **Records** of what someone actually saw, with the revision, environment, and
  a link to the evidence.

No record means verification is undocumented. That is useful information, not
a failure. A map never replaces running the tests.

### pr

Four workflows for pull requests. `/file-pr` opens a real PR that leads with
the problem. `/babysit-pr` watches it through CI and review with one watcher,
fixes real findings, and reports when it is ready; it merges only when you
ask. `/modernize-pr` decides whether an old PR should still land and rebases
it with a lease when it should. `/pr-comment` holds the rules for every
comment an agent posts on your behalf. `babysit-pr` bundles tstack's
`pr-wait` script, copied unchanged.

## Customize

Keep your preferences, such as attribution lines, PR title style, or which
review bots you run, in `CLAUDE.md` for Claude Code or `AGENTS.md` for Codex,
which each agent reads every session, rather than in pack files. With Serel
Memory installed, its `.rules` works too, because Memory's session start
reads it. An edited pack file is kept on upgrade only until upstream
changes the same file; then the upgrade stops on a conflict you resolve by
hand. The writing pack's `RULES.md` is still yours to edit; the same upgrade
rule applies to it.

## What the tests prove, and what they don't

Run them from the Kit:

```bash
bash tests/ci.sh           # ShellCheck, every check/smoke suite, Markdown lint
bash tests/ci.sh checks    # ShellCheck and Bash suites only
bash tests/ci.sh docs      # Markdown lint only
```

GitHub runs the same commands. Use a full Git checkout with release tags,
Bash, `jq`, and the Node version in `.github/ci/node-version` with its bundled
npm. The runner uses ShellCheck **0.11.0**, downloading and verifying an
official Linux/macOS Intel/ARM binary in a temporary directory if the
installed version differs. That bootstrap needs `curl`, `tar`, and `shasum`.
Markdown lint installs **0.23.3** and the dependencies in
`.github/ci/package-lock.json` into a temporary directory. Downloads require
network access and fail if unavailable; nothing is installed globally or left
in the repository. These are maintainer tools, not pack dependencies.

Update `.github/ci/shellcheck.sh` and its official archive checksums together,
the Markdown manifest/lockfile from `.github/ci/`, and
`.github/ci/node-version` for Node. Action revisions are pinned in the workflow.
Rerun the preflight and GitHub checks when changing pins.

**The automated tests cover installation, upgrades, local installs, and the one-source layout.**
`check-packs.sh` asserts every workflow has one source with its Codex
manifest, that its `.claude/skills/` copy is byte-identical and alone in its
folder, that no pack ships `.claude/commands/`, that every resource a
workflow points at travels with it, that no workflow calls its own CLI, and
that the installer's list of retired commands matches what the release tags
shipped. `smoke-install.sh` installs the
packs into throwaway git repositories and checks that the refusal path writes
nothing however the pack name is spelled, that a malformed receipt, a
symlinked destination path, or a file standing where a directory belongs each
stop the run with zero writes, that re-running converges, that a divergent
local file stops the whole run before anything is copied, that the memory bank
and anchor come out byte-identical, and that Serel Memory's own checks still
pass afterwards.

`smoke-local.sh` asks Git itself whether every Kit path is ignored after a
local install, including in a linked worktree. It checks that the exclude file
gains exactly the Kit's lines and that a preview or refusal changes nothing,
`.git` included. It also checks that unrelated staged, unstaged, and untracked
work survives. It refuses tracked Kit paths, re-including ignore rules,
shared-to-local switches, malformed receipts, linked exclude files, and
case-variant Kit paths on a case-insensitive filesystem. It
covers inheritance of local mode by added packs and upgrades, rollback of
files, receipt, and exclusions after injected failures, and shared Kit beside
a local memory bank. It isolates itself from your global Git configuration
and needs no Memory checkout.

`smoke-pr-pack.sh` installs the pr pack into a plain repository and checks
that every file, pr-wait and its license included, arrives byte-identical,
and that pr-wait still matches its pinned upstream hash.
It runs pr-wait with `python3 -I`: `--help` exits 0, and a missing or
malformed PR argument exits 2 before pr-wait reaches GitHub. It then installs
the pack beside Serel Memory and checks that nothing already there changed
and that Memory's own checks still pass. It needs `python3`, and like
`smoke-install.sh` it needs a Memory checkout for that last case. It never
runs pr-wait against a real PR.

Cases 2 to 5 of `smoke-install.sh`'s five need a Serel Memory checkout to
scaffold, and so does `smoke-pr-pack.sh`'s last case. Each test looks for
`$SEREL_MEMORY_REPO` first, then a sibling `../memory` or `../serel-memory`.
Without one it runs the no-Memory cases, prints `PARTIAL` and **exits
non-zero**, so a partial run can never read as a pass. Set
`SEREL_KIT_ALLOW_PARTIAL=1` to accept a partial run locally. CI uses the
preflight, which refuses partial results and requires every case.

The preflight builds its Memory fixture at the exact commit in
`.github/ci/memory-ref` (currently the Serel Memory 0.8.0 release). It first looks for that commit in `$SEREL_MEMORY_REPO`
or a sibling `../memory` or `../serel-memory`; otherwise it fetches from GitHub.
It checks out only the pinned commit in a temporary directory and never
changes the source checkout. `SEREL_KIT_ALLOW_PARTIAL` cannot weaken this run.
Individual smoke tests remain available for exploring other Memory versions.

When adopting a new Memory release, the Kit maintainer must update
`.github/ci/memory-ref` to its full commit SHA in a reviewed change and run
the preflight and GitHub checks. This pin records tested compatibility;
a green run does not claim compatibility with every newer Memory commit.
The Memory integration fixture reads the committed, pinned tree; the Kit
installer and pack checks exercise the working tree.

**They do not prove that a workflow behaves the same way in both CLIs.** Both run the same
skill text, but no automated test here runs Claude Code or Codex. Whether
`/polish` and `$polish` produce the same kind of answer is something a person
has to check, once, by running both. Each
pack's README ends with an acceptance exercise for exactly that: the prompt to
type, the shape of the reply to expect, and what should exist on disk
afterwards. Do it after you install, and again when you edit the prompts.

## Credits

Serel Kit is a companion to [Serel Memory](https://github.com/madeordinary/serel-memory)
and follows its `docs/workflow-contract.md`.

Two ideas here came from Cursor's
[pstack](https://github.com/cursor/plugins/tree/main/pstack) plugin (MIT): that
"stop writing like a language model" is a job worth giving an agent its own
rules for, and that a feature-by-feature map of how to verify behavior by hand
belongs in the repo next to the code. Those workflows, rules, and template,
and the installer, are written from scratch — the ideas are credited, no text
is copied.

The pr pack adapts four skills from Theo Browne's
[tstack](https://github.com/t3dotgg/tstack) (MIT): `file-pr`, `babysit-pr`,
`modernize`, and `leaving-pr-comments`. The workflows are rewritten in this
Kit's shape. Its `pr-wait` script is copied unchanged from tstack commit
`7de017b3fc9d50c03cf3ecb98fb71e0ca65a78bd`, and tstack's MIT license travels
with it in `.agents/skills/babysit-pr/LICENSE-tstack`.

## License

MIT. See [LICENSE](LICENSE).
