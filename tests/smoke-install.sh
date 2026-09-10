#!/usr/bin/env bash
# End-to-end test of install.sh against real repositories in a temp directory.
#
# Cases:
#   1. A git repo with no Serel Memory: the writing pack installs; the verify
#      pack is refused with install instructions and writes nothing; a mixed
#      request is refused whole, never half.
#   2. A git repo with Serel Memory scaffolded from the sibling repo's HEAD
#      (git archive + a fresh anchor): both packs install, Serel Memory's own
#      check-readlist and check-parity still pass afterwards, and the bank,
#      .rules, AGENTS.md, CLAUDE.md and the anchor are byte-identical.
#   3. Re-running with the same packs changes nothing and exits 0.
#   4. A locally modified pack file is a CONFLICT: exit 1, and a file that
#      would otherwise have been copied is still not there.
#
# The Memory cases need the sibling repo. Set SEREL_MEMORY_REPO to point at it,
# or keep it checked out next to this one as ../memory. Without it those cases
# are skipped and the run says so.
#
# What this proves: installation. What it does not prove: that the two adapters
# of a pack behave the same way in Claude Code and Codex. See the acceptance
# exercise in each pack's README for that.
set -euo pipefail
cd "$(dirname "$0")/.."
KIT="$PWD"

fail=0
bad() { printf 'FAIL: %s\n' "$*"; fail=1; }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required to run this test"; exit 1; }

kit_version="$(sed -n 's/^KIT_VERSION="\(.*\)"$/\1/p' "$KIT/install.sh")"
[ -n "$kit_version" ] || { echo "FAIL: could not read KIT_VERSION from install.sh"; exit 1; }

tmproot="$(mktemp -d)"
trap 'rm -rf "$tmproot"' EXIT

# Every non-.git file, with a checksum. Comparing two snapshots is how "wrote
# nothing" and "changed nothing" are asserted.
snapshot() { ( cd "$1" && find . -type f -not -path './.git/*' -exec cksum {} + | sort ); }

# The files Serel Kit promises never to touch.
guarded() {
  ( cd "$1" && find memory-bank .rules .serel-memory.json AGENTS.md CLAUDE.md \
      -type f -exec cksum {} + | sort )
}

expect_files() {
  local root="$1" p
  shift
  for p in "$@"; do
    [ -f "$root/$p" ] || bad "expected file missing after install: $p"
  done
}

receipt_packs() { jq -r '.packs | join(",")' "$1/.serel-kit.json"; }

WRITING_FILES=".claude/commands/polish.md
.agents/skills/polish/SKILL.md
.agents/skills/polish/agents/openai.yaml
.agents/skills/polish/RULES.md"

VERIFY_FILES=".claude/commands/verify-map.md
.agents/skills/verify-map/SKILL.md
.agents/skills/verify-map/agents/openai.yaml
.agents/skills/verify-map/TEMPLATE.md"

# --- case 1: a repo without Serel Memory -------------------------------------

echo "case 1: repo without Serel Memory"
plain="$tmproot/plain"
mkdir -p "$plain"
git -C "$plain" init -q
printf '# demo project\n' >"$plain/README.md"

before="$(snapshot "$plain")"

if bash "$KIT/install.sh" "$plain" --packs verify >"$tmproot/refuse.log" 2>&1; then
  bad "the verify pack installed into a repo with no Serel Memory (expected exit 1)"
fi
grep -q 'github.com/madeordinary/serel-memory#install' "$tmproot/refuse.log" ||
  bad "the refusal does not point at Serel Memory's install instructions"
[ "$(snapshot "$plain")" = "$before" ] || bad "the refused run wrote to the target"

if bash "$KIT/install.sh" "$plain" --packs writing,verify >"$tmproot/refuse-mixed.log" 2>&1; then
  bad "writing,verify installed without Serel Memory (expected the whole run to be refused)"
fi
[ "$(snapshot "$plain")" = "$before" ] || bad "the refused mixed run wrote part of the payload"

bash "$KIT/install.sh" "$plain" --packs writing >"$tmproot/writing.log" 2>&1 ||
  bad "the writing pack failed to install without Serel Memory"
# shellcheck disable=SC2086
expect_files "$plain" $WRITING_FILES
[ -f "$plain/.serel-kit.json" ] || bad "no receipt was written"
[ "$(receipt_packs "$plain")" = "writing" ] || bad "receipt packs should be 'writing', got '$(receipt_packs "$plain")'"
[ "$(jq -r '.kit' "$plain/.serel-kit.json")" = "$kit_version" ] || bad "receipt kit version is not $kit_version"

# An existing receipt is merged, not replaced: unknown keys survive.
jq '. + {"installedBy": "smoke-test"}' "$plain/.serel-kit.json" >"$tmproot/r.json"
mv "$tmproot/r.json" "$plain/.serel-kit.json"
bash "$KIT/install.sh" "$plain" --packs writing >"$tmproot/merge.log" 2>&1 ||
  bad "re-install over an existing receipt failed"
[ "$(jq -r '.installedBy' "$plain/.serel-kit.json")" = "smoke-test" ] ||
  bad "the receipt merge dropped an unknown key"

# --- case 2: a repo with Serel Memory ----------------------------------------

memory=""
if [ -n "${SEREL_MEMORY_REPO:-}" ]; then
  memory="$SEREL_MEMORY_REPO"
  if [ ! -d "$memory/.git" ] || [ ! -f "$memory/tests/check-parity.sh" ]; then
    echo "FAIL: SEREL_MEMORY_REPO=$memory is not a Serel Memory checkout"
    exit 1
  fi
else
  for candidate in "$KIT/../memory" "$KIT/../serel-memory"; do
    if [ -d "$candidate/.git" ] && [ -f "$candidate/tests/check-parity.sh" ]; then
      memory="$candidate"
      break
    fi
  done
fi

if [ -z "$memory" ]; then
  echo "SKIP: cases 2-4 need the sibling Serel Memory repo (set SEREL_MEMORY_REPO)"
else
  echo "case 2: repo with Serel Memory from $(cd "$memory" && pwd) HEAD"
  proj="$tmproot/with-memory"
  mkdir -p "$proj"
  git -C "$proj" init -q
  git -C "$memory" archive --format=tar HEAD | tar -x -C "$proj"
  # The anchor is export-ignored upstream; a real install writes its own.
  printf '{ "upstream": "madeordinary/serel-memory", "ref": "smoke", "linked": false }\n' \
    >"$proj/.serel-memory.json"

  guard_before="$(guarded "$proj")"

  bash "$KIT/install.sh" "$proj" --packs writing >"$tmproot/m-writing.log" 2>&1 ||
    bad "the writing pack failed to install into a Serel Memory repo"
  # shellcheck disable=SC2086
  expect_files "$proj" $WRITING_FILES
  polish_before="$(cd "$proj" && find .claude/commands/polish.md .agents/skills/polish \
    -type f -exec cksum {} + | sort)"

  # Adding a pack adds only that pack.
  bash "$KIT/install.sh" "$proj" --packs verify >"$tmproot/m-verify.log" 2>&1 ||
    bad "the verify pack failed to install into a Serel Memory repo"
  # shellcheck disable=SC2086
  expect_files "$proj" $VERIFY_FILES
  polish_after="$(cd "$proj" && find .claude/commands/polish.md .agents/skills/polish \
    -type f -exec cksum {} + | sort)"
  [ "$polish_after" = "$polish_before" ] || bad "installing verify rewrote the writing pack's files"
  [ "$(receipt_packs "$proj")" = "verify,writing" ] ||
    bad "receipt should list both packs, got '$(receipt_packs "$proj")'"

  # Serel Memory's own framework checks must still pass with the packs in place.
  bash "$proj/tests/check-readlist.sh" >"$tmproot/readlist.log" 2>&1 ||
    bad "Serel Memory's check-readlist.sh fails after installing the packs"
  bash "$proj/tests/check-parity.sh" >"$tmproot/parity.log" 2>&1 ||
    bad "Serel Memory's check-parity.sh fails after installing the packs"

  [ "$(guarded "$proj")" = "$guard_before" ] ||
    bad "the install changed the memory bank, .rules, AGENTS.md, CLAUDE.md, or the anchor"

  echo "case 3: re-running the same packs converges"
  after_install="$(snapshot "$proj")"
  bash "$KIT/install.sh" "$proj" --packs writing,verify >"$tmproot/rerun.log" 2>&1 ||
    bad "re-running with the same packs exited non-zero"
  [ "$(snapshot "$proj")" = "$after_install" ] || bad "re-running changed files in the target"
  grep -q 'nothing to do' "$tmproot/rerun.log" || bad "the converged re-run did not say there was nothing to do"

  echo "case 4: a divergent local file is a conflict, and nothing is written"
  printf '\nlocal edit that upstream does not have\n' >>"$proj/.claude/commands/polish.md"
  # Delete a file the run would otherwise copy, to prove the run is all-or-nothing.
  rm "$proj/.agents/skills/verify-map/TEMPLATE.md"
  pre_conflict="$(snapshot "$proj")"
  if bash "$KIT/install.sh" "$proj" --packs writing,verify >"$tmproot/conflict.log" 2>&1; then
    bad "a divergent local file did not stop the install (expected exit 1)"
  fi
  grep -q 'CONFLICT' "$tmproot/conflict.log" || bad "the conflicting run did not report CONFLICT"
  grep -q '.claude/commands/polish.md' "$tmproot/conflict.log" ||
    bad "the conflicting run did not name the file that conflicts"
  [ ! -e "$proj/.agents/skills/verify-map/TEMPLATE.md" ] ||
    bad "the conflicting run copied part of the payload before stopping"
  [ "$(snapshot "$proj")" = "$pre_conflict" ] || bad "the conflicting run wrote to the target"
fi

if [ "$fail" -eq 0 ]; then
  echo "install smoke OK: packs install, refuse, converge, and never overwrite"
fi
exit "$fail"
