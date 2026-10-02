# reports

One file per question answered. The agent writes here without asking.

Everything here except this README and `_template/` is gitignored. A report carries your
real numbers, so it stays on this machine. To keep reports in git, see the note at the
top of the workspace block in `.gitignore`.

## Naming

`reports/YYYY-MM-DD-<topic>.md`

- The date is the date the analysis ran, not the date range it covers. UTC.
- `<topic>` is lowercase, hyphen separated, and names the question, not the method.
- Good: `2026-02-14-second-carrier-week4-retention.md`
- Bad: `2026-02-14-analysis.md`, `2026-02-14-sql-results.md`, `Feb14Retention.md`

Rerunning the same question on a later date makes a new file. Do not overwrite an old
report. A superseded report stays, and the new one links back to it, because a PM who
quoted the old number needs to find out it moved.

`_template/report.md` is the contract. Copy it, do not edit it in place.

## The contract

Two shapes, exact heading names either way.

**Short form**, the default for a single-source question: Question, Facts, Exclusions
applied, Interpretation.

**Full form**, for a question that crosses sources, spans time periods, or feeds a
decision that matters: the four above plus Sources, Time range, Filters, Confidence and
gaps, Recommended next check.

Under Facts, every number carries the query that produced it and a row count. That is
C-05, not a preference. And every report states which exclusions from
`knowledge-base/entities.md` were applied, in both shapes. Those two things are the
contract. The rest is shape, and picking the shape the question deserves is part of
answering it.

## check-output.sh is a lint, not a gate

Before a report goes to the PM:

```
./evals/check-output.sh reports/2026-02-14-my-topic.md
```

It prints what it noticed and exits 0 anyway, including when it found something. You
decide whether a finding matters for your question. `--strict` makes findings exit 1,
which is what you want in CI.

The script checks structure only: sections present, dates absolute, exclusions stated,
queries attached, no secrets. It cannot tell you whether the analysis is sound. **A
clean run establishes almost nothing.** A report that names five exclusion rules in
prose and applies none of them to its queries passes every check in here. The judgment
half is the Evaluator role in `agents/roles.md`, and that is the half that catches a
confidently wrong number.

Run the script yourself when you receive a report. Then read the report anyway.
