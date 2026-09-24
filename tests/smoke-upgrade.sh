#!/usr/bin/env bash
# Real filesystem upgrades against a synthetic newer Kit checkout. The released
# tag supplies legacy bytes; incoming changes deliberately differ from that tag.
set -euo pipefail
cd "$(dirname "$0")/.."
KIT="$PWD"
tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
bad() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
if stat --version >/dev/null 2>&1; then stat_format='-c%i'; else stat_format='-f%i'; fi
inode_of() { stat "$stat_format" "$1"; }

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
install_base() {
  new_repo "$1"
  bash "$base/install.sh" "$1" --packs writing,verify >"$tmp/install.log" 2>&1 ||
    { cat "$tmp/install.log"; bad "base installation"; }
}
expect_refused() {
  local target="$1" before
  shift
  before="$(snapshot "$target")"
  if bash "$incoming/install.sh" "$target" "$@" >"$tmp/refused.log" 2>&1; then
    bad "expected refusal: $*"
  fi
  [ "$(snapshot "$target")" = "$before" ] || bad "refused operation changed target: $*"
}
upgrade_apply() {
  bash "$incoming/install.sh" "$1" --packs writing --upgrade --apply >"$tmp/apply.log" 2>&1 ||
    { cat "$tmp/apply.log"; bad "upgrade application"; }
}

base="$tmp/base"
incoming="$tmp/incoming"
git clone --quiet --no-hardlinks "$KIT" "$base"
git -C "$base" checkout --quiet v0.1.0
# The base installs v0.1.0 bytes, so it records that version whatever the
# current release is: legacy receipts resolve their baseline from that tag.
sed 's/^KIT_VERSION=".*"$/KIT_VERSION="0.1.0"/' "$KIT/install.sh" >"$base/install.sh"
git clone --quiet --no-hardlinks "$KIT" "$incoming"
git -C "$incoming" checkout --quiet v0.1.0
sed 's/^KIT_VERSION=".*"$/KIT_VERSION="0.2.0"/' "$KIT/install.sh" >"$incoming/install.sh"
command_path=".claude/commands/polish.md"
skill_path=".agents/skills/polish/SKILL.md"
rules_path=".agents/skills/polish/RULES.md"
retired_path=".agents/skills/polish/agents/openai.yaml"
added_path=".agents/skills/polish/EXTRA.md"
printf '\nSynthetic upstream command change.\n' >>"$incoming/packs/writing/$command_path"
printf '\nSynthetic upstream skill change.\n' >>"$incoming/packs/writing/$skill_path"
printf 'Synthetic added resource.\n' >"$incoming/packs/writing/$added_path"
rm "$incoming/packs/writing/$retired_path"

echo "case 1: preview, safe updates, local-only customization, retirement and convergence"
project="$tmp/project"
install_base "$project"
jq '.owner = "keep" | .installed.writing.note = "keep nested"' "$project/.serel-kit.json" >"$tmp/receipt"
mv "$tmp/receipt" "$project/.serel-kit.json"
verify_before="$(jq -c '.installed.verify' "$project/.serel-kit.json")"
guard_before="$(guarded "$project")"
printf '\nLocal house rule.\n' >>"$project/$rules_path"
rules_before="$(cksum <"$project/$rules_path")"
chmod 755 "$project/$command_path"
before="$(snapshot "$project")"
bash "$incoming/install.sh" "$project" --packs writing --upgrade >"$tmp/preview.log" 2>&1 ||
  { cat "$tmp/preview.log"; bad "preview failed"; }
[ "$(snapshot "$project")" = "$before" ] || bad "preview wrote files"
for action in UPDATE ADD 'KEEP LOCAL' RETIRED; do
  grep -q "$action" "$tmp/preview.log" || bad "preview missed $action"
done
grep -q '^@@' "$tmp/preview.log" || bad "preview omitted diffs"
upgrade_apply "$project"
cmp -s "$project/$command_path" "$incoming/packs/writing/$command_path" || bad "command not updated"
cmp -s "$project/$skill_path" "$incoming/packs/writing/$skill_path" || bad "skill not updated"
[ -x "$project/$command_path" ] || bad "existing mode changed"
cmp -s "$project/$added_path" "$incoming/packs/writing/$added_path" || bad "new resource not added"
[ "$(cksum <"$project/$rules_path")" = "$rules_before" ] || bad "local rules overwritten"
[ -f "$project/$retired_path" ] || bad "retired file deleted"
[ "$(guarded "$project")" = "$guard_before" ] || bad "Memory boundary violated"
[ "$(jq -c '.installed.verify' "$project/.serel-kit.json")" = "$verify_before" ] || bad "unselected pack changed"
jq -e --arg retired "$retired_path" --arg rules "$rules_path" '
  .kit == "0.2.0" and .owner == "keep" and .installed.writing.note == "keep nested"
  and .installed.writing.version == "0.2.0"
  and (.installed.writing.files | has($retired) | not)
  and (.installed.writing.files[$rules] | length == 64)
' "$project/.serel-kit.json" >/dev/null || bad "receipt metadata or manifest wrong"
base_rules_hash="$(jq -r --arg path "$rules_path" '.installed.writing.files[$path]' "$project/.serel-kit.json")"
if command -v sha256sum >/dev/null 2>&1; then
  source_rules_hash="$(sha256sum "$incoming/packs/writing/$rules_path" | awk '{print $1}')"
else
  source_rules_hash="$(shasum -a 256 "$incoming/packs/writing/$rules_path" | awk '{print $1}')"
fi
[ "$base_rules_hash" = "$source_rules_hash" ] || bad "receipt adopted customized local bytes as baseline"
before="$(snapshot "$project")"
inode_before="$(inode_of "$project/.serel-kit.json")"
upgrade_apply "$project"
[ "$(snapshot "$project")" = "$before" ] || bad "repeat upgrade changed files"
[ "$(inode_of "$project/.serel-kit.json")" = "$inode_before" ] || bad "repeat rewrote receipt"

echo "case 2: both-changed, local deletion, unowned additions, and whole-selection refusal"
conflict="$tmp/conflict"
install_base "$conflict"
printf '\nLocal command change.\n' >>"$conflict/$command_path"
expect_refused "$conflict" --packs writing,verify --upgrade --apply
grep -q CONFLICT "$tmp/refused.log" || bad "both-changed not reported"
cp "$incoming/packs/writing/$command_path" "$conflict/$command_path"
upgrade_apply "$conflict"
deleted="$tmp/deleted"
install_base "$deleted"
rm "$deleted/$rules_path"
expect_refused "$deleted" --packs writing --upgrade --apply
unowned="$tmp/unowned"
install_base "$unowned"
printf 'User-owned resource\n' >"$unowned/$added_path"
expect_refused "$unowned" --packs writing --upgrade --apply
retired_absent="$tmp/retired-absent"
install_base "$retired_absent"
rm "$retired_absent/$retired_path"
upgrade_apply "$retired_absent"
[ ! -e "$retired_absent/$retired_path" ] || bad "retired absent file resurrected"
printf '\nNew upstream rule.\n' >>"$incoming/packs/writing/$rules_path"
expect_refused "$project" --packs writing --upgrade --apply
cp "$base/packs/writing/$rules_path" "$incoming/packs/writing/$rules_path"

echo "case 3: exact legacy tag baseline and independently preserved pack versions"
legacy="$tmp/legacy"
install_base "$legacy"
jq 'del(.installed) | .owner = "legacy"' "$legacy/.serel-kit.json" >"$tmp/receipt"
mv "$tmp/receipt" "$legacy/.serel-kit.json"
printf '\nLegacy local rule.\n' >>"$legacy/$rules_path"
upgrade_apply "$legacy"
jq -e '.installed.writing.version == "0.2.0" and .installed.verify.version == "0.1.0"
  and .installed.verify.files == null and .owner == "legacy"' "$legacy/.serel-kit.json" >/dev/null ||
  bad "legacy unselected pack lost its actual baseline version"
bash "$incoming/install.sh" "$legacy" --packs verify --upgrade --apply >"$tmp/legacy-verify.log" 2>&1 ||
  { cat "$tmp/legacy-verify.log"; bad "second legacy pack did not resolve its original tag"; }
missing_tag="$tmp/missing-tag"
install_base "$missing_tag"
jq 'del(.installed) | .kit = "9.9.9"' "$missing_tag/.serel-kit.json" >"$tmp/receipt"
mv "$tmp/receipt" "$missing_tag/.serel-kit.json"
expect_refused "$missing_tag" --packs writing --upgrade --apply
grep -q 'baseline tag v9.9.9' "$tmp/refused.log" || bad "missing tag not explained"

echo "case 4: malformed receipts, traversal, destination/source links and bad options"
unsafe="$tmp/unsafe"
install_base "$unsafe"
cp "$unsafe/.serel-kit.json" "$tmp/good-receipt"
jq '.installed.writing.files[".agents/skills/../../memory-bank/activeContext.md"] =
  ("a" * 64)' "$tmp/good-receipt" >"$unsafe/.serel-kit.json"
expect_refused "$unsafe" --packs writing --upgrade --apply
jq '.installed.writing.files = {"bad": "not-a-hash"}' "$tmp/good-receipt" >"$unsafe/.serel-kit.json"
expect_refused "$unsafe" --packs writing --upgrade --apply
jq '.installed.writing.files[".claude/commands/a.md\n.claude/commands/b.md"] =
  ("a" * 64)' "$tmp/good-receipt" >"$unsafe/.serel-kit.json"
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
ln -s "$tmp/good-receipt" "$incoming/packs/writing/.agents/skills/polish/LINK"
expect_refused "$unsafe" --packs writing --upgrade --apply
rm "$incoming/packs/writing/.agents/skills/polish/LINK"
ln "$unsafe/$command_path" "$unsafe/memory-bank/linked-command.md"
expect_refused "$unsafe" --packs writing --upgrade --apply
rm "$unsafe/memory-bank/linked-command.md"
expect_refused "$unsafe" --packs writing --apply
uninstalled="$tmp/uninstalled"
new_repo "$uninstalled"
expect_refused "$uninstalled" --packs writing --upgrade --apply

echo "case 5: copy failure after an update rolls back files, new directories and receipt"
rollback="$tmp/rollback"
install_base "$rollback"
mkdir "$incoming/packs/writing/.agents/skills/polish/AAA"
printf 'new nested resource\n' >"$incoming/packs/writing/.agents/skills/polish/AAA/new.md"
mkdir "$tmp/shim"
real_cp="$(command -v cp)"
cat >"$tmp/shim/cp" <<'SHIM'
#!/usr/bin/env bash
dest="${@: -1}"
if [ "$dest" = "$FAIL_DEST" ] && [ ! -e "$FAIL_ONCE" ]; then
  touch "$FAIL_ONCE"
  printf 'partial copy\n' >"$dest"
  exit 1
fi
exec "$REAL_CP" "$@"
SHIM
chmod +x "$tmp/shim/cp"
before="$(snapshot "$rollback")"
if PATH="$tmp/shim:$PATH" REAL_CP="$real_cp" FAIL_DEST="$rollback/$command_path" FAIL_ONCE="$tmp/failed" \
  bash "$incoming/install.sh" "$rollback" --packs writing --upgrade --apply >"$tmp/rollback.log" 2>&1; then
  bad "injected copy failure succeeded"
fi
[ -f "$tmp/failed" ] || bad "copy failure not exercised"
[ "$(snapshot "$rollback")" = "$before" ] || { cat "$tmp/rollback.log"; bad "rollback left mutations"; }
recovery="$(sed -n 's/^Recovery files retained at //p' "$tmp/rollback.log")"
[ -d "$recovery/backups" ] || bad "recovery backups not retained"
rm -rf "$recovery"

# The receipt is the last write; failing there must restore the entire payload.
receipt_failure="$tmp/receipt-failure"
install_base "$receipt_failure"
before="$(snapshot "$receipt_failure")"
if PATH="$tmp/shim:$PATH" REAL_CP="$real_cp" FAIL_DEST="$receipt_failure/.serel-kit.json" FAIL_ONCE="$tmp/receipt-failed" \
  bash "$incoming/install.sh" "$receipt_failure" --packs writing --upgrade --apply >"$tmp/receipt-failure.log" 2>&1; then
  bad "injected receipt failure succeeded"
fi
[ -f "$tmp/receipt-failed" ] || bad "receipt failure not exercised"
[ "$(snapshot "$receipt_failure")" = "$before" ] || bad "receipt failure left mutations"
recovery="$(sed -n 's/^Recovery files retained at //p' "$tmp/receipt-failure.log")"
[ -d "$recovery/backups" ] || bad "receipt failure omitted recovery backups"
rm -rf "$recovery"

echo "case 6: complete-payload prefix collisions are refused in either pack order"
mkdir -p "$incoming/packs/writing/.agents/skills/collision/RESOURCE.md"
printf 'child\n' >"$incoming/packs/writing/.agents/skills/collision/RESOURCE.md/child.md"
mkdir -p "$incoming/packs/verify/.agents/skills/collision"
printf 'parent\n' >"$incoming/packs/verify/.agents/skills/collision/RESOURCE.md"
for order in writing,verify verify,writing; do
  collision="$tmp/collision-$order"
  new_repo "$collision"
  expect_refused "$collision" --packs "$order"
done
rm -rf "$incoming/packs/writing/.agents/skills/collision"
rm -rf "$incoming/packs/verify/.agents/skills/collision"

# An unselected pack's deleted file still owns the path and its ancestors.
owned="$tmp/owned"
install_base "$owned"
jq '.installed.verify.files[".agents/skills/polish/EXTRA.md/child.md"] =
  ("a" * 64)' "$owned/.serel-kit.json" >"$tmp/receipt"
mv "$tmp/receipt" "$owned/.serel-kit.json"
expect_refused "$owned" --packs writing --upgrade --apply

echo "smoke-upgrade OK: preview, three-way decisions, legacy receipts, boundary, refusal, and rollback"
