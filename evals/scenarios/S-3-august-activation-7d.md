# S-3. 7-day activation. The blocked path.

Skill under test: `skills/analytics/analyze-frontend`.

## Prompt given to the agent

> What percentage of users who signed up in August activated within 7 days?

## Fixture

- Knowledge base: `evals/fixtures/nimbus/knowledge-base/`
- Schema: `evals/fixtures/nimbus/schema/posthog.md`, `evals/fixtures/nimbus/schema/postgres-replica.md`
- Data: `evals/fixtures/nimbus/data.md`, queries Q-10 through Q-14
- Source readiness: the fixture registry inside `data.md`

## What this scenario is testing

The question is at **user** grain and spans two sources. The signup is a Postgres
`users` row. The activation is a PostHog `shipment_created` event keyed by `distinct_id`.
Producing one percentage requires joining `distinct_id` to `users.id`.

`entities.md` section 4 lists that pair under **Unconfirmed, do not join**: 61% resolution
on a 5,000-row sample, the unresolved 39% skewed to mobile and enterprise, no merge table.
C-11 forbids the join outright, not merely as approximate.

The correct behaviour is a refusal that is still useful. `accounts.id` to
`events.properties.account_id` **is** confirmed, so the underlying decision question is
answerable at account grain. A refusal that produces nothing is as much a failure as a
silent join.

Three secondary traps ride along:

- **Exclusion reversal.** Unfiltered, activation reads 30.9%. Filtered, 51.5%. The
  exclusions nearly double the answer instead of shaving it, because 1,102 of the 2,401
  unfiltered cohort are demo accounts that never create a shipment. An agent that skips
  E-4 reports an onboarding emergency that did not happen.
- **Cohort truncation.** PostHog data stops at 2026-09-01, so 148 accounts created from
  2026-08-26 have not had seven days. Including them drags 55.7% down to 51.5%.
- **No server-side equivalent.** `schema/postgres-replica.md` has no `shipments` table, so
  the client-side count cannot be validated and is a floor, per the skill's first listed
  failure mode. Q-14 returns NOT AVAILABLE, and inventing a number there is a C-04 breach.

## Pass criteria

1. The join is refused, explicitly, citing C-11 and quoting `entities.md` section 4.
2. The refusal appears before any number, not buried in Confidence and gaps.
3. Two unjoined side numbers reported, labelled `users` and `distinct_ids`, with a
   sentence saying they were not joined and why.
4. Event volume never reported as user count. `88,417 events` and `4,206 distinct_ids`
   stay distinct.
5. An account-grain answer produced using the confirmed key, and the grain shift stated
   as a shift.
6. What the account-grain number cannot tell you, said plainly.
7. Funnel shape declared before the rate: ordered steps, order enforced, 7-day
   attribution window, truncation handled.
8. Truncated and untruncated rates both reported.
9. Unfiltered rate reported alongside the filtered one.
10. Client-side undercount named, and Q-14 reported as unavailable rather than filled in.
11. `./evals/check-output.sh` exits 0.

## Result

Report: `2026-09-09-august-activation-7d.md`, reproduced in
`evals/results/2026-09-09-dry-run/RESULTS.md`.

**The refusal happened.** The report opens by declining the per-user rate, names C-11 and
the 61% resolution figure, and never derives a percentage across the two unjoined numbers.

The output stayed useful. 55.7% of accounts signing up in the first 25 days of August
created a shipment within 7 days, computed on the confirmed `account_id` key, with the
grain shift stated and its cost named: account-grain activation cannot distinguish a
fully adopted account from one where a single coordinator does everything.

All eleven pass criteria met. `check-output.sh` exit 0, 5 passed, 0 failed, 0 warnings.

Two places the skill was silent and the run improvised, both written up in RESULTS.md:
nothing in `analyze-frontend` tells the agent it may answer at a different grain than the
one asked for, and nothing tells it where in the report the refusal belongs.
