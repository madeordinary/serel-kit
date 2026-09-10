#!/usr/bin/env bash
# Asserts that every pack ships a complete, paired set of adapters.
#
# A Serel Kit pack is a workflow plus the two native adapters that run it:
# a Claude Code slash command (.claude/commands/<name>.md) and a Codex skill
# (.agents/skills/<name>/SKILL.md + agents/openai.yaml). This mirrors Serel
# Memory's own parity rule — if one side of a pair goes missing, the pack
# silently works in one CLI only.
#
# It checks three things and nothing else:
#   1. Both adapters and the Codex manifest exist, in both directions.
#   2. Every .agents/skills/... resource an adapter references really exists
#      inside the pack (so RULES.md and TEMPLATE.md travel with the skill).
#   3. No adapter invokes its own CLI — the telltale of a copy-paste port.
#
# What it does NOT check: that the two adapters behave the same way. Only a
# person running both can tell you that. See each pack's acceptance exercise.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
packs=0
pairs=0

for dir in packs/*/; do
  pack="${dir%/}"
  name="$(basename "$pack")"
  packs=$((packs + 1))

  if [ ! -f "$pack/README.md" ]; then
    echo "MISSING README: pack '$name' has no README.md (it documents the acceptance exercise)"
    fail=1
  fi
  if [ ! -d "$pack/.claude/commands" ]; then
    echo "MALFORMED PACK: '$name' has no .claude/commands directory"
    fail=1
    continue
  fi
  if [ ! -d "$pack/.agents/skills" ]; then
    echo "MALFORMED PACK: '$name' has no .agents/skills directory"
    fail=1
    continue
  fi

  # 1a. Every Claude command has a Codex skill and manifest.
  for cmd in "$pack"/.claude/commands/*.md; do
    w="$(basename "$cmd" .md)"
    pairs=$((pairs + 1))
    if [ ! -f "$pack/.agents/skills/$w/SKILL.md" ]; then
      echo "MISSING SKILL: /$w in pack '$name' has no .agents/skills/$w/SKILL.md"
      fail=1
    fi
    if [ ! -f "$pack/.agents/skills/$w/agents/openai.yaml" ]; then
      echo "MISSING MANIFEST: \$$w in pack '$name' has no agents/openai.yaml"
      fail=1
    fi
  done

  # 1b. And the reverse: no orphan skills.
  for skill in "$pack"/.agents/skills/*/; do
    w="$(basename "${skill%/}")"
    if [ ! -f "$pack/.claude/commands/$w.md" ]; then
      echo "MISSING COMMAND: \$$w in pack '$name' has no .claude/commands/$w.md"
      fail=1
    fi
  done

  # 2. Resources an adapter points at must exist inside the pack. A command
  # that references .agents/skills/polish/RULES.md is describing the file as
  # it will be AFTER install, so the same relative path must resolve here.
  for adapter in "$pack"/.claude/commands/*.md "$pack"/.agents/skills/*/SKILL.md; do
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      if [ ! -e "$pack/$ref" ]; then
        echo "MISSING RESOURCE: $adapter references $ref, which is not in pack '$name'"
        fail=1
      fi
    done < <(grep -ohE '\.agents/skills/[A-Za-z0-9._-]+/[A-Za-z0-9._/-]+' "$adapter" | sort -u || true)
  done

  # 3. Each adapter speaks its own CLI's idiom. A Claude command that shells
  # out to Claude, or a Codex skill that shells out to Codex, is a port that
  # was never finished.
  for cmd in "$pack"/.claude/commands/*.md; do
    if grep -q 'claude -p' "$cmd"; then
      echo "OWN-CLI CALL: $cmd invokes Claude from inside a Claude command"
      fail=1
    fi
  done
  for skill in "$pack"/.agents/skills/*/SKILL.md; do
    if grep -q 'codex exec' "$skill"; then
      echo "OWN-CLI CALL: $skill invokes Codex from inside a Codex skill"
      fail=1
    fi
  done
done

if [ "$packs" -eq 0 ]; then
  echo "NO PACKS: packs/ is empty"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "packs OK: $packs pack(s), $pairs command <-> skill pair(s), resources present, no own-CLI calls"
fi
exit "$fail"
