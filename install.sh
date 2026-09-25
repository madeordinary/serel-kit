#!/usr/bin/env bash
# Serel Kit pack installer.
#
# Copies optional workflow packs (Claude Code commands + Codex skills) into a
# target git repository. It does not install, upgrade, or reconfigure Serel
# Memory — it only detects Memory and refuses packs that need it. It never
# overwrites an existing file during installation; upgrades require --apply.
# It writes nothing outside `.claude/`,
# `.agents/`, and the `.serel-kit.json` receipt, except that a local install
# appends exact Kit paths to the repository's Git-resolved `info/exclude`.
#
# Requires: bash, git, jq, and sha256sum or shasum.
set -euo pipefail

KIT_VERSION="0.2.0"
KIT_ROOT="$(cd "$(dirname "$0")" && pwd)"
MEMORY_INSTALL_URL="https://github.com/madeordinary/serel-memory#install"
EXCLUDE_HEADER="# Serel Kit local install: exact paths recorded in .serel-kit.json"

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
       install.sh <target-repo> --packs <pack>[,<pack>...] --local [--apply]
       install.sh <target-repo> --packs <pack>[,<pack>...] --upgrade [--apply]

Installs Serel Kit workflow packs into a git repository. Both adapters travel
together: a Claude Code slash command and a Codex skill.

Options:
  --packs <list>   comma-separated pack names (required)
  --local          preview an install kept out of Git: each Kit file and the
                   receipt get an exact-path line in Git's info/exclude
  --upgrade        preview an upgrade using the recorded upstream baseline
  --apply          apply a local install or a conflict-free upgrade
  --list           list the available packs and exit
  -h, --help       show this text

Rules:
  - The target must be the root of a git repository.
  - During installation an existing file is never overwritten. A file that differs from the pack
    is a conflict: the run stops and writes nothing.
  - Re-running with the same packs changes nothing and exits 0.
  - The receipt records a local install. Later runs stay local and preview
    until --apply, with or without --local. A shared install never becomes
    local, and a Kit path Git tracks is refused.
USAGE_END
}

# --- arguments ---------------------------------------------------------------

target=""
packs_arg=""
upgrade=0
apply=0
local_flag=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --list) list_packs; exit 0 ;;
    --packs)
      [ "$#" -ge 2 ] || die "--packs needs a value, e.g. --packs writing,verify"
      packs_arg="$2"; shift 2 ;;
    --packs=*) packs_arg="${1#--packs=}"; shift ;;
    --upgrade) upgrade=1; shift ;;
    --apply) apply=1; shift ;;
    --local) local_flag=1; shift ;;
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
for raw in "${raw_packs[@]}"; do
  # Canonicalize the name before anything downstream sees it. `verify`,
  # `verify/` and `./verify` are the same directory but not the same string,
  # and the Serel Memory dependency gate below matches on the string.
  p="$raw"
  while [ "${p#./}" != "$p" ]; do p="${p#./}"; done
  while [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  [ -n "$p" ] || continue
  case "$p" in
    */*) die "a pack name is a plain name, not a path: '$raw'" ;;
  esac
  # Match the name against the real entries of packs/, byte for byte. Testing
  # `-d packs/$p` would accept `Verify` on a case-insensitive filesystem, which
  # resolves to the verify payload while the Serel Memory gate below — which
  # compares strings — would not recognize it.
  known=0
  for dir in "$KIT_ROOT"/packs/*/; do
    if [ "$(basename "$dir")" = "$p" ]; then known=1; break; fi
  done
  [ "$known" -eq 1 ] || die "no such pack: '$raw' (run: install.sh --list)"
  case "$seen" in *" $p "*) continue ;; esac
  seen="$seen$p "
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

# --- plan and baseline -------------------------------------------------------

if command -v sha256sum >/dev/null 2>&1; then
  hash_stream() { sha256sum | awk '{print $1}'; }
elif command -v shasum >/dev/null 2>&1; then
  hash_stream() { shasum -a 256 | awk '{print $1}'; }
else
  die "sha256sum or shasum is required"
fi
hash_file() { hash_stream <"$1"; }

# Restrict receipt paths as strictly as payload paths. They never authorize
# writing arbitrary repository files, even if a receipt has been hand-edited.
valid_payload_path() {
  [[ "$1" =~ ^[A-Za-z0-9_./-]+$ ]] || return 1
  case "/$1/" in *"/../"*|*"/./"*|*"//"*) return 1 ;; esac
  case "$1" in
    .claude/commands/*|.agents/skills/*/*) ! is_protected "$1" ;;
    *) return 1 ;;
  esac
}

check_path_safety() {
  local rest="$1" acc="" seg abs parent="$target"
  while [ -n "$rest" ]; do
    seg="${rest%%/*}"
    if [ "$seg" = "$rest" ]; then rest=""; else rest="${rest#*/}"; fi
    if [ -z "$acc" ]; then acc="$seg"; else acc="$acc/$seg"; fi
    abs="$target/$acc"
    [ ! -L "$abs" ] || die "UNSAFE PATH: $acc is a symlink; nothing was written"
    if [ -e "$abs" ]; then
      # A case-insensitive filesystem opens .Claude for .claude, but Git sees
      # the spelling on disk, which the receipt and exclusions would not name.
      [ -n "$(find "$parent" -mindepth 1 -maxdepth 1 -name "$seg" -print)" ] ||
        die "UNSAFE PATH: $acc exists with different letter case; nothing was written"
      if [ -n "$rest" ]; then
        [ -d "$abs" ] || die "UNSAFE PATH: $acc is not a directory; nothing was written"
      else
        [ -f "$abs" ] || die "UNSAFE PATH: $acc is not a regular file; nothing was written"
        [ -z "$(find "$abs" -prune -links +1 -print)" ] ||
          die "UNSAFE PATH: $acc has multiple hard links; nothing was written"
      fi
    fi
    parent="$abs"
  done
}

hash_or_absent() {
  if [ -f "$1" ]; then hash_file "$1"; else printf 'absent\n'; fi
}
current_hash() { hash_or_absent "$target/$1"; }

work="$(mktemp -d)"
write_rel=()
write_src=()
written=()
created_dirs=()
watch_rel=()
watch_hash=()
applying=0
success=0
# Local mode only: Git's exclude file, and what this run did to it.
exclude_file=""
exclude_dir=""
exclude_touched=0
exclude_dir_created=0
new_exclusions=0

# Roll back ordinary copy/mkdir failures. This is not a crash-atomic
# transaction: run with one writer and keep project changes in version control.
cleanup() {
  local rc=$? n rel
  trap - EXIT
  set +e
  if [ "$applying" -eq 1 ] && [ "$success" -eq 0 ]; then
    printf 'Apply failed; restoring files changed by this run.\n' >&2
    for ((n = ${#written[@]} - 1; n >= 0; n--)); do
      rel="${write_rel[${written[$n]}]}"
      if [ -f "$work/backups/${written[$n]}" ]; then
        cp -p "$work/backups/${written[$n]}" "$target/$rel" ||
          printf 'RESTORE FAILED: %s (backup: %s)\n' "$rel" "$work/backups/${written[$n]}" >&2
      else
        rm -f "$target/$rel"
      fi
    done
    for ((n = ${#created_dirs[@]} - 1; n >= 0; n--)); do
      rmdir "$target/${created_dirs[$n]}" 2>/dev/null
    done
    # Exclusions went in before any file, so they come out after every file.
    if [ "$exclude_touched" -eq 1 ]; then
      if [ -f "$work/exclude-backup" ]; then
        cp "$work/exclude-backup" "$exclude_file" ||
          printf 'RESTORE FAILED: %s (backup: %s)\n' "$exclude_file" "$work/exclude-backup" >&2
      else
        rm -f "$exclude_file"
      fi
      if [ "$exclude_dir_created" -eq 1 ]; then rmdir "$exclude_dir" 2>/dev/null; fi
    fi
  fi
  # Keep backups on failure so a failed restore remains recoverable.
  if [ "$applying" -eq 1 ] && [ "$success" -eq 0 ]; then
    printf 'Recovery files retained at %s\n' "$work" >&2
  else
    rm -rf "$work"
  fi
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

receipt="$target/.serel-kit.json"
check_path_safety .serel-kit.json
watch_rel+=(".serel-kit.json")
watch_hash+=("$(current_hash .serel-kit.json)")
if [ -f "$receipt" ]; then
  # Slurp: exactly one document. Every later jq reads only its last result, so
  # a second document appended to a valid receipt would silently replace it.
  jq -e -s '
    def payload_path:
      (test("[^A-Za-z0-9_./-]") | not)
      and (startswith(".claude/commands/") or test("^\\.agents/skills/[^/]+/"))
      and (split("/") | all(.[]; . != "" and . != "." and . != ".."));
    length == 1 and (.[0] |
    type == "object"
    and ((has("packs") | not) or (.packs | type == "array" and all(.[]; type == "string" and test("^[A-Za-z0-9_-]+\\z"))))
    and ((has("kit") | not) or (.kit | type == "string"))
    and ((has("local") | not) or (.local | type == "boolean"))
    and ((has("installed") | not) or (.installed | type == "object" and all(to_entries[];
      (.key | test("^[A-Za-z0-9_-]+\\z")) and
      (.value | type == "object" and (.version | type == "string") and
        (.files == null or (.files | type == "object" and all(to_entries[];
          (.key | payload_path) and (.value | type == "string" and test("^[0-9a-f]{64}\\z"))))))))))
  ' "$receipt" >/dev/null 2>&1 || die "existing $receipt is not a valid Serel Kit receipt; nothing was written"
  cp "$receipt" "$work/receipt-old.json"
else
  printf '{}\n' >"$work/receipt-old.json"
fi
jq -r '.installed // {} | .[].files // {} | keys[]' "$work/receipt-old.json" >"$work/recorded-paths"
while IFS= read -r rel; do
  valid_payload_path "$rel" || die "unsafe receipt path: $rel; nothing was written"
done <"$work/recorded-paths"

# Local mode belongs to the installation, not to one run: once recorded, every
# later run keeps the Kit's files out of Git. A shared installation is never
# converted, because an ignore rule cannot hide a file Git already tracks.
local_mode="$local_flag"
if jq -e '.local == true' "$work/receipt-old.json" >/dev/null; then
  local_mode=1
elif [ "$local_flag" -eq 1 ] &&
  jq -e '((.packs // []) + (.installed // {} | keys)) | length > 0' "$work/receipt-old.json" >/dev/null; then
  die "$receipt records a shared installation; --local cannot make it local. Nothing was written."
fi
[ "$apply" -eq 0 ] || [ "$upgrade" -eq 1 ] || [ "$local_mode" -eq 1 ] ||
  die "--apply requires --upgrade or --local"

# Freeze each legacy pack's old version before advancing the top-level
# installer version. An unselected legacy pack must not acquire a new baseline.
jq '
  .kit as $legacy |
  .installed = (.installed // {}) |
  reduce (.packs // [])[] as $p (.;
    if .installed[$p] == null then
      .installed[$p] = {version: ($legacy // ""), files: null}
    else . end)
' "$work/receipt-old.json" >"$work/receipt-new.json"

set_hash() {
  jq --arg path "$2" --arg hash "$3" '.[$path] = $hash' "$1" >"$work/json-next"
  mv "$work/json-next" "$1"
}

legacy_baseline() {
  local pack="$1" version="$2" output="$3" root commit entry meta path mode digest
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]] ||
    die "pack '$pack' has no usable recorded version; cannot establish its baseline"
  root="$(git -C "$KIT_ROOT" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -z "$root" ] || [ "$(cd "$root" && pwd -P)" != "$(cd "$KIT_ROOT" && pwd -P)" ]; then
    die "legacy upgrades need the original Kit git checkout with tag v$version"
  fi
  commit="$(git -C "$KIT_ROOT" rev-parse --verify "refs/tags/v$version^{commit}" 2>/dev/null)" ||
    die "baseline tag v$version is unavailable locally; obtain that Kit tag, then retry (no files written)"
  git -C "$KIT_ROOT" ls-tree -r "$commit" -- "packs/$pack/.claude" "packs/$pack/.agents" >"$work/tree"
  [ -s "$work/tree" ] || die "tag v$version has no payload for '$pack'"
  printf '{}\n' >"$output"
  while IFS= read -r entry; do
    meta="${entry%%$'\t'*}"; path="${entry#*$'\t'}"; mode="${meta%% *}"
    case "$mode" in 100644|100755) ;; *) die "unsafe baseline entry: $path" ;; esac
    path="${path#packs/"$pack"/}"
    valid_payload_path "$path" || die "unsafe baseline path: $path"
    digest="$(git -C "$KIT_ROOT" show "$commit:packs/$pack/$path" | hash_stream)"
    set_hash "$output" "$path" "$digest"
  done <"$work/tree"
}

printf 'Serel Kit %s -> %s\n' "$KIT_VERSION" "$target"
if [ "$upgrade" -eq 1 ]; then
  printf 'Upgrade plan (no files written yet):\n'
elif [ "$local_mode" -eq 1 ]; then
  printf 'Local install plan (no files written yet):\n'
fi
printf '{}\n' >"$work/owners.json"
conflicts=0
identical=0
kept=0
retired=0
for p in "${packs[@]}"; do
  base="$work/base-$p.json"
  incoming="$work/incoming-$p.json"
  printf '{}\n' >"$base"
  printf '{}\n' >"$incoming"
  if [ "$upgrade" -eq 1 ]; then
    jq -e --arg p "$p" '(.packs // []) | index($p) != null' "$work/receipt-old.json" >/dev/null ||
      die "pack '$p' is not recorded as installed; install it first"
    jq --arg p "$p" '.installed[$p].files' "$work/receipt-new.json" >"$base"
    if [ "$(cat "$base")" = "null" ]; then
      legacy_baseline "$p" "$(jq -r --arg p "$p" '.installed[$p].version' "$work/receipt-new.json")" "$base"
    fi
  fi
  # Reject links (including linked directories) and special files before find
  # can silently omit them. The trusted source is then copied into staging.
  if [ -L "$KIT_ROOT/packs" ] || [ -L "$KIT_ROOT/packs/$p" ]; then
    die "unsafe source pack: $p"
  fi
  find "$KIT_ROOT/packs/$p/.claude" "$KIT_ROOT/packs/$p/.agents" ! -type d ! -type f >"$work/special"
  [ ! -s "$work/special" ] || die "pack '$p' contains a symlink or special file"
  (cd "$KIT_ROOT/packs/$p" && find .claude .agents -type f | sort) >"$work/payload"
  [ -s "$work/payload" ] || die "pack '$p' has no payload"
  while IFS= read -r rel; do
    valid_payload_path "$rel" || die "unsafe payload path: $rel"
    check_path_safety "$rel"
    # Compare complete paths and file/directory prefixes, case-folded so a
    # plan cannot collide when applied to a case-insensitive filesystem.
    jq -e --arg path "$rel" '
      ($path | ascii_downcase) as $wanted |
      [keys[] | ascii_downcase | . as $known |
        . == $wanted or startswith($wanted + "/") or ($wanted | startswith($known + "/"))] | any | not
    ' "$work/owners.json" >/dev/null ||
      die "overlapping selected payload paths at $rel; nothing was written"
    jq -e --arg path "$rel" --arg p "$p" '
      ($path | ascii_downcase) as $wanted |
      [.installed // {} | to_entries[] | select(.key != $p) |
        .value.files // {} | keys[] | ascii_downcase | . as $known |
        . == $wanted or startswith($wanted + "/") or ($wanted | startswith($known + "/"))] | any | not
    ' "$work/receipt-old.json" >/dev/null || die "another installed pack owns an overlapping path at $rel"
    set_hash "$work/owners.json" "$rel" "$p"
    mkdir -p "$work/source/$p/$(dirname "$rel")"
    cp -p "$KIT_ROOT/packs/$p/$rel" "$work/source/$p/$rel"
    src="$work/source/$p/$rel"
    next="$(hash_file "$src")"
    old="$(jq -r --arg path "$rel" '.[$path] // "absent"' "$base")"
    local_hash="$(current_hash "$rel")"
    watch_rel+=("$rel"); watch_hash+=("$local_hash")
    set_hash "$incoming" "$rel" "$next"
    action=""
    if [ "$local_hash" = "$next" ]; then
      action="IDENTICAL"; identical=$((identical + 1))
    elif [ "$upgrade" -eq 0 ]; then
      if [ "$local_hash" = "absent" ]; then action="ADD"; else action="CONFLICT"; fi
    elif [ "$old" = "absent" ]; then
      if [ "$local_hash" = "absent" ]; then action="ADD"; else action="CONFLICT"; fi
    elif [ "$local_hash" = "absent" ]; then
      action="CONFLICT" # Do not resurrect a locally deleted managed file.
    elif [ "$local_hash" = "$old" ]; then
      action="UPDATE"
    elif [ "$next" = "$old" ]; then
      action="KEEP LOCAL"; kept=$((kept + 1))
    else
      action="CONFLICT"
    fi
    printf '  %-10s %s\n' "$action" "$rel"
    case "$action" in
      ADD|UPDATE) write_rel+=("$rel"); write_src+=("$src") ;;
      CONFLICT) conflicts=$((conflicts + 1)) ;;
    esac
    if [ "$upgrade" -eq 1 ]; then
      case "$action" in
        ADD|UPDATE|CONFLICT)
          from="$target/$rel"
          [ -f "$from" ] || from=/dev/null
          if diff -u "$from" "$src"; then :; else
            rc=$?
            [ "$rc" -eq 1 ] || die "could not compare $rel"
          fi ;;
      esac
    fi
  done <"$work/payload"
  jq -r --slurpfile next "$incoming" 'keys[] | select($next[0][.] == null)' "$base" >"$work/retired"
  while IFS= read -r rel; do
    printf '  RETIRED    %s (left as-is; no longer managed)\n' "$rel"
    retired=$((retired + 1))
  done <"$work/retired"
  jq --arg p "$p" --arg version "$KIT_VERSION" --slurpfile files "$incoming" '
    .installed[$p] = ((.installed[$p] // {}) + {version: $version, files: $files[0]})
  ' "$work/receipt-new.json" >"$work/json-next"
  mv "$work/json-next" "$work/receipt-new.json"
done

[ "$conflicts" -eq 0 ] || die "CONFLICT: $conflicts file(s); nothing was written. Back up and reconcile each local file with its source under $KIT_ROOT/packs, then retry. There is no force option."
packs_json="$(printf '%s\n' "${packs[@]}" | jq -R . | jq -s .)"
jq --arg kit "$KIT_VERSION" --argjson added "$packs_json" --argjson local "$local_mode" '
  .kit = $kit | .packs = (((.packs // []) + $added) | unique)
  | if $local == 1 then .local = true else . end
' "$work/receipt-new.json" >"$work/receipt-final.json"
if [ ! -f "$receipt" ] || ! cmp -s "$receipt" "$work/receipt-final.json"; then
  write_rel+=(".serel-kit.json"); write_src+=("$work/receipt-final.json")
fi

# --- local mode: Git exclusions ----------------------------------------------

# Git resolves the file, so a linked worktree uses its repository's shared
# info/exclude. Hold it to the same link rules as the payload.
check_exclude_file() {
  [ ! -L "$exclude_dir" ] || die "UNSAFE PATH: $exclude_dir is a symlink; nothing was written"
  [ ! -e "$exclude_dir" ] || [ -d "$exclude_dir" ] ||
    die "UNSAFE PATH: $exclude_dir is not a directory; nothing was written"
  [ ! -L "$exclude_file" ] || die "UNSAFE PATH: $exclude_file is a symlink; nothing was written"
  if [ -e "$exclude_file" ]; then
    [ -f "$exclude_file" ] || die "UNSAFE PATH: $exclude_file is not a regular file; nothing was written"
    [ -z "$(find "$exclude_file" -prune -links +1 -print)" ] ||
      die "UNSAFE PATH: $exclude_file has multiple hard links; nothing was written"
  fi
}

# git_ignores <path> [git options]: 0 if Git ignores the path, 1 if not.
git_ignores() {
  local path="$1" rc
  shift
  if git -C "$target" "$@" check-ignore -q -- "$path"; then return 0; else
    rc=$?
    [ "$rc" -eq 1 ] || die "could not check Git's ignore rules for $path"
    return 1
  fi
}

if [ "$local_mode" -eq 1 ]; then
  exclude_file="$(git -C "$target" rev-parse --git-path info/exclude)" ||
    die "could not resolve this repository's info/exclude"
  case "$exclude_file" in /*) ;; *) exclude_file="$target/$exclude_file" ;; esac
  exclude_dir="$(dirname "$exclude_file")"
  check_exclude_file
  exclude_hash="$(hash_or_absent "$exclude_file")"

  # Every file of every recorded pack, plus the receipt: a rerun also repairs
  # a deleted line. Exact anchored paths only, never .claude/ or .agents/.
  { jq -r '.installed // {} | .[].files // {} | keys[]' "$work/receipt-final.json"
    printf '.serel-kit.json\n'; } | LC_ALL=C sort -u >"$work/local-paths"
  specs=()
  while IFS= read -r rel; do
    valid_payload_path "$rel" || [ "$rel" = .serel-kit.json ] || die "unsafe local path: $rel"
    specs+=(":(icase)$rel")
  done <"$work/local-paths"

  # An ignore rule cannot hide a tracked file, so pretending would share it.
  # icase: a case-insensitive filesystem resolves a case variant to our file.
  git -C "$target" ls-files -z --cached -- "${specs[@]}" >"$work/tracked" ||
    die "could not read the Git index"
  if [ -s "$work/tracked" ]; then
    tr '\0' '\n' <"$work/tracked" | while IFS= read -r rel; do printf '  %-10s %s\n' TRACKED "$rel"; done
    die "TRACKED: Git tracks these Kit paths, so --local cannot keep them out of Git. The installer never removes files from Git. Nothing was written."
  fi

  printf 'Git exclusions in %s:\n' "$exclude_file"
  : >"$work/exclude-lines"
  : >"$work/exclude-sim"
  while IFS= read -r rel; do
    printf '/%s\n' "$rel" >>"$work/exclude-sim"
    if [ -f "$exclude_file" ] && grep -qxF -- "/$rel" "$exclude_file"; then
      printf '  %-10s /%s\n' PRESENT "$rel"
    else
      printf '  %-10s /%s\n' EXCLUDE "$rel"
      printf '/%s\n' "$rel" >>"$work/exclude-lines"
      new_exclusions=$((new_exclusions + 1))
    fi
  done <"$work/local-paths"

  # Predict the result without writing: .gitignore files and info/exclude
  # outrank core.excludesFile, so a negation there still shows up here.
  unignored=0
  while IFS= read -r rel; do
    if ! git_ignores "$rel" -c core.excludesFile="$work/exclude-sim"; then
      reason="$(git -C "$target" -c core.excludesFile="$work/exclude-sim" check-ignore -v -n -- "$rel" 2>/dev/null || true)"
      printf '  %-10s %s (%s)\n' VISIBLE "$rel" "${reason%%$'\t'*}"
      unignored=$((unignored + 1))
    fi
  done <"$work/local-paths"
  [ "$unignored" -eq 0 ] ||
    die "an ignore rule re-includes $unignored Kit path(s), so --local cannot keep them out of Git. Change that rule or install shared. Nothing was written."

  : >"$work/exclude-add"
  if [ "$new_exclusions" -gt 0 ]; then
    last=""
    if [ -s "$exclude_file" ]; then
      if [ -n "$(tail -c 1 "$exclude_file")" ]; then printf '\n' >>"$work/exclude-add"; fi
      last="$(awk 'NF { last = $0 } END { print last }' "$exclude_file")"
    fi
    # Continue Kit's block only when it is last, so Kit lines never land under
    # another tool's comment, such as Serel Memory's.
    if [ "$last" != "$EXCLUDE_HEADER" ] && ! grep -qxF -- "$last" "$work/exclude-sim"; then
      printf '%s\n' "$EXCLUDE_HEADER" >>"$work/exclude-add"
    fi
    cat "$work/exclude-lines" >>"$work/exclude-add"
  fi
  printf 'Local only: not committed or pushed, not access control, not backed up; git clean -x deletes these files.\n'
fi

if [ "$apply" -eq 0 ] && { [ "$upgrade" -eq 1 ] || [ "$local_mode" -eq 1 ]; }; then
  printf 'Preview only. %d file write(s), including any receipt update' "${#write_rel[@]}"
  if [ "$local_mode" -eq 1 ]; then printf ', and %d new Git exclusion(s)' "$new_exclusions"; fi
  if [ "$upgrade" -eq 1 ]; then
    printf '. Re-run with --upgrade --apply to apply this plan.\n'
  else
    printf '. Re-run with --local --apply to apply this plan.\n'
  fi
  exit 0
fi

# --- apply -------------------------------------------------------------------

# Recheck every observed destination, including kept files and the receipt,
# before starting. Staging freezes source bytes; this does not lock the target.
for ((i = 0; i < ${#watch_rel[@]}; i++)); do
  check_path_safety "${watch_rel[$i]}"
  [ "$(current_hash "${watch_rel[$i]}")" = "${watch_hash[$i]}" ] ||
    die "target changed during planning: ${watch_rel[$i]}; retry (nothing written)"
done
if [ "$local_mode" -eq 1 ]; then
  check_exclude_file
  [ "$(hash_or_absent "$exclude_file")" = "$exclude_hash" ] ||
    die "target changed during planning: $exclude_file; retry (nothing written)"
fi
mkdir "$work/backups"
for ((i = 0; i < ${#write_rel[@]}; i++)); do
  if [ -f "$target/${write_rel[$i]}" ]; then
    cp -p "$target/${write_rel[$i]}" "$work/backups/$i"
  fi
done
if [ -s "$work/exclude-add" ] && [ -f "$exclude_file" ]; then
  cp -p "$exclude_file" "$work/exclude-backup"
fi

ensure_parent() {
  local rest="$1" acc="" seg
  while [[ "$rest" == */* ]]; do
    seg="${rest%%/*}"; rest="${rest#*/}"
    if [ -z "$acc" ]; then acc="$seg"; else acc="$acc/$seg"; fi
    if [ ! -d "$target/$acc" ]; then
      mkdir "$target/$acc"
      created_dirs+=("$acc")
    fi
  done
}

applying=1
# Exclusions first, then Git's own answer, then files: a Kit file must never
# exist here while Git would still offer to commit it.
if [ "$local_mode" -eq 1 ]; then
  if [ -s "$work/exclude-add" ]; then
    if [ ! -d "$exclude_dir" ]; then
      mkdir "$exclude_dir"
      exclude_dir_created=1
    fi
    exclude_touched=1
    cat "$work/exclude-add" >>"$exclude_file"
  fi
  while IFS= read -r rel; do
    git_ignores "$rel" || die "Git does not ignore $rel after adding its exclusion"
  done <"$work/local-paths"
fi
for ((i = 0; i < ${#write_rel[@]}; i++)); do
  rel="${write_rel[$i]}"
  ensure_parent "$rel"
  # Never allow cp's directory-target behavior, even if a leaf changes type
  # after preflight. Concurrent writers are still unsupported.
  if [ -L "$target/$rel" ] || { [ -e "$target/$rel" ] && [ ! -f "$target/$rel" ]; }; then
    die "destination changed type during apply: $rel"
  fi
  written+=("$i") # Include a partially failed copy in rollback.
  if [ -f "$target/$rel" ]; then
    cp "${write_src[$i]}" "$target/$rel" # Preserve the destination mode.
  else
    cp -p "${write_src[$i]}" "$target/$rel"
  fi
done
success=1
printf '  written: %d file(s), including any receipt update\n' "${#write_rel[@]}"
if [ "$local_mode" -eq 1 ]; then
  printf '  new Git exclusions: %d in %s\n' "$new_exclusions" "$exclude_file"
fi
printf '  identical: %d; kept local: %d; retired: %d\n' "$identical" "$kept" "$retired"
if [ "${#write_rel[@]}" -eq 0 ] && [ "$new_exclusions" -eq 0 ]; then
  printf '  nothing to do — this target is already up to date.\n'
fi
