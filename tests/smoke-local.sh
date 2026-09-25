#!/usr/bin/env bash
# Local installs against real repositories. Git is the oracle: every Kit path
# must be ignored by Git's own rules, everything else must look exactly as it
# did, and a preview or refusal must change nothing, .git included.
set -euo pipefail
cd "$(dirname "$0")/.."
KIT="$PWD"
tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
bad() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
if stat --version >/dev/null 2>&1; then stat_format='-c%i'; else stat_format='-f%i'; fi
inode_of() { stat "$stat_format" "$1"; }

# A developer's own Git configuration, global excludes especially, must not
# decide what these cases observe. This isolates the test; it changes no config.
: >"$tmp/no-global-excludes"
cat >"$tmp/gitconfig" <<CONFIG
[user]
  name = Serel Kit smoke
  email = smoke@example.invalid
[commit]
  gpgsign = false
[init]
  defaultBranch = main
[core]
  excludesFile = $tmp/no-global-excludes
CONFIG
export GIT_CONFIG_GLOBAL="$tmp/gitconfig" GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$tmp/xdg"

header="$(sed -n 's/^EXCLUDE_HEADER="\(.*\)"$/\1/p' "$KIT/install.sh")"
[ -n "$header" ] || bad "could not read EXCLUDE_HEADER from install.sh"
WRITING=".claude/commands/polish.md .agents/skills/polish/SKILL.md .agents/skills/polish/RULES.md .agents/skills/polish/agents/openai.yaml"
VERIFY=".claude/commands/verify-map.md .agents/skills/verify-map/SKILL.md .agents/skills/verify-map/TEMPLATE.md .agents/skills/verify-map/agents/openai.yaml"

snapshot() {
  (
    cd "$1"
    find . -mindepth 1 | sort |
      while IFS= read -r path; do
        if [ -L "$path" ]; then printf 'link %s %s\n' "$path" "$(readlink "$path")"
        elif [ -d "$path" ]; then printf 'dir %s\n' "$path"
        else printf 'file %s %s\n' "$path" "$(cksum <"$path")"; fi
      done
  )
}
common_dir() { (cd "$1" && cd "$(git rev-parse --git-common-dir)" && pwd -P); }
exclude_of() { printf '%s/info/exclude\n' "$(common_dir "$1")"; }
# Everything a run could touch: the worktree, its .git, and the shared Git dir.
state() { snapshot "$1"; snapshot "$(common_dir "$1")"; }
new_repo() {
  git init -q "$1"
  printf 'tracked\n' >"$1/README.md"
  git -C "$1" add README.md
  git -C "$1" commit -qm base
}
run() {
  local log="$1"
  shift
  bash "$KIT/install.sh" "$@" >"$log" 2>&1 || { cat "$log"; bad "expected success: $*"; }
}
refused() {
  local target="$1" before
  shift
  before="$(state "$target")"
  if bash "$KIT/install.sh" "$target" "$@" >"$tmp/refused.log" 2>&1; then
    cat "$tmp/refused.log"
    bad "expected refusal: $*"
  fi
  [ "$(state "$target")" = "$before" ] || bad "refused run changed $target: $*"
}
all_ignored() {
  local repo="$1" path
  shift
  for path in "$@"; do
    [ -f "$repo/$path" ] || bad "missing after install: $path"
    git -C "$repo" check-ignore -q -- "$path" || bad "Git does not ignore $path"
  done
}
visible() { git -C "$1" status --porcelain --untracked-files=all; }

echo "case 1: preview writes nothing; apply excludes exact paths and keeps unrelated work"
repo="$tmp/repo"
new_repo "$repo"
mkdir "$repo/src"
printf 'one\n' >"$repo/src/app.txt"
printf '*.log\n' >"$repo/.gitignore"
git -C "$repo" add src/app.txt .gitignore
git -C "$repo" commit -qm work
printf 'unstaged\n' >>"$repo/README.md"
printf 'staged\n' >>"$repo/src/app.txt"
git -C "$repo" add src/app.txt
printf 'unstaged on top\n' >>"$repo/src/app.txt"
printf 'untracked\n' >"$repo/notes.txt"
printf 'ignored\n' >"$repo/debug.log"
mkdir -p "$repo/.claude/commands"
printf 'my own command\n' >"$repo/.claude/commands/mine.md"
exclude="$(exclude_of "$repo")"
printf '# mine\n*.swp\n/memory-bank/' >"$exclude" # no final newline, as hand edits often end
cp "$exclude" "$tmp/exclude-before"
status_before="$(visible "$repo")"
diff_before="$(git -C "$repo" diff; git -C "$repo" diff --cached)"
before="$(state "$repo")"
run "$tmp/preview.log" "$repo" --packs writing --local
[ "$(state "$repo")" = "$before" ] || bad "local preview wrote something"
grep -qF 'ADD        .claude/commands/polish.md' "$tmp/preview.log" || bad "preview omitted a file"
grep -qF 'EXCLUDE    /.serel-kit.json' "$tmp/preview.log" || bad "preview omitted the receipt exclusion"
run "$tmp/apply.log" "$repo" --packs writing --local --apply
# shellcheck disable=SC2086
{ cat "$tmp/exclude-before"; printf '\n%s\n' "$header"; printf '/%s\n' $WRITING .serel-kit.json | LC_ALL=C sort; } \
  >"$tmp/exclude-expected"
cmp -s "$exclude" "$tmp/exclude-expected" ||
  { diff "$tmp/exclude-expected" "$exclude" || true; bad "exclusions are not exactly the Kit paths"; }
# shellcheck disable=SC2086
all_ignored "$repo" $WRITING .serel-kit.json
[ "$(visible "$repo")" = "$status_before" ] || bad "Git status changed beyond the hidden Kit files"
[ "$(git -C "$repo" diff; git -C "$repo" diff --cached)" = "$diff_before" ] || bad "unrelated changes altered"
git -C "$repo" ls-files -o --exclude-standard | grep -qx '.claude/commands/mine.md' ||
  bad "a user's own .claude file became ignored"
jq -e '.local == true' "$repo/.serel-kit.json" >/dev/null || bad "receipt does not record local mode"
before="$(state "$repo")"
exclude_inode="$(inode_of "$exclude")"
receipt_inode="$(inode_of "$repo/.serel-kit.json")"
run "$tmp/rerun.log" "$repo" --packs writing --local --apply
grep -q 'nothing to do' "$tmp/rerun.log" || bad "converged rerun did not say nothing to do"
run "$tmp/inherit.log" "$repo" --packs writing
grep -q 'Preview only' "$tmp/inherit.log" || bad "a recorded local install did not preview"
[ "$(state "$repo")" = "$before" ] || bad "rerun changed the target"
[ "$(inode_of "$exclude")" = "$exclude_inode" ] || bad "rerun rewrote info/exclude"
[ "$(inode_of "$repo/.serel-kit.json")" = "$receipt_inode" ] || bad "rerun rewrote the receipt"

echo "case 2: an added pack and an upgrade stay local without --local; shared Memory untouched"
shared_memory="$tmp/shared-memory"
new_repo "$shared_memory"
mkdir "$shared_memory/memory-bank"
printf 'project memory\n' >"$shared_memory/memory-bank/activeContext.md"
printf '{}\n' >"$shared_memory/.serel-memory.json"
printf 'project rules\n' >"$shared_memory/.rules"
git -C "$shared_memory" add memory-bank .serel-memory.json .rules
git -C "$shared_memory" commit -qm memory
run "$tmp/local.log" "$shared_memory" --packs writing --local --apply
jq '.owner = "keep"' "$shared_memory/.serel-kit.json" >"$tmp/receipt"
mv "$tmp/receipt" "$shared_memory/.serel-kit.json"
# Another tool's block now follows Kit's; Kit's next lines must not join it.
exclude="$(exclude_of "$shared_memory")"
printf '# another tool\n/other-local-file\n' >>"$exclude"
cp "$exclude" "$tmp/exclude-before"
before="$(state "$shared_memory")"
run "$tmp/add-preview.log" "$shared_memory" --packs verify
[ "$(state "$shared_memory")" = "$before" ] || bad "inherited preview wrote something"
grep -qF 'EXCLUDE    /.claude/commands/verify-map.md' "$tmp/add-preview.log" || bad "added pack not excluded"
run "$tmp/add.log" "$shared_memory" --packs verify --apply
jq -e '.owner == "keep" and .local == true' "$shared_memory/.serel-kit.json" >/dev/null ||
  bad "adding a pack lost receipt metadata or local mode"
# shellcheck disable=SC2086
all_ignored "$shared_memory" $WRITING $VERIFY .serel-kit.json
for path in $WRITING $VERIFY .serel-kit.json; do
  [ "$(grep -cxF "/$path" "$exclude")" = 1 ] || bad "exclusion for $path is missing or duplicated"
done
# shellcheck disable=SC2086
{ cat "$tmp/exclude-before"; printf '%s\n' "$header"; printf '/%s\n' $VERIFY | LC_ALL=C sort; } \
  >"$tmp/exclude-expected"
cmp -s "$exclude" "$tmp/exclude-expected" ||
  { diff "$tmp/exclude-expected" "$exclude" || true; bad "added pack's lines are not a labeled block at the end"; }
if grep -Eq '(^|/)(memory-bank|\.rules|\.serel-memory\.json|AGENTS\.md|CLAUDE\.md)' "$exclude"; then
  bad "Kit excluded a Serel Memory path"
fi
[ -z "$(visible "$shared_memory")" ] || bad "Kit files became visible or Memory changed"
incoming="$tmp/incoming"
mkdir "$incoming"
cp -R "$KIT/install.sh" "$KIT/packs" "$incoming/"
printf '\nSynthetic upstream change.\n' >>"$incoming/packs/writing/.claude/commands/polish.md"
printf 'Synthetic added resource.\n' >"$incoming/packs/writing/.agents/skills/polish/EXTRA.md"
before="$(state "$shared_memory")"
bash "$incoming/install.sh" "$shared_memory" --packs writing --upgrade >"$tmp/up-preview.log" 2>&1 ||
  { cat "$tmp/up-preview.log"; bad "local upgrade preview failed"; }
[ "$(state "$shared_memory")" = "$before" ] || bad "local upgrade preview wrote something"
grep -qF 'EXCLUDE    /.agents/skills/polish/EXTRA.md' "$tmp/up-preview.log" || bad "upgrade addition not excluded"
bash "$incoming/install.sh" "$shared_memory" --packs writing --upgrade --apply >"$tmp/up.log" 2>&1 ||
  { cat "$tmp/up.log"; bad "local upgrade failed"; }
all_ignored "$shared_memory" .agents/skills/polish/EXTRA.md .claude/commands/polish.md
[ "$(tail -n 1 "$exclude")" = /.agents/skills/polish/EXTRA.md ] &&
  [ "$(grep -cxF "$header" "$exclude")" = 2 ] || bad "upgrade did not continue Kit's own final block"
cmp -s "$shared_memory/.claude/commands/polish.md" "$incoming/packs/writing/.claude/commands/polish.md" ||
  bad "upgrade did not update the command"
[ -z "$(visible "$shared_memory")" ] || bad "upgrade left a Kit file visible to Git"

echo "case 3: a linked worktree uses its repository's shared info/exclude"
main="$tmp/main"
new_repo "$main"
git -C "$main" worktree add -q -b side "$tmp/worktree"
[ -f "$tmp/worktree/.git" ] || bad "fixture is not a linked worktree"
before="$(state "$tmp/worktree")"
run "$tmp/wt-preview.log" "$tmp/worktree" --packs writing --local
[ "$(state "$tmp/worktree")" = "$before" ] || bad "worktree preview wrote something"
run "$tmp/wt.log" "$tmp/worktree" --packs writing --local --apply
exclude="$(exclude_of "$tmp/worktree")"
[ "$exclude" = "$(cd "$main/.git" && pwd -P)/info/exclude" ] || bad "worktree resolved the wrong exclude file"
for path in $WRITING .serel-kit.json; do
  grep -qxF "/$path" "$exclude" || bad "shared info/exclude lacks /$path"
done
# shellcheck disable=SC2086
all_ignored "$tmp/worktree" $WRITING .serel-kit.json
[ -f "$tmp/worktree/.git" ] || bad "worktree .git file replaced"
[ -z "$(visible "$tmp/worktree")" ] || bad "worktree shows Kit files"
[ -z "$(visible "$main")" ] || bad "main worktree changed"

echo "case 4: tracked Kit paths and shared-to-local switches are refused"
tracked="$tmp/tracked"
new_repo "$tracked"
mkdir -p "$tracked/.claude/commands"
cp "$KIT/packs/writing/.claude/commands/polish.md" "$tracked/.claude/commands/polish.md"
git -C "$tracked" add .claude
git -C "$tracked" commit -qm identical
refused "$tracked" --packs writing --local
grep -q 'TRACKED' "$tmp/refused.log" || bad "identical tracked file not reported"
refused "$tracked" --packs writing --local --apply
staged="$tmp/staged"
new_repo "$staged"
printf '{}\n' >"$staged/.serel-kit.json"
git -C "$staged" add .serel-kit.json
refused "$staged" --packs writing --local --apply
grep -q 'TRACKED' "$tmp/refused.log" || bad "staged receipt not reported"
variant="$tmp/variant"
new_repo "$variant"
mkdir -p "$variant/.Claude/commands"
cp "$KIT/packs/writing/.claude/commands/polish.md" "$variant/.Claude/commands/polish.md"
git -C "$variant" add .Claude
rm -r "$variant/.Claude" # Index only: case 9 covers a case variant on disk.
refused "$variant" --packs writing --local --apply
grep -q 'TRACKED' "$tmp/refused.log" || bad "case-variant tracked path not reported"
git -C "$repo" add -f .claude/commands/polish.md
refused "$repo" --packs writing --apply
grep -q 'TRACKED' "$tmp/refused.log" || bad "force-added Kit file not reported"
shared="$tmp/shared"
new_repo "$shared"
run "$tmp/shared.log" "$shared" --packs writing
jq -e 'has("local") | not' "$shared/.serel-kit.json" >/dev/null || bad "shared receipt recorded a mode"
refused "$shared" --packs writing --local
grep -q 'shared installation' "$tmp/refused.log" || bad "shared-to-local switch not explained"
refused "$shared" --packs writing --local --apply
refused "$shared" --packs writing --local --upgrade --apply
refused "$shared" --packs writing --apply

echo "case 5: an ignore rule that re-includes a Kit path is refused"
negated="$tmp/negated"
new_repo "$negated"
printf '!/.claude/commands/polish.md\n' >"$negated/.gitignore"
refused "$negated" --packs writing --local
grep -qF '.gitignore:1:!/.claude/commands/polish.md' "$tmp/refused.log" || bad "negation source not named"
refused "$negated" --packs writing --local --apply
rm "$negated/.gitignore"
mkdir "$negated/.agents"
printf '!skills/polish/SKILL.md\n' >"$negated/.agents/.gitignore"
refused "$negated" --packs writing --local --apply
rm -r "$negated/.agents"
printf '!/.serel-kit.json\n' >>"$(exclude_of "$negated")"
refused "$negated" --packs writing --local --apply
printf '!/.agents/skills/polish/RULES.md\n' >"$repo/.gitignore"
git -C "$repo" reset -q -- .claude/commands/polish.md
refused "$repo" --packs writing --apply
grep -q 'VISIBLE' "$tmp/refused.log" || bad "rerun did not recheck ignore rules"

echo "case 6: malformed receipts and unsafe exclude paths write nothing"
unsafe="$tmp/unsafe"
new_repo "$unsafe"
printf '{"local":"yes"}\n' >"$unsafe/.serel-kit.json"
refused "$unsafe" --packs writing --local --apply
refused "$unsafe" --packs writing --apply
jq -n '{local: true, packs: ["writing"], installed: {writing: {version: "0.2.0",
  files: {".agents/skills/../../memory-bank/activeContext.md": ("a" * 64)}}}}' >"$unsafe/.serel-kit.json"
refused "$unsafe" --packs writing --apply
rm "$unsafe/.serel-kit.json"
# A second document after a valid local receipt must not replace it: jq reads
# the last one, which would drop local mode and the mandatory preview.
concat="$tmp/concat"
new_repo "$concat"
run "$tmp/concat.log" "$concat" --packs writing --local --apply
printf '{}\n' >>"$concat/.serel-kit.json"
refused "$concat" --packs writing
grep -q 'not a valid Serel Kit receipt' "$tmp/refused.log" || bad "concatenated receipt not refused as invalid"
refused "$concat" --packs writing --apply
: >"$concat/.serel-kit.json"
refused "$concat" --packs writing --local --apply
grep -q 'not a valid Serel Kit receipt' "$tmp/refused.log" || bad "empty receipt not refused as invalid"
exclude="$(exclude_of "$unsafe")"
mv "$exclude" "$tmp/outside-exclude"
ln -s "$tmp/outside-exclude" "$exclude"
outside_before="$(cksum <"$tmp/outside-exclude")"
refused "$unsafe" --packs writing --local --apply
[ "$(cksum <"$tmp/outside-exclude")" = "$outside_before" ] || bad "wrote through a symlinked info/exclude"
rm "$exclude"
mv "$tmp/outside-exclude" "$exclude"
ln "$exclude" "$tmp/exclude-hardlink"
refused "$unsafe" --packs writing --local --apply
rm "$tmp/exclude-hardlink"
info="$(dirname "$exclude")"
mv "$info" "$tmp/outside-info"
ln -s "$tmp/outside-info" "$info"
refused "$unsafe" --packs writing --local --apply
rm "$info"
mv "$tmp/outside-info" "$info"
mkdir -p "$unsafe/.agents" "$tmp/elsewhere"
ln -s "$tmp/elsewhere" "$unsafe/.agents/skills"
refused "$unsafe" --packs writing --local --apply
grep -q 'UNSAFE PATH' "$tmp/refused.log" || bad "symlinked payload ancestor not reported"
[ -z "$(ls -A "$tmp/elsewhere")" ] || bad "wrote through a symlinked payload ancestor"

echo "case 7: an ordinary write failure restores files, receipt and exclusions"
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
# fail_copy <target> <dest> <flag> <install.sh> <args...>: copying to dest fails once.
fail_copy() {
  local target="$1" dest="$2" flag="$3" installer="$4" before recovery
  shift 4
  before="$(state "$target")"
  if PATH="$tmp/shim:$PATH" REAL_CP="$real_cp" FAIL_DEST="$target/$dest" FAIL_ONCE="$flag" \
    bash "$installer" "$target" "$@" >"$tmp/fail.log" 2>&1; then
    bad "injected failure at $dest succeeded"
  fi
  [ -f "$flag" ] || bad "failure at $dest not exercised"
  [ "$(state "$target")" = "$before" ] || { cat "$tmp/fail.log"; bad "failure at $dest left changes"; }
  recovery="$(sed -n 's/^Recovery files retained at //p' "$tmp/fail.log")"
  [ -d "$recovery/backups" ] || bad "failure at $dest kept no recovery files"
  rm -rf "$recovery"
}
rollback="$tmp/rollback"
new_repo "$rollback"
printf '# mine\n/memory-bank/\n' >"$(exclude_of "$rollback")"
fail_copy "$rollback" .serel-kit.json "$tmp/failed-receipt" "$KIT/install.sh" --packs writing --local --apply
no_info="$tmp/no-info"
new_repo "$no_info"
rm -r "$no_info/.git/info"
fail_copy "$no_info" .claude/commands/polish.md "$tmp/failed-payload" "$KIT/install.sh" --packs writing --local --apply
[ ! -e "$no_info/.git/info" ] || bad "rollback left a created info directory"
# A local upgrade that has already updated one file, added another, and
# excluded the addition fails on the receipt. state covers the payload, the
# receipt, info/exclude, the index, and the unrelated work around them.
local_upgrade="$tmp/local-upgrade"
new_repo "$local_upgrade"
run "$tmp/lu.log" "$local_upgrade" --packs writing --local --apply
printf '/my-own-local-file\n' >>"$(exclude_of "$local_upgrade")"
printf 'unstaged\n' >>"$local_upgrade/README.md"
printf 'staged\n' >"$local_upgrade/staged.txt"
git -C "$local_upgrade" add staged.txt
printf 'untracked\n' >"$local_upgrade/notes.txt"
fail_copy "$local_upgrade" .serel-kit.json "$tmp/failed-upgrade-receipt" "$incoming/install.sh" --packs writing --upgrade --apply
for line in 'UPDATE     .claude/commands/polish.md' 'ADD        .agents/skills/polish/EXTRA.md' \
  'EXCLUDE    /.agents/skills/polish/EXTRA.md'; do
  grep -qF -- "$line" "$tmp/fail.log" || bad "local upgrade rollback did not exercise: $line"
done
mkdir "$tmp/cat-shim"
cat >"$tmp/cat-shim/cat" <<'SHIM'
#!/usr/bin/env bash
# Append only part of Kit's exclusion block, then fail.
case "${1:-}" in
  */exclude-add) touch "$FAIL_ONCE"; head -n 2 "$1"; exit 1 ;;
esac
exec "$REAL_CAT" "$@"
SHIM
chmod +x "$tmp/cat-shim/cat"
before="$(state "$rollback")"
if PATH="$tmp/cat-shim:$PATH" REAL_CAT="$(command -v cat)" FAIL_ONCE="$tmp/failed-append" \
  bash "$KIT/install.sh" "$rollback" --packs writing --local --apply >"$tmp/append-fail.log" 2>&1; then
  bad "a partial exclusion append was accepted"
fi
[ -f "$tmp/failed-append" ] || bad "partial exclusion append not exercised"
[ "$(state "$rollback")" = "$before" ] || { cat "$tmp/append-fail.log"; bad "partial exclusion append left changes"; }
rm -rf "$(sed -n 's/^Recovery files retained at //p' "$tmp/append-fail.log")"
mkdir "$tmp/git-shim"
real_git="$(command -v git)"
cat >"$tmp/git-shim/git" <<'SHIM'
#!/usr/bin/env bash
# Git's real rules disagree with the prediction made before writing.
case " $* " in
  *" check-ignore "*) case "$*" in *core.excludesFile=*) ;; *) exit 1 ;; esac ;;
esac
exec "$REAL_GIT" "$@"
SHIM
chmod +x "$tmp/git-shim/git"
before="$(state "$rollback")"
if PATH="$tmp/git-shim:$PATH" REAL_GIT="$real_git" \
  bash "$KIT/install.sh" "$rollback" --packs writing --local --apply >"$tmp/verify-fail.log" 2>&1; then
  bad "an unignored path after writing exclusions was accepted"
fi
grep -q 'Git does not ignore' "$tmp/verify-fail.log" || bad "post-write ignore check not exercised"
[ "$(state "$rollback")" = "$before" ] || bad "failed ignore check left changes"
rm -rf "$(sed -n 's/^Recovery files retained at //p' "$tmp/verify-fail.log")"

echo "case 8: shared Kit beside an independently local Memory bank"
local_memory="$tmp/local-memory"
new_repo "$local_memory"
mkdir "$local_memory/memory-bank"
printf 'private memory\n' >"$local_memory/memory-bank/activeContext.md"
printf '{}\n' >"$local_memory/.serel-memory.json"
printf 'rules\n' >"$local_memory/.rules"
exclude="$(exclude_of "$local_memory")"
printf '/memory-bank/\n/.rules\n/.serel-memory.json\n' >>"$exclude"
cp "$exclude" "$tmp/memory-exclude"
run "$tmp/mixed.log" "$local_memory" --packs writing,verify
cmp -s "$exclude" "$tmp/memory-exclude" || bad "shared Kit install changed info/exclude"
jq -e 'has("local") | not' "$local_memory/.serel-kit.json" >/dev/null || bad "shared receipt recorded a mode"
git -C "$local_memory" ls-files -o --exclude-standard >"$tmp/shareable"
for path in $WRITING $VERIFY .serel-kit.json; do
  grep -qxF "$path" "$tmp/shareable" || bad "shared Kit file hidden from Git: $path"
done
git -C "$local_memory" check-ignore -q memory-bank/activeContext.md || bad "local Memory became visible"

echo "case 9: a case variant of a Kit path on disk"
alias_repo="$tmp/alias"
new_repo "$alias_repo"
# Git lists .Claude/ and .Serel-kit.json by their own spelling, which the
# lowercase exclusions do not match when core.ignorecase is false.
git -C "$alias_repo" config core.ignorecase false
mkdir -p "$alias_repo/.Claude/commands"
printf 'my own command\n' >"$alias_repo/.Claude/commands/mine.md"
: >"$tmp/case-probe"
if [ -e "$tmp/CASE-PROBE" ]; then
  refused "$alias_repo" --packs writing --local --apply
  grep -qF '.claude exists with different letter case' "$tmp/refused.log" || bad ".Claude alias not reported"
  refused "$alias_repo" --packs writing
  rm -r "$alias_repo/.Claude"
  printf '{}\n' >"$alias_repo/.Serel-kit.json"
  refused "$alias_repo" --packs writing --local --apply
  grep -qF '.serel-kit.json exists with different letter case' "$tmp/refused.log" ||
    bad ".Serel-kit.json alias not reported"
else
  echo "  case-sensitive filesystem: variants are separate files and stay as they were"
  printf '{}\n' >"$alias_repo/.Serel-kit.json"
  run "$tmp/alias.log" "$alias_repo" --packs writing --local --apply
  # shellcheck disable=SC2086
  all_ignored "$alias_repo" $WRITING .serel-kit.json
  [ "$(visible "$alias_repo")" = "$(printf '?? .Claude/commands/mine.md\n?? .Serel-kit.json')" ] ||
    bad "a case-variant user file changed visibility"
  [ "$(cat "$alias_repo/.Claude/commands/mine.md" "$alias_repo/.Serel-kit.json")" = "$(printf 'my own command\n{}')" ] ||
    bad "a case-variant user file changed"
fi

echo "smoke-local OK: preview, exact exclusions, inheritance, worktrees, refusals, and rollback"
