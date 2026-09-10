# Changelog

All notable changes to Serel Kit are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims
to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) once it
reaches 1.0.

## [Unreleased]

## [0.1.0] — 2026-09-09

First release. Two workflow packs and an installer that puts them into a git
repository without touching anything else.

Serel Memory owns bank structure, lifecycle, and compatibility. Serel Kit
supplies optional workflows that follow those contracts. The Kit never
installs, upgrades, or reconfigures Serel Memory.

### Added

- **`install.sh`** — the pack installer. `install.sh <target> --packs <a,b>`.
  Requires the target to be the root of a git repository. Detects Serel Memory
  by `.serel-memory.json` and refuses a pack that needs it, with a link to
  Memory's install instructions and zero writes. Preflights the complete
  payload before writing: identical files are skipped, an existing file that
  differs is a CONFLICT that stops the whole run. Never overwrites; never
  writes outside `.claude/`, `.agents/`, and the receipt. Re-running with the
  same packs converges. Bash, git, and jq only.
- **`.serel-kit.json`** — an installation receipt written last, recording the
  Kit version and the packs installed. Merged with `jq` when it already exists,
  so unknown keys survive. It is a receipt, never an authority over Serel
  Memory's `.serel-memory.json` anchor.
- **writing pack** — `/polish` (Claude Code) and `$polish` (Codex). Rewrites
  named text to 16 house rules in `RULES.md` and shows a diff. Writes nothing;
  the workflow ends at the proposal. Preserves meaning, qualifications, open
  questions, decision status and supersession links, evidence pointers, literal
  commands and paths, fenced code, and the retention-significant structure of
  memory bank files. Installs without Serel Memory.
- **verify pack** — `/verify-map` and `$verify-map`. Creates or refreshes
  `<effective bank>/verification/<feature>.md` from `TEMPLATE.md`: a RECIPE
  (launch, drive, observe, clean up) and RECORDS (revision, paths, environment,
  observation, artifact). Resolves one scope and one effective bank per
  invocation per Serel Memory's `docs/workflow-contract.md`, stops on an
  uninitialized bank, and shows a diff before writing its single file.
  Requires Serel Memory.
- **`tests/check-packs.sh`** — every pack ships both adapters plus the Codex
  manifest, in both directions; every resource an adapter references exists
  inside the pack; no adapter shells out to its own CLI.
- **`tests/smoke-install.sh`** — installs into throwaway git repositories: one
  without Serel Memory (writing installs, verify is refused, a mixed request is
  refused whole) and one with Serel Memory scaffolded from the upstream repo's
  HEAD. Asserts that adding a pack adds only that pack, that Serel Memory's own
  `check-readlist.sh` and `check-parity.sh` still pass with the packs
  installed, that the bank and anchor are byte-identical afterwards, that a
  re-run changes nothing, and that a divergent local file stops the run without
  copying any part of the payload.
- **CI** — shellcheck, markdownlint, and both tests, guarded to the
  `madeordinary/serel-kit` repository so forks and copies do not inherit them.
- Acceptance exercises in both pack READMEs: the prompt to type in each CLI,
  the reply to expect, and what should be on disk afterwards.

### Known limits

- The automated tests prove installation and adapter pairing. They do not prove
  that a pack behaves the same way in Claude Code and in Codex — nothing here
  runs either CLI. The manual acceptance exercises cover that.
- Upgrades are manual. To take a newer pack, delete the pack's files and
  install again; the installer will not overwrite them.

[Unreleased]: https://github.com/madeordinary/serel-kit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/madeordinary/serel-kit/releases/tag/v0.1.0
