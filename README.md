# Serel Kit

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg) ![Works with Claude Code + Codex](https://img.shields.io/badge/works%20with-Claude%20Code%20%2B%20Codex-5436DA) ![Version 0.2.0](https://img.shields.io/badge/version-0.2.0-blue)

Optional workflow packs for AI coding agents, built to fit
[Serel Memory](https://github.com/madeordinary/serel-memory).

Created and maintained by [Gus Feliciano](https://github.com/gusfeliciano) through
[Made Ordinary](https://github.com/madeordinary).

## What this is

A workflow is a markdown file that tells a coding agent how to do one job:
what to read first, what it is allowed to change, what to hand back, and when
to stop and ask you. Claude Code calls these slash commands
(`.claude/commands/polish.md` becomes `/polish`). Codex calls them skills
(`.agents/skills/polish/SKILL.md` becomes `$polish`). Same idea, two file
layouts, and both are plain text you can read and edit.

Serel Kit is a small collection of those, grouped into **packs**, plus an
installer that copies a pack into your repository. Every pack ships both
adapters, so the workflow exists in Claude Code and in Codex.

Serel Memory is the engine: it gives a project a memory bank the agent reads at
the start of every session. Serel Kit is optional workflows that follow Memory's
rules. You can use one pack here without the other.

## Who it's for

- **Product managers.** You do not need to write code to use this. The writing
  pack rewrites text — a status update, a spec section, release notes — to
  plain, concrete language and shows you what it changed. The verify pack keeps
  a written record of how to check each feature by hand, and when someone last
  did.
- **Developers new to coding agents.** Read the two packs' markdown files.
  They are short. They are how you learn what a workflow file is made of.
- **Developers already using Serel Memory.** These are the workflows that did
  not belong in the core, held to the same contracts and the same parity rule.

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
3. Recommend the fewest supported packs that cover those capabilities. writing needs nothing else. verify needs Serel Memory to install and an initialized memory bank when it runs.
4. If I want Serel Memory, or a chosen pack needs it, and it is missing, follow https://github.com/madeordinary/serel-memory/blob/main/docs/serel-setup.md. Do not install Memory silently or run its seeding interview from here.
5. Carry every answer I already gave into whichever setup runs next, so no question is asked twice.
6. Before writing anything, show me the exact install command, every path it writes, and what Git will share or keep local. For a local install, show me the installer's preview. Wait for my approval.
```

Answers carry forward: if the prompt hands off to Serel Memory's setup, that
setup receives what you already said instead of asking again. The Git
visibility answer is applied to Kit and Memory separately. Kit's `--local`
covers only Kit's files, and Memory's setup decides for Memory's files.
Mixing them is fine. You can share Kit skills through Git while keeping
the memory bank local, or the reverse.

| Piece | Owner | Paths | Needs | Shared or local |
|-------|-------|-------|-------|-----------------|
| writing pack: `/polish`, `$polish` | Serel Kit | `.claude/commands/polish.md`, `.agents/skills/polish/` | nothing | Kit's choice: shared by default, or `--local` |
| verify pack: `/verify-map`, `$verify-map` | Serel Kit | `.claude/commands/verify-map.md`, `.agents/skills/verify-map/` | `.serel-memory.json` to install; an initialized bank to run | Kit's choice; the maps it writes live in the bank |
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
4. Show me the installed version from the receipt, the proposed Kit commit and whether it is released, its benefits, diffs, and conflicts. Wait for approval; only rerun a conflict-free preview with --apply.
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

## Install

Clone the Kit somewhere, then install a pack into your project:

```bash
git clone https://github.com/madeordinary/serel-kit.git
bash serel-kit/install.sh /path/to/your-repo --packs writing
```

Both packs at once:

```bash
bash serel-kit/install.sh /path/to/your-repo --packs writing,verify
```

Then open your project in Claude Code or Codex. `/polish` and `$polish` are
there. Nothing else in your repo changed.

What the installer does:

- Copies each pack's `.claude/commands/` files and its whole
  `.agents/skills/<name>/` directory, resources included.
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

`--local` is available in this checkout and planned for the next release.
The v0.2.0 installer does not have it.

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

- Only exact paths are excluded, such as `/.claude/commands/polish.md`.
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
  rule that re-includes a Kit path, such as `!/.claude/commands/polish.md`, is
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
| Upstream retired a file | Leave it as-is and stop managing it |

A different local file at a new upstream path is also a conflict. Nothing is
deleted. A local installation stays local: new files get their exclusion
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

**The automated tests cover installation, upgrades, local installs, and adapter pairing.**
`check-packs.sh` asserts every pack ships both adapters plus the Codex
manifest, that every resource a workflow points at travels with it, and that
neither adapter shells out to its own CLI. `smoke-install.sh` installs the
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

Three of those four smoke cases need a Serel Memory checkout to scaffold. The
test looks for `$SEREL_MEMORY_REPO` first, then a sibling `../memory` or
`../serel-memory`. Without one it runs the no-Memory cases, prints
`smoke-install PARTIAL` and **exits non-zero**, so a partial run can never read
as a pass. Set `SEREL_KIT_ALLOW_PARTIAL=1` to accept a partial run locally. CI
uses the preflight, which refuses partial results and requires all four cases.

The preflight builds its Memory fixture at the exact commit in
`.github/ci/memory-ref` (currently the Serel Memory 0.6.0 release). It first looks for that commit in `$SEREL_MEMORY_REPO`
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

**They do not prove that a workflow behaves the same way in both CLIs.** No automated test
here runs Claude Code or Codex. Whether `/polish` and `$polish` produce the same
kind of answer is something a person has to check, once, by running both. Each
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
belongs in the repo next to the code. The workflows, rules, template, and
installer here are written from scratch — the ideas are credited, no text is
copied.

## License

MIT. See [LICENSE](LICENSE).
