# S-1. Active accounts, August versus July. Happy path.

Skill under test: `skills/analytics/analyze-backend`.

## Prompt given to the agent

> How many active accounts did we have in August 2026, and how does that compare to July?

## Fixture

- Knowledge base: `evals/fixtures/nimbus/knowledge-base/`
- Schema: `evals/fixtures/nimbus/schema/postgres-replica.md`, `evals/fixtures/nimbus/schema/posthog.md`
- Data: `evals/fixtures/nimbus/data.md`, queries Q-1, Q-2, Q-3, Q-3b, Q-3c
- Source readiness: the fixture registry inside `data.md`, not `sources/sources.md`

## What this scenario is testing

The path with no trap in the data, so the failure surface is the skill itself. It should
exercise: reading `entities.md` first, declaring account grain before counting, applying
the `confirmed` exclusion rules and citing them by id, holding back `unconfirmed` E-6 and
disclosing what it would change, using the **confirmed** `account_id` join rather than
refusing everything reflexively, and the cross-check in Process step 8.

It also carries the fixture's genuine ambiguity: "active in August" has no settled
mapping onto the rolling 28-day `active_28d_core` definition, and `metrics.md` records
that as an open dispute. A single number here is a wrong answer regardless of its value.

## Pass criteria

1. Grain declared as account before any number appears.
2. Both the rolling and the calendar-month readings reported and labelled. Neither
   presented as the answer.
3. E-1, E-2, E-3, E-4, E-5, E-7, E-8, E-9 applied and cited by id, in every query, not
   only the first.
4. E-6 named, not applied, with its effect quantified.
5. Unfiltered numbers shown alongside filtered ones, because the exclusions move the
   growth rate from 13.1% to 5.2%.
6. The `account_id` join quoted from `entities.md` section 4 with its cardinality.
7. A cross-check that a reader can verify, and it reconciles.
8. Client-side undercount named.
9. `./evals/check-output.sh` exits 0.

## Result

Report: `2026-09-09-active-accounts-august-vs-july.md`, reproduced in
`evals/results/2026-09-09-dry-run/RESULTS.md`.

Answer produced: 2,554 accounts on the calendar-month reading, 2,428 in July, plus 5.2%.
2,462 and 2,344 on the rolling reading, plus 5.0%.

All nine pass criteria met. `check-output.sh` exit 0, 5 passed, 0 failed, 0 warnings.

Two things the skill did not cover and the run had to improvise. Both are written up in
RESULTS.md: how to apply a `users`-level exclusion predicate to an account-grain count,
and what to do when the fixture's own E-8 predicate contradicts its stated intent.
