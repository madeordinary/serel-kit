# Serel Kit

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg) ![Works with Claude Code + Codex](https://img.shields.io/badge/works%20with-Claude%20Code%20%2B%20Codex-5436DA) ![Version 0.1.0](https://img.shields.io/badge/version-0.1.0-blue)

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
`memory-bank/`, `.rules`, `.serel-memory.json`, `AGENTS.md`, or `CLAUDE.md`.

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
  which packs, with per-pack versions and upstream file hashes. It is a
  receipt, not a config file, and it has no authority over
  Serel Memory's `.serel-memory.json` anchor. Unknown keys in an existing
  receipt are preserved.
- Running it again with the same packs changes nothing and exits 0. Adding a
  pack adds only that pack.

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
deleted. Unselected packs and unknown receipt metadata are preserved. Stored
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

**The automated tests cover installation, upgrades, and adapter pairing.**
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

Three of those four smoke cases need a Serel Memory checkout to scaffold. The
test looks for `$SEREL_MEMORY_REPO` first, then a sibling `../memory` or
`../serel-memory`. Without one it runs the no-Memory cases, prints
`smoke-install PARTIAL` and **exits non-zero**, so a partial run can never read
as a pass. Set `SEREL_KIT_ALLOW_PARTIAL=1` to accept a partial run locally. CI
uses the preflight, which refuses partial results and requires all four cases.

The preflight builds its Memory fixture at the exact commit in
`.github/ci/memory-ref` (currently the AGENTS-only template and memory-update
reconciliation change). It first looks for that commit in `$SEREL_MEMORY_REPO`
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
