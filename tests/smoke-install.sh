#!/usr/bin/env bash
# End-to-end test of install.sh against real repositories in a temp directory.
#
# Cases:
#   1. A git repo with no Serel Memory: the writing pack installs; the verify
#      pack is refused with install instructions and writes nothing, however
#      the pack name is spelled; a mixed request is refused whole, never half;
#      a malformed receipt, a symlinked destination ancestor, and a file
#      standing where a directory belongs each stop the run with zero writes.
#   2. A git repo with Serel Memory scaffolded from the sibling repo's HEAD
#      (git archive + a fresh anchor): both packs install, Serel Memory's own
#      check-readlist and check-parity still pass afterwards, and the bank,
#      .rules, AGENTS.md, CLAUDE.md and the anchor are byte-identical.
#   3. Re-running with the same packs changes nothing and exits 0.
#   4. A locally modified pack file is a CONFLICT: exit 1, and a file earlier in
#      traversal order that would otherwise have been copied is still not there.
#
# Cases 2-4 need the sibling Serel Memory repo. Set SEREL_MEMORY_REPO to point
# at it, or keep it checked out next to this one as ../memory. Without it those
# cases are skipped, the run says PARTIAL and exits non-zero — set
# SEREL_KIT_ALLOW_PARTIAL=1 to accept a partial local run.
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

# Every entry below the root, with its type: files by checksum, directories by
# name, symlinks by target. Comparing two snapshots is how "wrote nothing" and
# "changed nothing" are asserted — and a new empty directory or a new symlink
# has to fail those assertions too, so type is recorded, not just content.
snapshot() {
  (
    cd "$1" || exit 1
    find . -mindepth 1 -not -path './.git' -not -path './.git/*' | sort |
      while IFS= read -r p; do
        if [ -L "$p" ]; then
          printf 'link %s -> %s\n' "$p" "$(readlink "$p")"
        elif [ -d "$p" ]; then
          printf 'dir  %s\n' "$p"
        elif [ -f "$p" ]; then
          printf 'file %s %s\n' "$p" "$(cksum <"$p")"
        else
          printf 'other %s\n' "$p"
        fi
      done
  )
}

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

# BSD stat and GNU stat spell the inode format differently; try both.
inode_of() { stat -f %i "$1" 2>/dev/null || stat -c %i "$1"; }

new_repo() {
  mkdir -p "$1"
  git -C "$1" init -q
}

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
new_repo "$plain"
printf '# demo project\n' >"$plain/README.md"

before="$(snapshot "$plain")"

if bash "$KIT/install.sh" "$plain" --packs verify >"$tmproot/refuse.log" 2>&1; then
  bad "the verify pack installed into a repo with no Serel Memory (expected exit 1)"
fi
grep -q 'github.com/madeordinary/serel-memory#install' "$tmproot/refuse.log" ||
  bad "the refusal does not point at Serel Memory's install instructions"
[ "$(snapshot "$plain")" = "$before" ] || bad "the refused run wrote to the target"

# The dependency gate matches on the pack name, so a name that spells the same
# directory a different way must not slip past it.
for alias in "verify/" "./verify" ".//verify//"; do
  if bash "$KIT/install.sh" "$plain" --packs "$alias" >"$tmproot/refuse-alias.log" 2>&1; then
    bad "--packs '$alias' installed the verify pack without Serel Memory"
  fi
  [ "$(snapshot "$plain")" = "$before" ] || bad "--packs '$alias' wrote to the target"
done

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

# A receipt that parses but is the wrong shape must stop the run BEFORE the
# payload is copied — otherwise the merge fails over a half-installed pack.
echo "case 1b: a malformed receipt stops the run with zero writes"
badreceipt="$tmproot/bad-receipt"
new_repo "$badreceipt"
printf '{"packs":"writing"}\n' >"$badreceipt/.serel-kit.json"
before_bad="$(snapshot "$badreceipt")"
if bash "$KIT/install.sh" "$badreceipt" --packs writing >"$tmproot/badreceipt.log" 2>&1; then
  bad "a malformed receipt did not stop the install (expected exit 1)"
fi
[ ! -e "$badreceipt/.claude" ] || bad "the malformed-receipt run copied part of the payload"
[ "$(snapshot "$badreceipt")" = "$before_bad" ] || bad "the malformed-receipt run wrote to the target"

# A symlink on a destination path would send the copy wherever it points.
echo "case 1c: a symlinked destination ancestor stops the run with zero writes"
linked="$tmproot/symlinked"
new_repo "$linked"
mkdir -p "$linked/memory-bank" "$linked/.agents"
printf 'the user context this must never touch\n' >"$linked/memory-bank/activeContext.md"
ln -s ../memory-bank "$linked/.agents/skills"
before_link="$(snapshot "$linked")"
if bash "$KIT/install.sh" "$linked" --packs writing >"$tmproot/symlink.log" 2>&1; then
  bad "a symlinked .agents/skills did not stop the install (expected exit 1)"
fi
grep -q 'UNSAFE PATH' "$tmproot/symlink.log" || bad "the symlink run did not report UNSAFE PATH"
grep -q '.agents/skills' "$tmproot/symlink.log" || bad "the symlink run did not name the symlinked path"
[ ! -e "$linked/memory-bank/polish" ] || bad "the symlink run wrote through the link into memory-bank"
[ "$(snapshot "$linked")" = "$before_link" ] || bad "the symlink run wrote to the target"

# A regular file where a directory belongs used to copy the .agents payload
# first and only then fail at mkdir, leaving half a pack behind.
echo "case 1d: a file where a directory belongs stops the run with zero writes"
blocked="$tmproot/blocked-dir"
new_repo "$blocked"
printf 'this is a file, not a directory\n' >"$blocked/.claude"
before_blocked="$(snapshot "$blocked")"
if bash "$KIT/install.sh" "$blocked" --packs writing >"$tmproot/blocked.log" 2>&1; then
  bad "a file at .claude did not stop the install (expected exit 1)"
fi
grep -q 'UNSAFE PATH' "$tmproot/blocked.log" || bad "the blocked-directory run did not report UNSAFE PATH"
[ ! -e "$blocked/.agents" ] || bad "the blocked-directory run copied the .agents payload before failing"
[ "$(snapshot "$blocked")" = "$before_blocked" ] || bad "the blocked-directory run wrote to the target"

# --- cases 2-4: a repo with Serel Memory -------------------------------------

memory=""
if [ -n "${SEREL_MEMORY_REPO:-}" ]; then
  memory="$SEREL_MEMORY_REPO"
  if ! git -C "$memory" rev-parse --git-dir >/dev/null 2>&1 ||
    [ ! -f "$memory/tests/check-parity.sh" ]; then
    echo "FAIL: SEREL_MEMORY_REPO=$memory is not a Serel Memory checkout"
    exit 1
  fi
else
  for candidate in "$KIT/../memory" "$KIT/../serel-memory"; do
    if git -C "$candidate" rev-parse --git-dir >/dev/null 2>&1 &&
      [ -f "$candidate/tests/check-parity.sh" ]; then
      memory="$candidate"
      break
    fi
  done
fi

partial=0
if [ -z "$memory" ]; then
  partial=1
  echo "SKIP: cases 2-4 need the sibling Serel Memory repo (set SEREL_MEMORY_REPO)"
else
  echo "case 2: repo with Serel Memory from $(cd "$memory" && pwd) HEAD"
  proj="$tmproot/with-memory"
  new_repo "$proj"
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
  receipt_inode_before="$(inode_of "$proj/.serel-kit.json")"
  bash "$KIT/install.sh" "$proj" --packs writing,verify >"$tmproot/rerun.log" 2>&1 ||
    bad "re-running with the same packs exited non-zero"
  [ "$(snapshot "$proj")" = "$after_install" ] || bad "re-running changed files in the target"
  [ "$(inode_of "$proj/.serel-kit.json")" = "$receipt_inode_before" ] ||
    bad "re-running replaced the receipt file even though its contents were identical"
  grep -q 'nothing to do' "$tmproot/rerun.log" || bad "the converged re-run did not say there was nothing to do"

  echo "case 4: a divergent local file is a conflict, and nothing is written"
  # Order matters. The deleted file is in .agents/, which the installer reaches
  # before .claude/, so an installer that copied as it scanned would already
  # have written it by the time it met the conflict. Its absence afterwards is
  # what proves the preflight is complete before any write.
  rm "$proj/.agents/skills/polish/RULES.md"
  printf '\nlocal edit that upstream does not have\n' >>"$proj/.claude/commands/polish.md"
  pre_conflict="$(snapshot "$proj")"
  if bash "$KIT/install.sh" "$proj" --packs writing,verify >"$tmproot/conflict.log" 2>&1; then
    bad "a divergent local file did not stop the install (expected exit 1)"
  fi
  grep -q 'CONFLICT' "$tmproot/conflict.log" || bad "the conflicting run did not report CONFLICT"
  grep -q '.claude/commands/polish.md' "$tmproot/conflict.log" ||
    bad "the conflicting run did not name the file that conflicts"
  [ ! -e "$proj/.agents/skills/polish/RULES.md" ] ||
    bad "the conflicting run copied part of the payload before stopping"
  [ "$(snapshot "$proj")" = "$pre_conflict" ] || bad "the conflicting run wrote to the target"
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi

if [ "$partial" -eq 1 ]; then
  echo "smoke-install PARTIAL: Memory not found, cases 2-4 skipped"
  if [ "${SEREL_KIT_ALLOW_PARTIAL:-}" = "1" ]; then
    echo "  accepted because SEREL_KIT_ALLOW_PARTIAL=1"
    exit 0
  fi
  exit 1
fi

echo "install smoke OK: packs install, refuse, converge, and never overwrite"
exit 0
