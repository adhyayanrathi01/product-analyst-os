# Skills

`CHARTER.md` outranks the root `AGENTS.md`, which outranks this file, which outranks any
single skill.

## Picking one

- Add or configure a source: `setup/connect-sources`
- Prove a source is readable: `setup/verify-sources`
- Record a schema the first time: `schema/capture-schema`
- Check whether a schema changed: `schema/refresh-schema`
- What users did: `analytics/analyze-frontend`
- Accounts, users, revenue: `analytics/analyze-backend`

Order matters. Connect, verify, capture, then analyze. A skill that needs an earlier one
to have run says so and stops.

## The CORE fence

Every `SKILL.md` fences `## Contract` and `## Output contract` between
`<!-- CORE:BEGIN -->` and `<!-- CORE:END -->`. Inside is what the skill promises: a human
specification, never edited by an analysis task or a self-improvement pass, per **C-12**.

`## Process` and `## Failure modes` sit outside the fence and are the improvement
surface. A change there that breaks a promise inside the fence is the wrong change. Each
failure-mode entry names a real failure and the check that catches it. Generic risk
language is a defect.

## Before delivering

Read the skill's **Required fields** and confirm every one is present in the output, by
name. A missing required field is an incomplete output, not a style choice. Then run
`evals/check-output.sh` where the output is a report.
