#!/usr/bin/env bash
# Asserts that every pack ships one source per workflow, and that the
# installer's list of retired commands matches what the releases shipped.
#
# A Serel Kit workflow is one skill. Its source is
# packs/<pack>/.agents/skills/<name>/SKILL.md, with its resources
# (agents/openai.yaml, RULES.md, TEMPLATE.md, scripts/) in that folder; Codex
# discovers it there. Claude Code discovers packs/<pack>/.claude/skills/<name>/
# SKILL.md, a byte-identical copy that sits alone in its folder. This mirrors
# Serel Memory's tests/check-single-source.sh.
#
# It checks these things and nothing else:
#   1. Layout: every source has its manifest and a byte-identical Claude copy
#      alone in its folder, every Claude copy has a source, and no pack ships
#      .claude/commands/ (or anything else under .claude/ but skills/).
#   2. Every .agents/skills/... resource a body references really exists
#      inside the pack (so RULES.md and TEMPLATE.md travel with the skill).
#   3. The own-CLI rule for a body both CLIs load: it may call the other CLI
#      only inside a labeled branch (**In Claude Code:** may run codex exec,
#      **In Codex:** may run claude -p), never its own CLI.
#   4. install.sh's retired-command map and known shipped hashes are exactly
#      what the release tags shipped: every .claude/commands/<name>.md any tag
#      ships is mapped to its pack and to a Claude copy that exists today, and
#      every hash is regenerated from the tags with the installer's digest.
#      This needs the release tags (CI fetches full history).
#
# What it does NOT check: that a workflow behaves the same way in Claude Code
# and Codex. Only a person running both can tell you that. See each pack's
# acceptance exercise.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
packs=0
copies=0

# Own-CLI rule, ported from Serel Memory 0.8.0's tests/check-single-source.sh.
# A line containing "Which CLI am I running in" opens the branch; labeled
# blocks then start with exactly **In Claude Code:** or **In Codex:** (after
# any list marker or indentation). Every `codex exec` must sit under
# **In Claude Code:** and every `claude -p` under **In Codex:**, after the
# label and before the next label or Markdown heading. A `#` line inside a
# fenced block is code, not a heading. Prints one file:line finding per
# offending line; prints nothing when it passes.
own_cli_rule() {
  awk '
    function fence_mark(s) { match(s, /^[[:space:]]*(```+|~~~+)/); s = substr(s, RSTART, RLENGTH); gsub(/[[:space:]]/, "", s); return s }
    function check(needle, want, wanted,   why) {
      if (index($0, needle) == 0 || label == want) return
      if (label == "early") why = "its label at line " label_at " comes before any \"Which CLI am I running in\" line"
      else if (label != "") why = "self-call: it sits under the **In " (label == "claude" ? "Claude Code" : "Codex") ":** label at line " label_at ", and a CLI must never call itself"
      else if (reset_at > 0) why = "the heading at line " reset_at " ended the labeled block above it"
      else why = "unlabeled: it is not under an **In " wanted ":** label"
      printf "%s:%d: `%s`: %s\n", FILENAME, FNR, needle, why
    }
    FNR == 1 { asked = 0; label = ""; label_at = 0; reset_at = 0; fence = "" }
    {
      if (fence != "") {
        if ($0 ~ /^[[:space:]]*(```|~~~)/) {
          m = fence_mark($0)
          if (substr(m, 1, 1) == substr(fence, 1, 1) && length(m) >= length(fence)) fence = ""
        }
      } else if ($0 ~ /^[[:space:]]*(```|~~~)/) {
        fence = fence_mark($0)
      } else {
        if ($0 ~ /^ ? ? ?#+([[:space:]]|$)/) { if (label != "") reset_at = FNR; label = "" }
        if (index($0, "Which CLI am I running in")) asked = 1
        if ($0 ~ /^[[:space:]]*(([-+*]|[0-9]+[.)])[[:space:]]+)?\*\*In Claude Code:\*\*/) { label = asked ? "claude" : "early"; label_at = FNR; reset_at = 0 }
        else if ($0 ~ /^[[:space:]]*(([-+*]|[0-9]+[.)])[[:space:]]+)?\*\*In Codex:\*\*/) { label = asked ? "codex" : "early"; label_at = FNR; reset_at = 0 }
      }
      check("codex exec", "claude", "Claude Code")
      check("claude -p", "codex", "Codex")
    }
  ' "$@"
}

# The rule must pass a canonical body and flag each way of breaking it, so a
# regression in the rule itself fails CI.
own_cli_self_test() {
  local t rc=0 out f want
  t="$(mktemp -d)"
  cat >"$t/good.md" <<'EOF'
# Good

Which CLI am I running in? Take only this CLI's branch; never call your own CLI.

- **In Claude Code:** the other reviewer is Codex:

  ```bash
  # A comment in a fence is not a heading.
  codex exec --cd "$PWD" --sandbox read-only - < "$PROMPT_FILE"
  ```

- **In Codex:** the other reviewer is Claude: `claude -p --permission-mode plan < "$PROMPT_FILE"`.
EOF
  cat >"$t/self-call.md" <<'EOF'
# Self-call

Which CLI am I running in?

- **In Claude Code:** run `claude -p --permission-mode plan < "$PROMPT_FILE"`.
EOF
  cat >"$t/unlabeled.md" <<'EOF'
# Unlabeled

Ask the other one: `codex exec --cd "$PWD" --sandbox read-only - < "$PROMPT_FILE"`
EOF
  cat >"$t/heading-reset.md" <<'EOF'
# Heading reset

Which CLI am I running in?

- **In Codex:** the other reviewer is Claude.

## Next step

claude -p --permission-mode plan < "$PROMPT_FILE"
EOF
  cat >"$t/label-first.md" <<'EOF'
# Label first

- **In Claude Code:** `codex exec --cd "$PWD" --sandbox read-only - < "$PROMPT_FILE"`

Which CLI am I running in?
EOF
  out="$(own_cli_rule "$t/good.md")"
  if [ -n "$out" ]; then echo "SELF-TEST: the own-CLI rule flagged a canonical body:"; printf '%s\n' "$out"; rc=1; fi
  for f in self-call:self-call unlabeled:unlabeled heading-reset:heading label-first:"before any"; do
    want="${f#*:}"; f="${f%%:*}"
    out="$(own_cli_rule "$t/$f.md")"
    if ! grep -q -- "$want" <<<"$out"; then
      echo "SELF-TEST: the own-CLI rule did not flag $f.md ($want); it printed: ${out:-nothing}"; rc=1
    fi
  done
  rm -rf "$t"
  return "$rc"
}
if ! own_cli_self_test; then fail=1; fi

for dir in packs/*/; do
  pack="${dir%/}"
  name="$(basename "$pack")"
  packs=$((packs + 1))
  src_root="$pack/.agents/skills"
  dst_root="$pack/.claude/skills"

  if [ ! -f "$pack/README.md" ]; then
    echo "MISSING README: pack '$name' has no README.md (it documents the acceptance exercise)"
    fail=1
  fi
  if [ -e "$pack/.claude/commands" ] || [ -L "$pack/.claude/commands" ]; then
    echo "COMMANDS: pack '$name' has .claude/commands/; workflows ship as .claude/skills/<name>/SKILL.md"
    fail=1
  fi
  if [ ! -d "$src_root" ] || [ ! -d "$dst_root" ]; then
    echo "MALFORMED PACK: '$name' needs both .agents/skills and .claude/skills directories"
    fail=1
    continue
  fi
  for f in "$pack"/.claude/* "$pack"/.claude/.[!.]*; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    [ "$f" = "$dst_root" ] && [ ! -L "$f" ] && continue
    [ "$f" = "$pack/.claude/commands" ] && continue # reported above
    echo "STRAY: $f is not .claude/skills (resources live in .agents/skills/<name>/)"
    fail=1
  done

  # 1a. Every source has its manifest and a byte-identical Claude copy that
  # sits alone in its folder.
  for d in "$src_root"/*/; do
    w="$(basename "$d")"
    src="$src_root/$w/SKILL.md"
    dst="$dst_root/$w/SKILL.md"
    yaml="$src_root/$w/agents/openai.yaml"
    if [ ! -f "$src" ]; then
      echo "MISSING SOURCE: $src_root/$w/ has no SKILL.md"
      fail=1
      continue
    fi
    if [ ! -f "$yaml" ]; then
      echo "MISSING MANIFEST: \$$w in pack '$name' has no agents/openai.yaml"
      fail=1
    elif ! grep -qE "default_prompt:.*\\\$$w([^A-Za-z0-9_-]|\$)" "$yaml"; then
      echo "MANIFEST DRIFT: $yaml default_prompt does not name \$$w"
      fail=1
    fi
    if [ -L "$dst" ] || [ -L "$dst_root/$w" ]; then
      echo "COPY DRIFT: $dst is a symlink; it must be a plain copy (cp $src $dst)"
      fail=1
    elif [ ! -f "$dst" ]; then
      echo "MISSING COPY: $src has no Claude copy $dst (cp $src $dst)"
      fail=1
    elif ! cmp -s "$src" "$dst"; then
      echo "COPY DRIFT: $dst differs from $src (edit the source, then cp $src $dst)"
      fail=1
    else
      copies=$((copies + 1))
    fi
    if [ -d "$dst_root/$w" ] && [ ! -L "$dst_root/$w" ]; then
      extra="$(find "$dst_root/$w" -mindepth 1 ! -path "$dst" -print | LC_ALL=C sort | tr '\n' ' ')"
      if [ -n "$extra" ]; then
        echo "EXTRA FILES: $dst_root/$w/ holds more than SKILL.md: $extra(resources live in $src_root/$w/)"
        fail=1
      fi
    fi
  done

  # 1b. And the reverse: no Claude copy without a source.
  for f in "$dst_root"/* "$dst_root"/.[!.]*; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    w="$(basename "$f")"
    if [ ! -d "$f" ] || [ -L "$f" ]; then
      echo "STRAY: $f is not a skill folder"
      fail=1
    elif [ ! -f "$src_root/$w/SKILL.md" ]; then
      echo "ORPHAN COPY: $dst_root/$w/ has no source $src_root/$w/SKILL.md"
      fail=1
    fi
  done

  # 2. Resources a body points at must exist inside the pack. A body that
  # references .agents/skills/polish/RULES.md describes the file as it will be
  # AFTER install, so the same relative path must resolve here. The Claude
  # copies are read too: they are what Claude Code loads.
  for body in "$src_root"/*/SKILL.md "$dst_root"/*/SKILL.md; do
    [ -f "$body" ] || continue
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      if [ ! -e "$pack/$ref" ]; then
        echo "MISSING RESOURCE: $body references $ref, which is not in pack '$name'"
        fail=1
      fi
    done < <(grep -ohE '\.agents/skills/[A-Za-z0-9._-]+/[A-Za-z0-9._/-]+' "$body" | sort -u || true)
  done

  # 3. Both CLIs load every Markdown file in a source folder (the Claude copy
  # is byte-identical), so each must pass the own-CLI rule.
  shared=()
  while IFS= read -r f; do
    if [ -n "$f" ]; then shared+=("$f"); fi
  done < <(find "$src_root" -name '*.md' -type f | LC_ALL=C sort)
  if [ "${#shared[@]}" -gt 0 ]; then
    own="$(own_cli_rule "${shared[@]}")"
    if [ -n "$own" ]; then
      printf '%s\n' "$own"
      echo "OWN-CLI DRIFT: pack '$name': a shared body may run codex exec only under **In Claude Code:** and claude -p only under **In Codex:**, after a \"Which CLI am I running in\" line (findings above)"
      fail=1
    fi
  fi
done

if [ "$packs" -eq 0 ]; then
  echo "NO PACKS: packs/ is empty"
  fail=1
fi

# 4. The retired-command map and the known shipped hashes in install.sh.
# Read each table from between its markers, one quoted entry per line.
installer_table() {
  sed -n "/^# BEGIN $1\$/,/^# END $1\$/p" install.sh |
    sed -n 's/^  "\(.*\)"$/\1/p' | LC_ALL=C sort
}
if command -v sha256sum >/dev/null 2>&1; then
  digest() { sha256sum | awk '{print $1}'; }
else
  digest() { shasum -a 256 | awk '{print $1}'; }
fi
map="$(installer_table 'RETIRED COMMANDS')"
known="$(installer_table 'KNOWN COMMAND HASHES')"
[ -n "$map" ] || { echo "RETIRED MAP: install.sh has no RETIRED COMMANDS table"; fail=1; }
[ -n "$known" ] || { echo "KNOWN HASHES: install.sh has no KNOWN COMMAND HASHES table"; fail=1; }
tags="$(git tag --list 'v*' --sort=v:refname 2>/dev/null || true)"
if [ -z "$tags" ]; then
  echo "KNOWN HASHES: no release tags here; run git fetch --tags (the check regenerates the hashes from them)"
  fail=1
else
  # Every command file any release tag shipped: "<pack> <path> <sha256> <tag>".
  shipped=""
  for tag in $tags; do
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      rest="${path#packs/}"
      p="${rest%%/*}"
      rel="${rest#*/}"
      h="$(git show "$tag:$path" | digest)"
      shipped="$shipped$p $rel $h $tag"$'\n'
    done < <(git ls-tree -r --name-only "$tag" -- packs | grep -E '^packs/[^/]+/\.claude/commands/[^/]+$' || true)
  done
  # Group the tags per (path, hash) in release order, as the table writes them.
  expected_known="$(printf '%s' "$shipped" | awk '
    NF == 4 { k = $2 " " $3; if (!(k in tags)) { order[++n] = k; tags[k] = $4 } else tags[k] = tags[k] "," $4 }
    END { for (i = 1; i <= n; i++) print order[i] " " tags[order[i]] }' | LC_ALL=C sort)"
  if [ "$known" != "$expected_known" ]; then
    echo "KNOWN HASHES: install.sh KNOWN COMMAND HASHES differs from what the release tags shipped."
    diff <(printf '%s\n' "$known") <(printf '%s\n' "$expected_known") | sed 's/^/  /' || true
    echo "  Regenerated from the tags (paste these entries between the markers):"
    printf '%s\n' "$expected_known" | sed 's/^/    "/; s/$/"/'
    fail=1
  fi
  # Each shipped command maps to its own pack and to the skill copy that
  # replaced it; the map holds nothing else.
  expected_map="$(printf '%s' "$shipped" | awk 'NF == 4 { print $1, $2 }' | LC_ALL=C sort -u |
    while read -r p rel; do
      n="${rel#.claude/commands/}"
      printf '%s %s .claude/skills/%s/SKILL.md\n' "$p" "$rel" "${n%.md}"
    done | LC_ALL=C sort)"
  if [ "$map" != "$expected_map" ]; then
    echo "RETIRED MAP: install.sh RETIRED COMMANDS must map exactly the commands the release tags shipped:"
    diff <(printf '%s\n' "$map") <(printf '%s\n' "$expected_map") | sed 's/^/  /' || true
    fail=1
  fi
  while read -r p rel new; do
    [ -n "$p" ] || continue
    if [ ! -f "packs/$p/$new" ]; then
      echo "RETIRED MAP: $rel in pack '$p' maps to $new, which pack '$p' does not ship"
      fail=1
    fi
  done <<<"$map"
fi

if [ "$fail" -eq 0 ]; then
  echo "packs OK: $packs pack(s), $copies byte-identical Claude copies, resources present, no own-CLI calls, $(printf '%s\n' "$map" | wc -l | tr -d ' ') retired commands mapped with $(printf '%s\n' "$known" | wc -l | tr -d ' ') known shipped hashes"
fi
exit "$fail"
