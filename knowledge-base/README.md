# knowledge-base

Five files. They hold the definitions the agent is not allowed to invent.

Everything here ships blank, as a template. The worked examples describe a fictional
company called **Nimbus Freight**, which does not exist. They are labelled `EXAMPLE`.
Delete them as you fill each file in. An example left in place will be read as a fact.

---

## The agent reads these. It never writes them.

`AGENTS.md` and `CHARTER.md` C-10 make this binding, and
`.claude/hooks/guard.py` enforces it in the Claude Code harness.

When the agent believes a definition here is wrong, missing, or contradicted by the
data, it does three things and then stops:

1. Says which file and which section.
2. Shows the exact proposed diff.
3. Waits for you.

It does not edit, and it does not route around the rule by writing the definition
into a report and using it anyway. If you see a report using a definition that is not
in this folder, that is a defect.

---

## Fill them in this order

**1. `entities.md`. This one blocks everything.**

Until the grain, the active definition, and the exclusion rules exist, every number
the agent produces is unfiltered and counted at an unknown unit. That is worse than
no number, because it looks like an answer. Expect this file to take an afternoon and
two arguments.

**2. `company.md`.** Short. It stops the agent asking you what the product is.

**3. `personas.md`.** Needs `entities.md` first, because a persona is identified by a
predicate at a grain.

**4. `metrics.md`.** Needs `entities.md` and `personas.md`. Every metric inherits the
grain, the window, and the exclusions.

**5. `glossary.md`.** Fill as you go. The row that earns its keep is the one where a
word means something different here than it does everywhere else.

---

## What "done" looks like

- No `TODO` left in `entities.md` sections 1 through 4.
- No `EXAMPLE` block left in any file you have filled in.
- Every exclusion rule in `entities.md` is a literal predicate, not a description.
- Every persona has an identifying predicate, or an honest `NOT IDENTIFIABLE`.
- Every metric names its source and its owner.

Section 5 of `entities.md`, the lifecycle edge cases, can stay partly `TODO`. Fill a
row the first time a case actually happens. Record the date in the change log.

---

## Keeping them true

These files decay. A new internal domain, a renamed event, a settled argument that
nobody wrote down.

- When the agent hits a case with no rule, it stops and asks. Answer by editing the
  file, not by answering in chat. The chat answer is gone next session.
- Log every edit in the `entities.md` change log, including which past reports the
  edit invalidates.
- Reread `metrics.md` whenever a number in a report surprises you. The surprise is
  usually a definition, not a finding.
