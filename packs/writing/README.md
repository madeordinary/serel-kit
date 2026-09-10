# Writing pack

One workflow: `/polish` in Claude Code, `$polish` in Codex. It rewrites prose
you name to a set of house rules and shows you the diff.

## What it does

- Reads `RULES.md` — 16 rules about plain words, concrete facts, one idea per
  sentence, evidence instead of adjectives, and the phrasings that make text
  read like it was generated.
- Reads the text you named: a file, a file plus a heading, or something you
  paste.
- Prints a unified diff, a line per change citing the rule it came from, and a
  list of what it deliberately left alone.

## What it never does

- **It never writes.** The workflow ends at the diff. Applying it is a
  separate thing you ask for.
- **It never adds a claim.** No new numbers, names, or certainty that was not
  in the source.
- **It never drops a qualification.** "on macOS only", "we think", "not yet
  measured" survive the rewrite, along with open questions, decision status
  and supersession links, evidence pointers, and everything inside a code
  fence.
- **It never reflows a memory bank file's structure.** `## Recent changes`
  headings, `## Recent milestones`, and `Older entries:` pointer lines are
  load-bearing for Serel Memory's retention step, so they are left as-is.
- **It does not review your work.** It changes how a claim reads, never
  whether the claim is true.

## Install

Serel Memory is not required for this pack.

```bash
bash /path/to/serel-kit/install.sh /path/to/your-repo --packs writing
```

Installs four files:

```text
.claude/commands/polish.md
.agents/skills/polish/SKILL.md
.agents/skills/polish/agents/openai.yaml
.agents/skills/polish/RULES.md
```

`RULES.md` is yours after install. Edit it. The rules that survive contact
with your project are the ones worth keeping.

## Acceptance exercise

Automated tests prove the pack installs and that both adapters are present and
paired. They cannot prove the workflow behaves the same way in both CLIs — a
person has to check that. Run this once per CLI in a fresh session.

Put this in `/tmp/polish-demo.md` first:

```text
# Sync status

It is worth noting that we have leveraged a comprehensive new approach to the
synchronization layer in order to significantly improve reliability, and the
initial results have been quite promising. There are a few edge cases that we
may want to consider addressing, and the retry logic (which currently only
works on Linux) should probably be revisited at some point. Open question: do
we keep the 30 second timeout?
```

### In Claude Code

Type `/polish /tmp/polish-demo.md`.

Expect:

- A first line shaped `POLISH: /tmp/polish-demo.md — <n> change(s)`.
- A unified diff, not a retyped copy of the file.
- A `WHY:` block citing rule numbers.
- A `KEPT:` block that mentions the open question about the 30 second timeout
  and the "only works on Linux" qualification — both must still be in the
  rewritten text.
- A final line: `Nothing was written.`

Afterwards: `/tmp/polish-demo.md` is byte-for-byte unchanged, and no new file
exists. Check with `git status` if the file is in a repo.

### In Codex

Type `$polish /tmp/polish-demo.md`.

Expect the same five things, with `-` instead of the em dash in the first
line. Same result on disk: nothing written.

### It failed if

- Any file changed on disk.
- The rewrite dropped the open question, the Linux qualification, or turned
  "quite promising" into a claim that it works.
- The reply is a rewritten file body instead of a diff.
- It asked "want me to apply this?" — the workflow is supposed to stop.

## Relationship to Serel Memory

Serel Memory owns bank structure, lifecycle, and compatibility. This pack is
an optional workflow that follows those contracts: it reads the retention
rules in `docs/workflow-contract.md` before touching a bank file, and it
writes nothing at all.
