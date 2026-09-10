#!/usr/bin/env bash
# Serel Kit pack installer.
#
# Copies optional workflow packs (Claude Code commands + Codex skills) into a
# target git repository. It does not install, upgrade, or reconfigure Serel
# Memory — it only detects Memory and refuses packs that need it. It never
# overwrites an existing file, and it writes nothing outside `.claude/`,
# `.agents/`, and the `.serel-kit.json` receipt.
#
# Requires: bash, git, jq.
set -euo pipefail

KIT_VERSION="0.1.0"
KIT_ROOT="$(cd "$(dirname "$0")" && pwd)"
MEMORY_INSTALL_URL="https://github.com/madeordinary/serel-memory#install"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

pack_summary() {
  case "$1" in
    writing) printf '/polish     rewrite named text to the house rules, diff only' ;;
    verify)  printf '/verify-map feature verification maps (needs Serel Memory)' ;;
    *)       printf 'no summary' ;;
  esac
}

pack_requires_memory() {
  case "$1" in
    verify) return 0 ;;
    *) return 1 ;;
  esac
}

# Files the installer must never create or touch. The payload can only contain
# `.claude/` and `.agents/` paths, so this is a backstop that fails loudly if a
# pack is ever shaped wrong.
is_protected() {
  case "$1" in
    .rules|.serel-memory.json|AGENTS.md|CLAUDE.md) return 0 ;;
    memory-bank/*|memory-bank.local/*) return 0 ;;
    *) return 1 ;;
  esac
}

list_packs() {
  local dir name
  printf 'Available packs:\n'
  for dir in "$KIT_ROOT"/packs/*/; do
    name="$(basename "$dir")"
    printf '  %-8s %s\n' "$name" "$(pack_summary "$name")"
  done
}

usage() {
  cat <<'USAGE_END'
Usage: install.sh <target-repo> --packs <pack>[,<pack>...]

Installs Serel Kit workflow packs into a git repository. Both adapters travel
together: a Claude Code slash command and a Codex skill.

Options:
  --packs <list>   comma-separated pack names (required)
  --list           list the available packs and exit
  -h, --help       show this text

Rules:
  - The target must be the root of a git repository.
  - An existing file is never overwritten. A file that differs from the pack
    is a conflict: the run stops and writes nothing.
  - Re-running with the same packs changes nothing and exits 0.
USAGE_END
}

# --- arguments ---------------------------------------------------------------

target=""
packs_arg=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --list) list_packs; exit 0 ;;
    --packs)
      [ "$#" -ge 2 ] || die "--packs needs a value, e.g. --packs writing,verify"
      packs_arg="$2"; shift 2 ;;
    --packs=*) packs_arg="${1#--packs=}"; shift ;;
    -*) die "unknown option: $1" ;;
    *)
      [ -z "$target" ] || die "only one target is allowed (got '$target' and '$1')"
      target="$1"; shift ;;
  esac
done

if [ -z "$target" ]; then usage >&2; exit 1; fi
[ -n "$packs_arg" ] || die "--packs is required (try: install.sh <repo> --packs writing)"
command -v git >/dev/null 2>&1 || die "git is required"
command -v jq >/dev/null 2>&1 || die "jq is required (the installation receipt is JSON)"

[ -d "$target" ] || die "target is not a directory: $target"
# Physical paths on both sides: git reports the resolved root, so a target
# reached through a symlink (/tmp on macOS) must be resolved the same way.
target="$(cd "$target" && pwd -P)"
toplevel="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$toplevel" ] || die "target is not a git repository: $target"
toplevel="$(cd "$toplevel" && pwd -P)"
[ "$toplevel" = "$target" ] || die "target must be the repository root, which is: $toplevel"

# --- packs -------------------------------------------------------------------

IFS=',' read -r -a raw_packs <<<"$packs_arg"
packs=()
seen=" "
for p in "${raw_packs[@]}"; do
  [ -n "$p" ] || continue
  case "$seen" in *" $p "*) continue ;; esac
  seen="$seen$p "
  [ -d "$KIT_ROOT/packs/$p" ] || die "no such pack: $p (run: install.sh --list)"
  [ -d "$KIT_ROOT/packs/$p/.claude/commands" ] || die "pack '$p' has no .claude/commands directory"
  [ -d "$KIT_ROOT/packs/$p/.agents/skills" ] || die "pack '$p' has no .agents/skills directory"
  packs+=("$p")
done
[ "${#packs[@]}" -gt 0 ] || die "--packs listed no pack names"

# --- Serel Memory gate -------------------------------------------------------

has_memory=0
if [ -f "$target/.serel-memory.json" ]; then has_memory=1; fi

blocked=""
for p in "${packs[@]}"; do
  if pack_requires_memory "$p" && [ "$has_memory" -eq 0 ]; then
    blocked="$blocked $p"
  fi
done

if [ -n "$blocked" ]; then
  printf 'error: these packs need Serel Memory in the target repo:%s\n' "$blocked" >&2
  printf '\n' >&2
  printf '  No .serel-memory.json was found in %s\n' "$target" >&2
  printf '  Serel Kit does not install Serel Memory. Install it first:\n' >&2
  printf '  %s\n' "$MEMORY_INSTALL_URL" >&2
  printf '\n' >&2
  printf '  Then run this command again. Nothing was written.\n' >&2
  exit 1
fi

# --- preflight ---------------------------------------------------------------

# The payload is every file under a pack's .claude/ and .agents/ directories.
# The pack README stays in the Kit; it is documentation, not payload.
payload_files() {
  ( cd "$KIT_ROOT/packs/$1" && find .claude .agents -type f | sed 's|^\./||' | sort )
}

copy_src=()
copy_rel=()
conflicts=()
identical=0

for p in "${packs[@]}"; do
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if is_protected "$rel"; then
      die "pack '$p' would write a protected path ($rel) — refusing"
    fi
    src="$KIT_ROOT/packs/$p/$rel"
    dst="$target/$rel"
    if [ -e "$dst" ]; then
      if cmp -s "$src" "$dst"; then
        identical=$((identical + 1))
      else
        conflicts+=("$rel")
      fi
    else
      copy_src+=("$src")
      copy_rel+=("$rel")
    fi
  done < <(payload_files "$p")
done

if [ "${#conflicts[@]}" -gt 0 ]; then
  printf 'CONFLICT: %d file(s) already exist in the target and differ from the pack:\n' "${#conflicts[@]}" >&2
  for c in "${conflicts[@]}"; do printf '  %s\n' "$c" >&2; done
  printf '\n' >&2
  printf 'Nothing was written. Serel Kit never overwrites. Either keep your version\n' >&2
  printf '(drop that pack), or move yours aside and run this again.\n' >&2
  exit 1
fi

receipt="$target/.serel-kit.json"
if [ -e "$receipt" ]; then
  jq -e . "$receipt" >/dev/null 2>&1 || die "existing $receipt is not valid JSON — fix or remove it; nothing was written"
fi

# --- write -------------------------------------------------------------------

copied=0
if [ "${#copy_rel[@]}" -gt 0 ]; then
  for ((i = 0; i < ${#copy_rel[@]}; i++)); do
    dst="$target/${copy_rel[$i]}"
    mkdir -p "$(dirname "$dst")"
    cp "${copy_src[$i]}" "$dst"
    copied=$((copied + 1))
  done
fi

# The receipt records what this installer put here. It is a receipt, never an
# authority over Serel Memory's own `.serel-memory.json` anchor. Unknown keys
# in an existing receipt are preserved.
packs_json="$(printf '%s\n' "${packs[@]}" | jq -R . | jq -s .)"
tmp_receipt="$receipt.tmp.$$"
if [ -e "$receipt" ]; then
  jq --arg kit "$KIT_VERSION" --argjson added "$packs_json" \
    '.kit = $kit | .packs = (((.packs // []) + $added) | unique)' "$receipt" >"$tmp_receipt"
else
  jq -n --arg kit "$KIT_VERSION" --argjson added "$packs_json" \
    '{kit: $kit, packs: ($added | unique)}' >"$tmp_receipt"
fi
mv "$tmp_receipt" "$receipt"

printf 'Serel Kit %s -> %s\n' "$KIT_VERSION" "$target"
printf '  packs:     %s\n' "$(printf '%s ' "${packs[@]}" | sed 's/ $//')"
printf '  copied:    %d file(s)\n' "$copied"
printf '  identical: %d file(s) already matched\n' "$identical"
printf '  receipt:   .serel-kit.json\n'
if [ "$copied" -eq 0 ]; then
  printf '  nothing to do — this target is already up to date.\n'
fi
