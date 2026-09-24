# Changelog

All notable changes to Serel Kit are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims
to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) once it
reaches 1.0.

## [Unreleased]

No changes yet.

## [0.2.0] — 2026-09-23

Safe upgrades. 0.1.0 could install packs but not upgrade them; this release
adds a preview-first upgrade that keeps your local edits. Tested against Serel
Memory 0.6.0.

Upgrade from 0.1.0: `git pull` your Kit checkout and keep its `v0.1.0` tag,
because a 0.1.0 receipt takes its baseline from that tag. Preview with
`install.sh <repo> --packs <names> --upgrade`, then apply with
`--upgrade --apply`. Nothing is written until you apply, and a conflict stops
the whole selection. The packs themselves are unchanged since 0.1.0, so this
first upgrade only rewrites the receipt with per-pack baselines.

### Added

- Preview-first pack upgrades: `--upgrade` reports file decisions and diffs;
  `--upgrade --apply` applies a conflict-free selection. Per-pack versions and
  upstream SHA-256 manifests preserve local-only edits, reject conflicting
  edits and local deletions, and leave retired files on disk. Legacy receipts
  use the exact locally available release tag; no fetch or guessed baseline.
- Destination rechecks, staged payloads, and rollback for ordinary write
  failures, with recovery backups retained after failed applies. The receipt
  is written last. Concurrent writers and crash-atomic recovery are not supported.
- Upgrade smoke coverage using a synthetic changed upstream, including local
  customizations, independent pack versions, preview/refusal snapshots, path
  safety, and injected payload/receipt copy failures.

### Changed

- The installer now needs `sha256sum` or `shasum` for every run, not only
  upgrades; macOS includes `shasum`.
- Maintainers run `bash tests/ci.sh`, the same preflight GitHub Actions runs:
  pinned ShellCheck, every pack suite, and locked Markdown lint. Install tests
  use the exact Serel Memory commit in `.github/ci/memory-ref`, now the Serel
  Memory 0.6.0 release.

### Fixed

- Reject symlinked receipts and multiply linked destination files before
  installation or upgrades can write through them.
- Install smoke checks accept projects without `CLAUDE.md` and still protect
  a project's custom copy when one exists.

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
  Memory's install instructions and zero writes. Pack names are canonicalized
  and then matched byte for byte against the real entries of `packs/`, so
  neither `verify/` nor `Verify` on a case-insensitive filesystem can spell
  its way past that gate.
  Preflights the complete payload before writing: identical files are skipped,
  an existing file that differs is a CONFLICT that stops the whole run, and
  every destination *ancestor* is checked too — a symlink anywhere on the path
  (which would send the copy into whatever it points at) or a file standing
  where a directory belongs (which would strand the copy half done) is refused
  with zero writes. Never overwrites; never writes outside `.claude/`,
  `.agents/`, and the receipt. Re-running with the same packs converges, and
  leaves the receipt file itself untouched when its contents are unchanged.
  Bash, git, and jq only.
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
  without Serel Memory (writing installs; verify is refused however its name is
  spelled; a mixed request is refused whole; a malformed receipt, a symlinked
  `.agents/skills`, and a file at `.claude` each stop the run with zero writes)
  and one with Serel Memory scaffolded from the upstream repo's HEAD. Asserts
  that adding a pack adds only that pack, that Serel Memory's own
  `check-readlist.sh` and `check-parity.sh` still pass with the packs
  installed, that the bank and anchor are byte-identical afterwards, that a
  re-run changes nothing (including the receipt's inode), and that a divergent
  local file stops the run without copying a file it had already passed in
  traversal order. Snapshots record directories and symlinks as well as file
  contents, so a stray empty directory cannot slip through a zero-writes
  assertion. Needs a Serel Memory checkout (`SEREL_MEMORY_REPO`, or a sibling
  `../memory`); without one it reports `smoke-install PARTIAL` and exits
  non-zero unless `SEREL_KIT_ALLOW_PARTIAL=1`.
- **CI** — shellcheck, markdownlint, and both tests, guarded to the
  `madeordinary/serel-kit` repository so forks and copies do not inherit them.
  The Serel Memory checkout the smoke test scaffolds from is required, not
  best-effort: a run that skipped those cases would be a green tick over an
  untested installer.
- Acceptance exercises in both pack READMEs: the prompt to type in each CLI,
  the reply to expect, and what should be on disk afterwards.

### Known limits

- The automated tests prove installation and adapter pairing. They do not prove
  that a pack behaves the same way in Claude Code and in Codex — nothing here
  runs either CLI. The manual acceptance exercises cover that.
- Upgrades are manual. To take a newer pack, delete the pack's files and
  install again; the installer will not overwrite them.

[Unreleased]: https://github.com/madeordinary/serel-kit/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/madeordinary/serel-kit/releases/tag/v0.2.0
[0.1.0]: https://github.com/madeordinary/serel-kit/releases/tag/v0.1.0
