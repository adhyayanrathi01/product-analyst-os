---
paths:
  - "reports/**/*.md"
---
<!-- Restates AGENTS.md "Every number carries its query" and CHARTER C-03, C-05, C-10, plus reports/README.md. If this ever disagrees with AGENTS.md or CHARTER.md, they win. -->

# Working in reports/

- File name is `reports/YYYY-MM-DD-<topic>.md`. The date is the day the analysis ran, in UTC. The topic names the question, not the method.
- Copy `_template/report.md`. Do not edit the template in place. A rerun on a later date is a new file that links back to the old one. Never overwrite a report.
- Pick a shape. Short form is the default for one source: Question, Facts, Exclusions applied, Interpretation. Full form adds Sources, Time range, Filters, Confidence and gaps, Recommended next check.
- Heading names are literal. `evals/check-output.sh` greps for them.
- Every number carries its query, source, absolute date range with timezone, filters and row count. Resolve "last 30 days" to real dates.
- Name the exclusion rules applied, by id. When a rule moves the answer, show both numbers.
- Facts, Interpretation and the next check stay in separate sections. A reader must be able to reject your interpretation and keep your facts.
- Never state a cause from a correlation. Name the confounder you did not rule out.
- Recommend a check to run, not a product action. The PM decides what to build.
- If a number came from a dashboard tile, say so and name the tile.
- A clean lint run proves structure only. Read the report anyway.
