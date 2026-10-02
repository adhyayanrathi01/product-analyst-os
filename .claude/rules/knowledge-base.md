---
paths:
  - "knowledge-base/**/*.md"
---
<!-- Restates AGENTS.md "What you may write" and "Handle exclusions honestly", plus knowledge-base/README.md. If this ever disagrees with AGENTS.md or CHARTER.md, they win. -->

# Working in knowledge-base/

- This directory is the user's. Do not edit it. If a definition looks wrong or missing, name the file and section, show the exact proposed diff, and wait.
- Do not route around that by using the definition in a report anyway. A report using a definition that is not in this folder is a defect.
- A denied write here is the protection working. Report which file refused and stop. Do not `chmod`, use `sudo`, or set `PAOS_ALLOW_PROTECTED=1`.
- Apply every `confirmed` exclusion rule and cite each by id.
- An `unconfirmed` rule is a heuristic. Name it, do not apply it silently, and where it moves the answer show both numbers.
- Rules are written to KEEP wanted rows, so they `AND` straight into a `WHERE` clause. Pasted into a clause that selects rows to remove, they keep exactly the rows you meant to drop, and nothing errors.
- An empty value must not drop a row. `type <> 'demo'` returns unknown for an empty `type`, so the row vanishes. Use `IS DISTINCT FROM`, or add the `IS NULL` half. Say how many values were empty when the share is meaningful.
- No rule for the case you hit, for example a new internal domain? Do not invent one. Name what is undefined, state what you assumed, and continue.
- Do not join across sources on an identifier that `entities.md` has not confirmed.
