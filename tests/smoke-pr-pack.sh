#!/usr/bin/env bash
# The pr pack against real repositories in a temp directory.
#
# Cases:
#   1. A plain git repo with no Serel Memory: the pr pack installs, every file
#      under packs/pr/.claude and packs/pr/.agents arrives byte-identical,
#      pr-wait and its license included, and nothing else is written but the
#      receipt.
#   2. pr-wait, run from the installed copy as `python3 -I`, prints its help
#      and exits 0, and a missing or malformed PR argument exits 2. Both stop
#      before pr-wait calls gh or writes its state, so this needs no network
#      and no real PR. The bundled copy still matches the pinned upstream hash.
#   3. A repo with Serel Memory scaffolded from SEREL_MEMORY_REPO (or a sibling
#      ../memory) HEAD: installing pr changes and removes nothing that was
#      there, adds only the pack and the receipt, and Serel Memory's own
#      check-parity and check-readlist still pass.
#
# Case 3 needs a Serel Memory checkout. Without one it is skipped, the run says
# PARTIAL and exits non-zero; set SEREL_KIT_ALLOW_PARTIAL=1 to accept that.
#
# What this proves: installation, and that pr-wait starts. What it does not
# prove: that the workflows behave on a real PR. See packs/pr/README.md.
set -euo pipefail
cd "$(dirname "$0")/.."
KIT="$PWD"
PACK="$KIT/packs/pr"
PR_WAIT=".agents/skills/babysit-pr/scripts/pr-wait"
LICENSE=".agents/skills/babysit-pr/LICENSE-tstack"
PR_WAIT_SHA256="90393f85b95b78bff1b039744bdfb09dc88ff2b430e1c3df687ee6f449c97214"

fail=0
bad() { printf 'FAIL: %s\n' "$*"; fail=1; }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required to run this test"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required to run pr-wait's checks"; exit 1; }
if command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum "$1" | awk '{print $1}'; }
else
  sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
fi

tmproot="$(mktemp -d)"
trap 'rm -rf "$tmproot"' EXIT

# Every entry below the root, with its type, as in smoke-install.sh.
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
  ) | LC_ALL=C sort
}

new_repo() {
  mkdir -p "$1"
  git -C "$1" init -q
}

# The payload comes from the source tree, so the test cannot drift from it.
payload="$(cd "$PACK" && find .claude .agents -type f | LC_ALL=C sort)"
for required in "$PR_WAIT" "$LICENSE" .agents/skills/pr-comment/SKILL.md; do
  printf '%s\n' "$payload" | grep -qxF "$required" || bad "the pr pack source has no $required"
done

# --- case 1: a plain repo ----------------------------------------------------

echo "case 1: pr installs standalone, byte for byte"
plain="$tmproot/plain"
new_repo "$plain"
printf '# demo project\n' >"$plain/README.md"

bash "$KIT/install.sh" "$plain" --packs pr >"$tmproot/plain.log" 2>&1 ||
  { cat "$tmproot/plain.log"; bad "the pr pack failed to install without Serel Memory"; }
while IFS= read -r rel; do
  if [ ! -f "$plain/$rel" ]; then
    bad "not installed: $rel"
  elif ! cmp -s "$PACK/$rel" "$plain/$rel"; then
    bad "installed copy differs from the pack: $rel"
  fi
done <<<"$payload"
expected="$( { printf '%s\n' "$payload" | sed 's|^|./|'; printf './.serel-kit.json\n./README.md\n'; } | LC_ALL=C sort)"
[ "$(cd "$plain" && find . -type f -not -path './.git/*' | LC_ALL=C sort)" = "$expected" ] ||
  bad "the install wrote files other than the pack and the receipt"
[ "$(jq -r '.packs | join(",")' "$plain/.serel-kit.json")" = "pr" ] ||
  bad "the receipt should list only pr"

# --- case 2: pr-wait starts offline ------------------------------------------

echo "case 2: pr-wait prints help and rejects bad input without GitHub"
[ "$(sha256 "$PACK/$PR_WAIT")" = "$PR_WAIT_SHA256" ] ||
  bad "packs/pr/$PR_WAIT no longer matches the upstream sha256 its provenance records"
for doc in "$PACK/README.md" "$PACK/.claude/commands/babysit-pr.md" "$PACK/.agents/skills/babysit-pr/SKILL.md"; do
  grep -qF "$PR_WAIT_SHA256" "$doc" || bad "${doc#"$KIT"/} does not record pr-wait's sha256"
done

# A private HOME proves these runs leave no pr-wait state behind.
home="$tmproot/home"
mkdir "$home"
if ! HOME="$home" python3 -I "$plain/$PR_WAIT" --help >"$tmproot/help.log" 2>&1; then
  cat "$tmproot/help.log"
  bad "pr-wait --help exited non-zero"
fi
grep -q -- '--until' "$tmproot/help.log" || bad "pr-wait --help did not describe --until"
expect_bad_input() {
  local rc=0
  HOME="$home" python3 -I "$plain/$PR_WAIT" "$@" >"$tmproot/bad.log" 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || { cat "$tmproot/bad.log"; bad "pr-wait ${*:-<no PR>} exited $rc, expected 2"; }
}
expect_bad_input not-a-pr
expect_bad_input
[ -z "$(find "$home" -mindepth 1 -print)" ] || bad "pr-wait wrote state for bad input"

# --- case 3: beside Serel Memory ---------------------------------------------

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
  echo "SKIP: case 3 needs a Serel Memory checkout (set SEREL_MEMORY_REPO)"
else
  echo "case 3: pr beside Serel Memory from $(cd "$memory" && pwd) HEAD leaves Memory untouched"
  proj="$tmproot/with-memory"
  new_repo "$proj"
  git -C "$memory" archive --format=tar HEAD | tar -x -C "$proj"
  # The anchor is export-ignored upstream; a real install writes its own.
  printf '{ "upstream": "madeordinary/serel-memory", "ref": "smoke", "linked": false }\n' \
    >"$proj/.serel-memory.json"
  snapshot "$proj" >"$tmproot/memory-before"

  bash "$KIT/install.sh" "$proj" --packs pr >"$tmproot/memory.log" 2>&1 ||
    { cat "$tmproot/memory.log"; bad "the pr pack failed to install beside Serel Memory"; }
  snapshot "$proj" >"$tmproot/memory-after"

  changed="$(LC_ALL=C comm -23 "$tmproot/memory-before" "$tmproot/memory-after")"
  [ -z "$changed" ] || bad "installing pr changed or removed existing entries: $changed"
  added_files=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    path="${line#* }"
    path="${path# }"
    path="${path%% *}"
    path="${path#./}"
    case "$path" in
      .serel-kit.json | .claude/commands/file-pr.md | .claude/commands/babysit-pr.md | \
        .claude/commands/modernize-pr.md | .claude/commands/pr-comment.md | \
        .agents/skills/file-pr | .agents/skills/file-pr/* | \
        .agents/skills/babysit-pr | .agents/skills/babysit-pr/* | \
        .agents/skills/modernize-pr | .agents/skills/modernize-pr/* | \
        .agents/skills/pr-comment | .agents/skills/pr-comment/*) ;;
      *) bad "installing pr added an entry outside the pack: $line" ;;
    esac
    case "$line" in file\ *) added_files=$((added_files + 1)) ;; esac
  done < <(LC_ALL=C comm -13 "$tmproot/memory-before" "$tmproot/memory-after")
  expected_files=$(($(printf '%s\n' "$payload" | wc -l) + 1))
  [ "$added_files" -eq "$expected_files" ] ||
    bad "installing pr added $added_files files, expected $expected_files (the pack and the receipt)"
  while IFS= read -r rel; do
    cmp -s "$PACK/$rel" "$proj/$rel" || bad "installed copy beside Memory differs from the pack: $rel"
  done <<<"$payload"

  # Serel Memory's own checks must still pass with the pack in place.
  bash "$proj/tests/check-parity.sh" >"$tmproot/parity.log" 2>&1 ||
    { cat "$tmproot/parity.log"; bad "Serel Memory's check-parity.sh fails with the pr pack installed"; }
  bash "$proj/tests/check-readlist.sh" >"$tmproot/readlist.log" 2>&1 ||
    { cat "$tmproot/readlist.log"; bad "Serel Memory's check-readlist.sh fails with the pr pack installed"; }
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi

if [ "$partial" -eq 1 ]; then
  echo "smoke-pr-pack PARTIAL: Memory not found, case 3 skipped"
  if [ "${SEREL_KIT_ALLOW_PARTIAL:-}" = "1" ]; then
    echo "  accepted because SEREL_KIT_ALLOW_PARTIAL=1"
    exit 0
  fi
  exit 1
fi

echo "pr pack smoke OK: installs byte for byte, alone and beside Memory; pr-wait starts offline"
exit 0
