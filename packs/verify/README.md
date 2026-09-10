# Verify pack

One workflow: `/verify-map` in Claude Code, `$verify-map` in Codex. It keeps a
file per feature in the memory bank saying how to see that feature work, and
what someone saw the last time they looked.

Requires Serel Memory in the target repo. The maps live in the bank.

## Why

Some behavior has no test. A checkout flow, a nightly job, an integration you
can only watch — the way you know it works is that a person ran it and saw the
right thing. That knowledge normally lives in one person's head and expires.

A verification map writes it down in two halves:

- **Recipe** — Launch, Drive, Observe, Clean up. How to see it work, concrete
  enough for someone who has never opened the repo.
- **Records** — what someone actually saw, with the revision, the paths, the
  environment, the observation in the words that were on screen, and a link to
  a screenshot or log.

The split is the point. The recipe is a claim about how to check. A record is a
claim that someone checked. Keeping them apart makes "nobody has verified this"
a visible, ordinary state instead of an assumption.

## What it does

- Resolves one scope and one effective bank per invocation, exactly the way
  Serel Memory's `docs/workflow-contract.md` says: `--scope <path>`, else the
  current directory, else the root; `memory-bank.local/` wins when present.
- Reads `TEMPLATE.md`, the existing map, and enough of the repo to write a
  Launch section whose commands exist.
- Shows the proposed file as a diff and waits for you to confirm.
- Writes exactly one file: `<effective bank>/verification/<feature>.md`.

## What it never does

- **It never writes anything else.** Not `activeContext.md`, not
  `progress.md`, not `.rules`, not `.serel-memory.json`. Anything the rest of
  the bank should learn goes through `/update-memory`.
- **It never writes without confirmation.** Diff first, always.
- **It never records a run it did not observe.** A record you did not watch is
  a lie with a date on it.
- **It never invents a launch command.** If it cannot find how to run the
  thing, it asks.
- **It never creates or repairs a memory bank.** An uninitialized bank stops
  the workflow, with a pointer to `/discover`, `/init-memory`, or `/from-prd`.
- **It never claims to be a test.** A map does not replace running the suite,
  and a missing map is not a product failure.

## Install

```bash
bash /path/to/serel-kit/install.sh /path/to/your-repo --packs verify
```

Without `.serel-memory.json` in the target, the installer refuses and points at
Serel Memory's install instructions. Nothing is written.

Installs four files:

```text
.claude/commands/verify-map.md
.agents/skills/verify-map/SKILL.md
.agents/skills/verify-map/agents/openai.yaml
.agents/skills/verify-map/TEMPLATE.md
```

## How reviews find these files

There is no hook into `/ship` or `/review` in v0.1, on purpose. Serel Memory
already has a convention for this: optional docs under `memory-bank/` are read
when the current task touches that topic. A map at
`memory-bank/verification/checkout.md` is exactly that — a review of the
checkout code will find it and can say "the map's newest record is three
revisions old."

If you want it enforced rather than found, that is a change to your own copy of
`/review`, which is a markdown file you already own.

## Acceptance exercise

Automated tests prove the pack installs and that both adapters are present and
paired. They cannot prove the workflow behaves the same way in both CLIs — a
person has to check that. Run this once per CLI in a fresh session, in a repo
that has Serel Memory with an initialized bank.

### In Claude Code

Type `/verify-map` with no argument.

Expect: a list of maps that already exist (none, the first time), a few
candidate features drawn from the bank, and a question about which one you
want. It must not pick one for you.

Then type `/verify-map <one of those features>`.

Expect:

- A header block naming the feature, the resolved bank path, and the file it
  proposes to write.
- The full proposed file, with Recipe and Records as separate sections.
- Launch commands that actually exist in the repo — check one against the
  project README.
- `RECORDS: none - this feature is unverified`, because you have not run it.
- A question: "Write this file?"

Answer yes. Afterwards `memory-bank/verification/<feature>.md` exists, and
`git status` shows that one new file and nothing else.

### In Codex

Type `$verify-map <the same feature>` in a fresh session.

Expect the same header block, the same two sections, and the same question
before anything is written. It should recognize the file you already have and
offer a refresh rather than a new file.

### It failed if

- It wrote before you confirmed.
- Any file other than the map changed.
- It filled in a Records entry, including a date and a "worked as expected",
  when nobody had run anything.
- Its Launch section contains a command that does not exist in the repo.
- In a repo with `scopes`, it wrote to a different bank than the one you
  selected.

## Relationship to Serel Memory

Serel Memory owns bank structure, lifecycle, and compatibility. This pack is an
optional workflow that follows those contracts: it resolves scope and the
effective bank by Memory's rule, stops on an uninitialized bank with Memory's
message, shows diffs before writing, and writes one optional doc inside the
bank it was pointed at. Serel Kit never installs, upgrades, or reconfigures
Serel Memory.
