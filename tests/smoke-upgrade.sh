#!/usr/bin/env bash
# Real filesystem upgrades from genuine historical installs. Each fixture is
# seeded by its own release's installer (an exported v0.1.0, v0.2.0 or v0.3.0
# tree), so its receipt, payload and exclusions are exactly what that release
# wrote: 0.1.0 legacy receipts, 0.2.0 hash receipts, 0.3.0 local receipts.
# The incoming Kit is this tree (one skill per workflow, no .claude/commands),
# in a clone that carries the release tags, plus synthetic upstream changes
# that deliberately differ from every tag.
set -euo pipefail
cd "$(dirname "$0")/.."
KIT="$PWD"
tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
bad() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
if stat --version >/dev/null 2>&1; then stat_format='-c%i'; else stat_format='-f%i'; fi
inode_of() { stat "$stat_format" "$1"; }
if command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum "$1" | awk '{print $1}'; }
else
  sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
fi

snapshot() {
  (
    cd "$1"
    find . -mindepth 1 -not -path './.git' -not -path './.git/*' | sort |
      while IFS= read -r path; do
        if [ -L "$path" ]; then printf 'link %s %s\n' "$path" "$(readlink "$path")"
        elif [ -d "$path" ]; then printf 'dir %s\n' "$path"
        else printf 'file %s %s\n' "$path" "$(cksum <"$path")"; fi
      done
  )
}
new_repo() {
  mkdir "$1"
  git -C "$1" init -q
  mkdir "$1/memory-bank"
  printf 'project memory\n' >"$1/memory-bank/activeContext.md"
  printf '{}\n' >"$1/.serel-memory.json"
  printf 'project rules\n' >"$1/.rules"
  printf 'project instructions\n' >"$1/AGENTS.md"
  printf 'custom compatibility instructions\n' >"$1/CLAUDE.md"
}
guarded() {
  (cd "$1" && cksum .rules .serel-memory.json AGENTS.md CLAUDE.md memory-bank/activeContext.md)
}
# install_old <tag> <target> <installer args...>: a fresh project installed by
# that release's own installer.
install_old() {
  local tag="$1" target="$2"
  shift 2
  new_repo "$target"
  bash "$tmp/kit-$tag/install.sh" "$target" "$@" >"$tmp/install.log" 2>&1 ||
    { cat "$tmp/install.log"; bad "Kit $tag installation: $*"; }
}
expect_refused() {
  local target="$1" before
  shift
  before="$(snapshot "$target")"
  if bash "$incoming/install.sh" "$target" "$@" >"$tmp/refused.log" 2>&1; then
    cat "$tmp/refused.log"
    bad "expected refusal: $*"
  fi
  [ "$(snapshot "$target")" = "$before" ] || bad "refused operation changed target: $*"
}
# upgrade_apply <target> [packs]
upgrade_apply() {
  bash "$incoming/install.sh" "$1" --packs "${2:-writing}" --upgrade --apply >"$tmp/apply.log" 2>&1 ||
    { cat "$tmp/apply.log"; bad "upgrade application: ${2:-writing} in $1"; }
}

for tag in v0.1.0 v0.2.0 v0.3.0; do
  git -C "$KIT" rev-parse --verify -q "refs/tags/$tag^{commit}" >/dev/null ||
    bad "fixture tag $tag is missing: run git fetch --tags"
  mkdir "$tmp/kit-$tag"
  git -C "$KIT" archive "$tag" | tar -x -C "$tmp/kit-$tag"
done
# Legacy receipts resolve their baseline from the exact release tag, so the
# incoming Kit is a git checkout with the tags; its files are this tree's.
incoming="$tmp/incoming"
git clone --quiet --no-hardlinks "$KIT" "$incoming"
git -C "$incoming" checkout --quiet --detach "$(git -C "$KIT" rev-parse HEAD)"
rm -rf "$incoming/packs"
cp -R "$KIT/packs" "$incoming/packs"
cp "$KIT/install.sh" "$incoming/install.sh"
incoming_version="$(sed -n 's/^KIT_VERSION="\(.*\)"$/\1/p' "$incoming/install.sh")"
[ -n "$incoming_version" ] || bad "could not read KIT_VERSION from install.sh"
[ ! -e "$incoming/packs/writing/.claude/commands" ] || bad "the incoming Kit still ships commands"

command_path=".claude/commands/polish.md"
copy_path=".claude/skills/polish/SKILL.md"
skill_path=".agents/skills/polish/SKILL.md"
rules_path=".agents/skills/polish/RULES.md"
retired_path=".agents/skills/polish/agents/openai.yaml"
added_path=".agents/skills/polish/EXTRA.md"
verify_command=".claude/commands/verify-map.md"
W="$incoming/packs/writing"
printf '\nSynthetic upstream skill change.\n' >>"$W/$skill_path"
cp "$W/$skill_path" "$W/$copy_path"
printf 'Synthetic added resource.\n' >"$W/$added_path"
rm "$W/$retired_path"
# Every release shipped these rules bytes, so a local edit is KEEP LOCAL.
git -C "$KIT" show "v0.1.0:packs/writing/$rules_path" >"$W/$rules_path"

echo "case 1: a 0.2.0 hash receipt: preview, safe updates, removal, local customization, retirement, convergence"
project="$tmp/project"
install_old v0.2.0 "$project" --packs writing,verify
jq -e --arg c "$command_path" '.installed.writing.files[$c] | length == 64' "$project/.serel-kit.json" >/dev/null ||
  bad "the 0.2.0 fixture is not a hash receipt naming the command"
jq '.owner = "keep" | .installed.writing.note = "keep nested"' "$project/.serel-kit.json" >"$tmp/receipt"
mv "$tmp/receipt" "$project/.serel-kit.json"
verify_before="$(jq -c '.installed.verify' "$project/.serel-kit.json")"
guard_before="$(guarded "$project")"
printf '\nLocal house rule.\n' >>"$project/$rules_path"
rules_before="$(cksum <"$project/$rules_path")"
chmod 755 "$project/$skill_path"
before="$(snapshot "$project")"
bash "$incoming/install.sh" "$project" --packs writing --upgrade >"$tmp/preview.log" 2>&1 ||
  { cat "$tmp/preview.log"; bad "preview failed"; }
[ "$(snapshot "$project")" = "$before" ] || bad "preview wrote files"
for action in UPDATE ADD 'KEEP LOCAL' "REMOVE     $command_path" "RETIRED    $retired_path (left as-is"; do
  grep -qF "$action" "$tmp/preview.log" || bad "preview missed $action"
done
grep -q '^@@' "$tmp/preview.log" || bad "preview omitted diffs"
grep -q '1 removal(s)' "$tmp/preview.log" || bad "preview did not count the removal"
upgrade_apply "$project"
[ ! -e "$project/$command_path" ] || bad "unmodified retired command not removed"
cmp -s "$project/$skill_path" "$W/$skill_path" || bad "skill not updated"
cmp -s "$project/$copy_path" "$W/$copy_path" || bad "Claude copy not added"
[ -x "$project/$skill_path" ] || bad "existing mode changed"
cmp -s "$project/$added_path" "$W/$added_path" || bad "new resource not added"
[ "$(cksum <"$project/$rules_path")" = "$rules_before" ] || bad "local rules overwritten"
[ -f "$project/$retired_path" ] || bad "retired file deleted"
[ -f "$project/$verify_command" ] || bad "a pack that was not upgraded lost its command"
[ "$(guarded "$project")" = "$guard_before" ] || bad "Memory boundary violated"
[ "$(jq -c '.installed.verify' "$project/.serel-kit.json")" = "$verify_before" ] || bad "unselected pack changed"
jq -e --arg retired "$retired_path" --arg rules "$rules_path" --arg c "$command_path" \
  --arg copy "$copy_path" --arg copy_hash "$(sha256 "$W/$copy_path")" --arg v "$incoming_version" '
  .kit == $v and .owner == "keep" and .installed.writing.note == "keep nested"
  and .installed.writing.version == $v
  and (.installed.writing.files | has($retired) | not)
  and (.installed.writing.files | has($c) | not)
  and .installed.writing.files[$copy] == $copy_hash
  and (.installed.writing.files[$rules] | length == 64)
' "$project/.serel-kit.json" >/dev/null || bad "receipt metadata or manifest wrong"
base_rules_hash="$(jq -r --arg path "$rules_path" '.installed.writing.files[$path]' "$project/.serel-kit.json")"
[ "$base_rules_hash" = "$(sha256 "$W/$rules_path")" ] || bad "receipt adopted customized local bytes as baseline"
before="$(snapshot "$project")"
inode_before="$(inode_of "$project/.serel-kit.json")"
upgrade_apply "$project"
[ "$(snapshot "$project")" = "$before" ] || bad "repeat upgrade changed files"
[ "$(inode_of "$project/.serel-kit.json")" = "$inode_before" ] || bad "repeat rewrote receipt"
upgrade_apply "$project" verify
[ ! -e "$project/$verify_command" ] || bad "the verify upgrade did not remove its own command"

echo "case 2: both-changed, local deletion, unowned additions, absent files, and whole-selection refusal"
conflict="$tmp/conflict"
install_old v0.2.0 "$conflict" --packs writing,verify
printf '\nLocal skill change.\n' >>"$conflict/$skill_path"
expect_refused "$conflict" --packs writing,verify --upgrade --apply
grep -q CONFLICT "$tmp/refused.log" || bad "both-changed not reported"
[ -f "$conflict/$verify_command" ] || bad "a refused selection removed a command"
cp "$W/$skill_path" "$conflict/$skill_path"
upgrade_apply "$conflict" writing,verify
[ ! -e "$conflict/$command_path" ] && [ ! -e "$conflict/$verify_command" ] || bad "commands not removed"
deleted="$tmp/deleted"
install_old v0.2.0 "$deleted" --packs writing
rm "$deleted/$rules_path"
expect_refused "$deleted" --packs writing --upgrade --apply
unowned="$tmp/unowned"
install_old v0.2.0 "$unowned" --packs writing
printf 'User-owned resource\n' >"$unowned/$added_path"
expect_refused "$unowned" --packs writing --upgrade --apply
retired_absent="$tmp/retired-absent"
install_old v0.2.0 "$retired_absent" --packs writing
rm "$retired_absent/$retired_path"
upgrade_apply "$retired_absent"
[ ! -e "$retired_absent/$retired_path" ] || bad "retired absent file resurrected"
# An already-absent retired command stays absent, and that is not an error.
command_absent="$tmp/command-absent"
install_old v0.2.0 "$command_absent" --packs writing
rm "$command_absent/$command_path"
upgrade_apply "$command_absent"
grep -qF "ABSENT     $command_path" "$tmp/apply.log" || bad "already-absent command not reported"
[ ! -e "$command_absent/$command_path" ] || bad "absent retired command resurrected"
cmp -s "$command_absent/$copy_path" "$W/$copy_path" || bad "Claude copy not added beside an absent command"
printf '\nNew upstream rule.\n' >>"$W/$rules_path"
expect_refused "$project" --packs writing --upgrade --apply
git -C "$KIT" show "v0.1.0:packs/writing/$rules_path" >"$W/$rules_path"

echo "case 3: genuine 0.1.0 legacy receipts: exact tag baseline, removal, and a modified command stopping"
legacy="$tmp/legacy"
install_old v0.1.0 "$legacy" --packs writing,verify
jq -e '.kit == "0.1.0" and (has("installed") | not)' "$legacy/.serel-kit.json" >/dev/null ||
  bad "the 0.1.0 fixture is not a legacy receipt"
jq '.owner = "legacy"' "$legacy/.serel-kit.json" >"$tmp/receipt"
mv "$tmp/receipt" "$legacy/.serel-kit.json"
printf '\nLegacy local rule.\n' >>"$legacy/$rules_path"
bash "$incoming/install.sh" "$legacy" --packs writing --upgrade >"$tmp/legacy-preview.log" 2>&1 ||
  { cat "$tmp/legacy-preview.log"; bad "legacy preview failed"; }
grep -qF "REMOVE     $command_path" "$tmp/legacy-preview.log" || bad "legacy baseline did not offer the removal"
upgrade_apply "$legacy"
[ ! -e "$legacy/$command_path" ] || bad "legacy command not removed"
[ -f "$legacy/$verify_command" ] || bad "legacy unselected pack lost its command"
jq -e --arg v "$incoming_version" '.installed.writing.version == $v and .installed.verify.version == "0.1.0"
  and .installed.verify.files == null and .owner == "legacy"' "$legacy/.serel-kit.json" >/dev/null ||
  bad "legacy unselected pack lost its actual baseline version"
upgrade_apply "$legacy" verify
[ ! -e "$legacy/$verify_command" ] || bad "second legacy pack did not resolve its original tag"
missing_tag="$tmp/missing-tag"
install_old v0.1.0 "$missing_tag" --packs writing
jq '.kit = "9.9.9"' "$missing_tag/.serel-kit.json" >"$tmp/receipt"
mv "$tmp/receipt" "$missing_tag/.serel-kit.json"
expect_refused "$missing_tag" --packs writing --upgrade --apply
grep -q 'baseline tag v9.9.9' "$tmp/refused.log" || bad "missing tag not explained"
# A customized command from a genuine 0.1.0 install: the skill would shadow
# it, so the upgrade stops, in preview as well as apply.
legacy_mod="$tmp/legacy-modified"
install_old v0.1.0 "$legacy_mod" --packs writing
printf '\nMy legacy command rule.\n' >>"$legacy_mod/$command_path"
expect_refused "$legacy_mod" --packs writing --upgrade
expect_refused "$legacy_mod" --packs writing --upgrade --apply
for line in "MODIFIED   $command_path" STOPPED "MODIFIED: 1 retired command(s); nothing was written" \
  "show v0.1.0:packs/writing/$command_path"; do
  grep -qF -- "$line" "$tmp/refused.log" || { cat "$tmp/refused.log"; bad "legacy stop message lacks: $line"; }
done
# The documented recovery, run as printed: save, restore, upgrade, reapply.
mkdir "$tmp/saved-legacy"
cp "$legacy_mod/$command_path" "$tmp/saved-legacy/polish.md"
grep -E '^       (git -C|cp) ' "$tmp/refused.log" >"$tmp/restore.sh"
bash "$tmp/restore.sh" || bad "the printed restore commands failed"
cmp -s "$legacy_mod/$command_path" <(git -C "$KIT" show "v0.1.0:packs/writing/$command_path") ||
  bad "restore did not put back the 0.1.0 command"
upgrade_apply "$legacy_mod"
[ ! -e "$legacy_mod/$command_path" ] || bad "recovered legacy command not removed"
printf '\nMy legacy command rule.\n' | tee -a "$legacy_mod/$copy_path" >>"$legacy_mod/$skill_path"
before="$(snapshot "$legacy_mod")"
upgrade_apply "$legacy_mod"
grep -q 'nothing to do' "$tmp/apply.log" || bad "re-upgrade after reapplying did not converge"
[ "$(snapshot "$legacy_mod")" = "$before" ] || bad "re-upgrade overwrote reapplied customizations"

echo "case 4: 0.3.0 receipts: a shared pr install and a local writing install"
pr3="$tmp/pr-v0.3.0"
install_old v0.3.0 "$pr3" --packs pr
upgrade_apply "$pr3" pr
for n in file-pr babysit-pr modernize-pr pr-comment; do
  [ ! -e "$pr3/.claude/commands/$n.md" ] || bad "pr command $n not removed"
  cmp -s "$pr3/.claude/skills/$n/SKILL.md" "$incoming/packs/pr/.claude/skills/$n/SKILL.md" ||
    bad "pr Claude copy $n not installed"
done
[ "$(grep -c '^  REMOVE ' "$tmp/apply.log")" = 4 ] || bad "pr upgrade did not remove exactly four commands"
local3="$tmp/local-v0.3.0"
install_old v0.3.0 "$local3" --packs writing --local --apply
jq -e '.local == true' "$local3/.serel-kit.json" >/dev/null || bad "the 0.3.0 fixture is not a local receipt"
exclude="$local3/.git/info/exclude"
before="$(snapshot "$local3")"
exclude_before="$(cat "$exclude")"
bash "$incoming/install.sh" "$local3" --packs writing --upgrade >"$tmp/local-preview.log" 2>&1 ||
  { cat "$tmp/local-preview.log"; bad "local upgrade preview failed"; }
[ "$(snapshot "$local3")" = "$before" ] && [ "$(cat "$exclude")" = "$exclude_before" ] ||
  bad "local upgrade preview wrote something"
grep -qF "REMOVE     $command_path" "$tmp/local-preview.log" || bad "local preview omitted the removal"
upgrade_apply "$local3"
[ ! -e "$local3/$command_path" ] || bad "local retired command not removed"
grep -qxF "/$command_path" "$exclude" || bad "local upgrade dropped the retired command's exclusion"
for path in "$copy_path" "$skill_path" .serel-kit.json; do
  git -C "$local3" check-ignore -q -- "$path" || bad "local upgrade left $path visible"
done

echo "case 5: ownership: Memory paths, another pack's command and unknown bytes are preserved"
own="$tmp/ownership"
install_old v0.3.0 "$own" --packs writing,verify
mkdir -p "$own/.agents/skills/start"
printf 'Serel Memory start command\n' >"$own/.claude/commands/start.md"
printf 'Serel Memory start skill\n' >"$own/.agents/skills/start/SKILL.md"
# A hand-edited writing receipt that claims Serel Memory's start workflow and
# verify's command, each with its real hash.
jq --arg s "$(sha256 "$own/.claude/commands/start.md")" --arg k "$(sha256 "$own/.agents/skills/start/SKILL.md")" \
  --arg v "$(sha256 "$own/$verify_command")" --arg vc "$verify_command" '
  .installed.writing.files[".claude/commands/start.md"] = $s
  | .installed.writing.files[".agents/skills/start/SKILL.md"] = $k
  | .installed.writing.files[$vc] = $v' "$own/.serel-kit.json" >"$tmp/receipt"
mv "$tmp/receipt" "$own/.serel-kit.json"
memory_before="$(cd "$own" && cksum .claude/commands/start.md .agents/skills/start/SKILL.md)"
# verify's own command, while writing's receipt still lists it: preserved.
upgrade_apply "$own" verify
grep -qF "RETIRED    $verify_command (left as-is; another installed pack records it)" "$tmp/apply.log" ||
  bad "a command another pack records was not preserved"
[ -f "$own/$verify_command" ] || bad "removed a command another pack records"
upgrade_apply "$own"
for path in .claude/commands/start.md .agents/skills/start/SKILL.md "$verify_command"; do
  grep -qF "RETIRED    $path (left as-is" "$tmp/apply.log" || bad "receipt path $path not left as-is"
done
[ ! -e "$own/$command_path" ] || bad "writing's own command not removed beside preserved paths"
[ "$(cd "$own" && cksum .claude/commands/start.md .agents/skills/start/SKILL.md)" = "$memory_before" ] ||
  bad "a Serel Memory path named by a receipt changed"
[ -f "$own/$verify_command" ] || bad "another pack's command removed through a foreign receipt"
# Recorded bytes that no release shipped prove nothing about ownership.
unknown="$tmp/unknown-bytes"
install_old v0.3.0 "$unknown" --packs writing
printf '\nNot from any release.\n' >>"$unknown/$command_path"
jq --arg c "$command_path" --arg h "$(sha256 "$unknown/$command_path")" '.installed.writing.files[$c] = $h' \
  "$unknown/.serel-kit.json" >"$tmp/receipt"
mv "$tmp/receipt" "$unknown/.serel-kit.json"
upgrade_apply "$unknown"
grep -qF "RETIRED    $command_path (left as-is; its recorded bytes match no Kit release)" "$tmp/apply.log" ||
  bad "unknown recorded bytes not preserved"
[ -f "$unknown/$command_path" ] || bad "removed a command whose bytes no release shipped"

echo "case 6: malformed receipts, traversal, destination/source links and bad options"
unsafe="$tmp/unsafe"
install_old v0.2.0 "$unsafe" --packs writing,verify
cp "$unsafe/.serel-kit.json" "$tmp/good-receipt"
jq '.installed.writing.files[".agents/skills/../../memory-bank/activeContext.md"] =
  ("a" * 64)' "$tmp/good-receipt" >"$unsafe/.serel-kit.json"
expect_refused "$unsafe" --packs writing --upgrade --apply
jq '.installed.writing.files = {"bad": "not-a-hash"}' "$tmp/good-receipt" >"$unsafe/.serel-kit.json"
expect_refused "$unsafe" --packs writing --upgrade --apply
jq '.installed.writing.files[".claude/commands/a.md\n.claude/commands/b.md"] =
  ("a" * 64)' "$tmp/good-receipt" >"$unsafe/.serel-kit.json"
expect_refused "$unsafe" --packs writing --upgrade --apply
jq '.installed.writing.files[".claude/skills/polish/extra.md"] = ("a" * 64)' "$tmp/good-receipt" >"$unsafe/.serel-kit.json"
expect_refused "$unsafe" --packs writing --upgrade --apply
cp "$tmp/good-receipt" "$unsafe/.serel-kit.json"
rm "$unsafe/.serel-kit.json"
ln -s "$tmp/good-receipt" "$unsafe/.serel-kit.json"
expect_refused "$unsafe" --packs writing --upgrade --apply
rm "$unsafe/.serel-kit.json"
cp "$tmp/good-receipt" "$unsafe/.serel-kit.json"
mv "$unsafe/.agents/skills" "$tmp/moved-skills"
ln -s "$tmp/moved-skills" "$unsafe/.agents/skills"
expect_refused "$unsafe" --packs writing --upgrade --apply
rm "$unsafe/.agents/skills"
mv "$tmp/moved-skills" "$unsafe/.agents/skills"
ln -s "$tmp/good-receipt" "$W/.agents/skills/polish/LINK"
expect_refused "$unsafe" --packs writing --upgrade --apply
rm "$W/.agents/skills/polish/LINK"
mkdir -p "$W/.claude/commands"
printf 'a pack that still ships a command\n' >"$W/.claude/commands/polish.md"
expect_refused "$unsafe" --packs writing --upgrade --apply
grep -q 'never commands' "$tmp/refused.log" || bad "a pack shipping commands not refused"
rm -r "$W/.claude/commands"
ln "$unsafe/$skill_path" "$unsafe/memory-bank/linked-skill.md"
expect_refused "$unsafe" --packs writing --upgrade --apply
rm "$unsafe/memory-bank/linked-skill.md"
# A retired command gets the same path checks as an incoming file.
ln "$unsafe/$command_path" "$unsafe/memory-bank/linked-command.md"
expect_refused "$unsafe" --packs writing --upgrade --apply
grep -qF "UNSAFE PATH: $command_path has multiple hard links" "$tmp/refused.log" || bad "hard-linked command not refused"
rm "$unsafe/memory-bank/linked-command.md"
mv "$unsafe/$command_path" "$tmp/moved-command"
ln -s "$tmp/moved-command" "$unsafe/$command_path"
expect_refused "$unsafe" --packs writing --upgrade --apply
grep -qF "UNSAFE PATH: $command_path is a symlink" "$tmp/refused.log" || bad "symlinked command not refused"
rm "$unsafe/$command_path"
mv "$tmp/moved-command" "$unsafe/$command_path"
mv "$unsafe/.claude/commands" "$tmp/moved-commands"
ln -s "$tmp/moved-commands" "$unsafe/.claude/commands"
expect_refused "$unsafe" --packs writing --upgrade --apply
grep -qF "UNSAFE PATH: .claude/commands is a symlink" "$tmp/refused.log" || bad "symlinked commands folder not refused"
rm "$unsafe/.claude/commands"
mv "$tmp/moved-commands" "$unsafe/.claude/commands"
expect_refused "$unsafe" --packs writing --apply
uninstalled="$tmp/uninstalled"
new_repo "$uninstalled"
expect_refused "$uninstalled" --packs writing --upgrade --apply
# A case variant of the retired command's folder.
variant="$tmp/variant"
install_old v0.2.0 "$variant" --packs writing
mv "$variant/.claude/commands" "$variant/.claude/Commands"
: >"$tmp/case-probe"
if [ -e "$tmp/CASE-PROBE" ]; then
  expect_refused "$variant" --packs writing --upgrade --apply
  grep -qF '.claude/commands exists with different letter case' "$tmp/refused.log" || bad "case variant not refused"
else
  echo "  case-sensitive filesystem: .claude/Commands is the project's own folder and stays as it was"
  upgrade_apply "$variant"
  grep -qF "ABSENT     $command_path" "$tmp/apply.log" || bad "case variant not treated as absent"
  cmp -s "$variant/.claude/Commands/polish.md" <(git -C "$KIT" show "v0.2.0:packs/writing/$command_path") ||
    bad "a case-variant file changed"
fi

echo "case 7: failures after a removal and during the receipt write roll everything back"
mkdir "$W/.agents/skills/polish/AAA"
printf 'new nested resource\n' >"$W/.agents/skills/polish/AAA/new.md"
mkdir "$tmp/shim"
real_cp="$(command -v cp)"
cat >"$tmp/shim/cp" <<'SHIM'
#!/usr/bin/env bash
dest="${@: -1}"
if [ "$dest" = "$FAIL_DEST" ] && [ ! -e "$FAIL_ONCE" ]; then
  touch "$FAIL_ONCE"
  # Record that the retired command was already gone when this write failed.
  if [ -n "${GONE:-}" ] && [ ! -e "$GONE" ]; then touch "$FAIL_ONCE.after-removal"; fi
  printf 'partial copy\n' >"$dest"
  exit 1
fi
exec "$REAL_CP" "$@"
SHIM
chmod +x "$tmp/shim/cp"
# fail_copy <target> <dest> <flag>: the copy to dest fails once, after the
# command was removed; every change must be undone.
fail_copy() {
  local target="$1" dest="$2" flag="$3" before recovery
  before="$(snapshot "$target")"
  if PATH="$tmp/shim:$PATH" REAL_CP="$real_cp" FAIL_DEST="$target/$dest" FAIL_ONCE="$flag" \
    GONE="$target/$command_path" \
    bash "$incoming/install.sh" "$target" --packs writing --upgrade --apply >"$tmp/fail.log" 2>&1; then
    bad "injected failure at $dest succeeded"
  fi
  [ -f "$flag" ] || bad "failure at $dest not exercised"
  [ -f "$flag.after-removal" ] || bad "failure at $dest did not come after the removal"
  [ "$(snapshot "$target")" = "$before" ] || { cat "$tmp/fail.log"; bad "failure at $dest left mutations"; }
  [ -f "$target/$command_path" ] || bad "rollback did not restore the removed command"
  recovery="$(sed -n 's/^Recovery files retained at //p' "$tmp/fail.log")"
  [ -f "$recovery/backups/removed-0" ] || bad "failure at $dest kept no backup of the removed command"
  rm -rf "$recovery"
}
rollback="$tmp/rollback"
install_old v0.2.0 "$rollback" --packs writing
fail_copy "$rollback" "$copy_path" "$tmp/failed-copy"
# The receipt is the last write; failing there must restore the entire payload.
receipt_failure="$tmp/receipt-failure"
install_old v0.2.0 "$receipt_failure" --packs writing
fail_copy "$receipt_failure" .serel-kit.json "$tmp/failed-receipt"
# The removal itself fails.
mkdir "$tmp/rm-shim"
cat >"$tmp/rm-shim/rm" <<'SHIM'
#!/usr/bin/env bash
case "${@: -1}" in "$FAIL_DEST") touch "$FAIL_ONCE"; exit 1 ;; esac
exec "$REAL_RM" "$@"
SHIM
chmod +x "$tmp/rm-shim/rm"
rm_failure="$tmp/rm-failure"
install_old v0.2.0 "$rm_failure" --packs writing
before="$(snapshot "$rm_failure")"
real_rm="$(command -v rm)" # resolved before PATH reaches the shim
if PATH="$tmp/rm-shim:$PATH" REAL_RM="$real_rm" FAIL_DEST="$rm_failure/$command_path" \
  FAIL_ONCE="$tmp/failed-rm" bash "$incoming/install.sh" "$rm_failure" --packs writing --upgrade --apply \
  >"$tmp/rm-fail.log" 2>&1; then
  bad "injected removal failure succeeded"
fi
[ -f "$tmp/failed-rm" ] || bad "removal failure not exercised"
[ "$(snapshot "$rm_failure")" = "$before" ] || { cat "$tmp/rm-fail.log"; bad "removal failure left mutations"; }
rm -rf "$(sed -n 's/^Recovery files retained at //p' "$tmp/rm-fail.log")"
# The command changes after the plan hashed it: once after the plan, which
# the recheck before applying catches with nothing written, and once while
# the backups are taken, which the recheck right before the removal catches
# and rolls back. The shim edits the command on the first call that matches.
mkdir "$tmp/race-shim"
cat >"$tmp/race-shim/race" <<'SHIM'
#!/usr/bin/env bash
tool="$(basename "$0")"
case "${*: -1}" in *"$WHEN_SUFFIX") hit=1 ;; *) hit=0 ;; esac
if [ ! -e "$FAIL_ONCE" ] && [ "$hit" -eq 1 ]; then
  touch "$FAIL_ONCE"
  printf 'edited meanwhile\n' >>"$CHANGE"
fi
case "$tool" in cmp) exec "$REAL_CMP" "$@" ;; cp) exec "$REAL_CP" "$@" ;; esac
exit 127
SHIM
chmod +x "$tmp/race-shim/race"
mkdir "$tmp/cmp-shim" "$tmp/cp-race-shim"
ln -s "$tmp/race-shim/race" "$tmp/cmp-shim/cmp"
ln -s "$tmp/race-shim/race" "$tmp/cp-race-shim/cp"
real_cmp="$(command -v cmp)" # resolved before PATH reaches the shim
# race <shim dir> <destination suffix or empty> <expected message>
race() {
  local dir="$1" when="$2" message="$3" raced before
  raced="$tmp/raced-$(basename "$1")"
  install_old v0.2.0 "$raced" --packs writing
  cp "$raced/$command_path" "$tmp/raced-command"
  before="$(snapshot "$raced")"
  if PATH="$dir:$PATH" REAL_CMP="$real_cmp" REAL_CP="$real_cp" CHANGE="$raced/$command_path" \
    WHEN_SUFFIX="$when" FAIL_ONCE="$raced.once" \
    bash "$incoming/install.sh" "$raced" --packs writing --upgrade --apply >"$tmp/raced.log" 2>&1; then
    bad "a command changed after planning was removed"
  fi
  [ -e "$raced.once" ] || bad "race not exercised: $message"
  grep -qF "$message" "$tmp/raced.log" || { cat "$tmp/raced.log"; bad "recheck not reported: $message"; }
  [ -f "$raced/$command_path" ] || bad "a command that changed was removed"
  cp "$tmp/raced-command" "$raced/$command_path" # undo the shim's own edit
  [ "$(snapshot "$raced")" = "$before" ] || bad "a stopped recheck left changes: $message"
  rm -rf "$(sed -n 's/^Recovery files retained at //p' "$tmp/raced.log")"
}
# The receipt comparison is the plan's last step before the recheck.
race "$tmp/cmp-shim" "" "target changed during planning: $command_path"
# The command's backup is the last copy before the removal.
race "$tmp/cp-race-shim" /backups/removed-0 "target changed during apply: $command_path"
rm -rf "$W/.agents/skills/polish/AAA"

echo "case 8: complete-payload prefix collisions are refused in either pack order"
mkdir -p "$W/.agents/skills/collision/RESOURCE.md"
printf 'child\n' >"$W/.agents/skills/collision/RESOURCE.md/child.md"
mkdir -p "$incoming/packs/verify/.agents/skills/collision"
printf 'parent\n' >"$incoming/packs/verify/.agents/skills/collision/RESOURCE.md"
for order in writing,verify verify,writing; do
  collision="$tmp/collision-$order"
  new_repo "$collision"
  expect_refused "$collision" --packs "$order"
done
rm -rf "$W/.agents/skills/collision"
rm -rf "$incoming/packs/verify/.agents/skills/collision"
# An unselected pack's deleted file still owns the path and its ancestors.
owned="$tmp/owned"
install_old v0.2.0 "$owned" --packs writing,verify
jq '.installed.verify.files[".agents/skills/polish/EXTRA.md/child.md"] =
  ("a" * 64)' "$owned/.serel-kit.json" >"$tmp/receipt"
mv "$tmp/receipt" "$owned/.serel-kit.json"
expect_refused "$owned" --packs writing --upgrade --apply

echo "case 9: the documented recovery when both old adapters were customized"
rec="$tmp/recovery"
install_old v0.3.0 "$rec" --packs writing
printf '\nMy command rule.\n' >>"$rec/$command_path"
printf '\nMy skill rule.\n' >>"$rec/$skill_path"
expect_refused "$rec" --packs writing --upgrade --apply
for line in "MODIFIED   $command_path" "CONFLICT   $skill_path" "and 1 other conflict(s)" \
  "show v0.3.0:packs/writing/$command_path" "If an upgrade stops on a customized"; do
  grep -qF -- "$line" "$tmp/refused.log" || { cat "$tmp/refused.log"; bad "stop message lacks: $line"; }
done
# 1. Copy the customized files outside the discovery folders.
mkdir "$tmp/saved"
cp "$rec/$command_path" "$tmp/saved/command.md"
cp "$rec/$skill_path" "$tmp/saved/skill.md"
# 2. Reconcile, with the commands exactly as printed: the command back to its
# verified baseline bytes, the Codex skill to the incoming bytes, in place.
grep -E '^       (git -C|cp) ' "$tmp/refused.log" >"$tmp/restore.sh"
[ "$(wc -l <"$tmp/restore.sh" | tr -d ' ')" = 2 ] || bad "the stop message did not print both restore commands"
bash "$tmp/restore.sh" || bad "the printed restore commands failed"
[ "$(sha256 "$rec/$command_path")" = "$(jq -r --arg c "$command_path" '.installed.writing.files[$c]' "$rec/.serel-kit.json")" ] ||
  bad "restore did not match the receipt's baseline"
cmp -s "$rec/$skill_path" "$W/$skill_path" || bad "restore did not put back the incoming skill"
# 3. The upgrade removes the command and installs both new copies.
upgrade_apply "$rec"
[ ! -e "$rec/$command_path" ] || bad "recovery upgrade kept the command"
cmp -s "$rec/$copy_path" "$W/$copy_path" || bad "recovery upgrade did not install the Claude copy"
cmp -s "$rec/$skill_path" "$W/$skill_path" || bad "recovery upgrade did not install the Codex skill"
jq -e --arg copy "$copy_path" --arg skill "$skill_path" --arg ch "$(sha256 "$W/$copy_path")" \
  --arg sh "$(sha256 "$W/$skill_path")" '.installed.writing.files[$copy] == $ch
  and .installed.writing.files[$skill] == $sh' "$rec/.serel-kit.json" >/dev/null ||
  bad "the receipt does not record the incoming hashes"
# 4. Reapply the approved customizations to both copies; later upgrades keep them.
printf '\nMy command rule.\n\nMy skill rule.\n' | tee -a "$rec/$copy_path" >>"$rec/$skill_path"
before="$(snapshot "$rec")"
upgrade_apply "$rec"
for path in "$copy_path" "$skill_path"; do
  grep -qF "KEEP LOCAL $path" "$tmp/apply.log" || bad "reapplied customization not kept: $path"
done
[ "$(snapshot "$rec")" = "$before" ] || bad "a later upgrade overwrote the reapplied customizations"
# Only the Codex skill customized: an ordinary conflict, same reconcile.
rec_skill="$tmp/recovery-skill"
install_old v0.3.0 "$rec_skill" --packs writing
printf '\nMy skill rule.\n' >>"$rec_skill/$skill_path"
expect_refused "$rec_skill" --packs writing --upgrade --apply
grep -qF "CONFLICT   $skill_path" "$tmp/refused.log" || bad "a Codex-only customization was not a conflict"
if grep -q MODIFIED "$tmp/refused.log"; then bad "a Codex-only customization stopped as a modified command"; fi
cp "$rec_skill/$skill_path" "$tmp/saved/skill-only.md"
cp "$W/$skill_path" "$rec_skill/$skill_path"
upgrade_apply "$rec_skill"
[ ! -e "$rec_skill/$command_path" ] || bad "Codex-only recovery kept the command"
printf '\nMy skill rule.\n' | tee -a "$rec_skill/$copy_path" >>"$rec_skill/$skill_path"
upgrade_apply "$rec_skill"
grep -q 'nothing to do' "$tmp/apply.log" || bad "Codex-only recovery did not converge"

echo "smoke-upgrade OK: historical installs, removals, stops, ownership, refusal, rollback, and recovery"
