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

- `bash`, `git`, and `jq` to run the installer.
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
  never overwrites, and it never leaves a half-installed pack behind.
- Writes `.serel-kit.json` last — a receipt saying which version installed
  which packs. It is a receipt, not a config file, and it has no authority over
  Serel Memory's `.serel-memory.json` anchor. Unknown keys in an existing
  receipt are preserved.
- Running it again with the same packs changes nothing and exits 0. Adding a
  pack adds only that pack.

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
shellcheck install.sh tests/*.sh
bash tests/check-packs.sh
bash tests/smoke-install.sh
npx --yes markdownlint-cli2 "**/*.md"
```

**The automated tests prove two things: installation, and adapter pairing.**
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
checks Memory out and requires all four cases.

**They do not prove that a workflow behaves the same way in both CLIs.** No automated test
here runs Claude Code or Codex. Whether `/polish` and `$polish` produce the same
kind of answer is something a person has to check, once, by running both. Each
pack's README ends with an acceptance exercise for exactly that: the prompt to
type, the shape of the reply to expect, and what should exist on disk
afterwards. Do it after you install, and again when you edit the prompts.

## Upgrading

Manual in v0.1. To take a newer version of a pack, pull the Kit, delete the
pack's files from your repo, and install again. The installer will not
overwrite them for you — that is the same rule that protects your local edits.

Your edits are the point. A workflow you changed is worth more than the one
that shipped.

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
