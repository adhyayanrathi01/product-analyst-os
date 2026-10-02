# <one-line question, as the PM asked it>

Copy this file to `reports/YYYY-MM-DD-<topic>.md` and fill it in. Delete the guidance
lines as you go.

## Two shapes. Pick one.

**Short form** is the default for a single-source question. Four headings:

Question, Facts, Exclusions applied, Interpretation.

**Full form** is for a question that crosses sources, spans time periods, or feeds a
decision the reader has said matters. Nine headings, the four above plus:

Sources, Time range, Filters, Confidence and gaps, Recommended next check.

Heading names are fixed either way, because `./evals/check-output.sh` greps for them
literally. Run it before delivering. It is a lint, not a gate: it tells you what it
noticed and exits 0 anyway, so read the findings and decide. `--strict` makes findings
exit 1, for CI.

**One thing is not optional in either shape.** Read `knowledge-base/entities.md` before
you query, and state which exclusions you applied. That is the one step whose omission
silently corrupts every number in the report.

A short-form example is at the bottom of this file, after the full-form one. Do not
reach for the full form to look thorough. A four-heading answer to a one-source question
is the right answer, and padding it buries the number.

---

## The full form, heading by heading

## Question

The question, restated in one or two sentences, plus the decision it feeds.

- Good: "Do accounts that connect a second carrier in week 1 retain to week 4 better
  than accounts that connect one? Feeds the Q2 onboarding roadmap call."
- Bad: "Retention analysis."

## Sources

One line per source: name, what was read, and its readiness state from
`sources/sources.md`. A source marked partial or blocked is named as such here.

- Good: "PostHog, project 4412, events `shipment_created` and `carrier_connected`.
  Ready. / Postgres read replica, `public.accounts`. Ready. / Zendesk. Blocked, no
  read scope, so ticket volume is not in this report."
- Bad: "Our data warehouse."

## Time range

Absolute dates with a timezone. Both ends. Resolve every relative phrase before you
write it here.

- Good: "2026-01-05 00:00:00 UTC to 2026-02-01 23:59:59 UTC, inclusive."
- Good: "Cohort window 2025-11-01 to 2025-11-30 UTC. Outcome window runs to
  2025-12-28 UTC, 28 days after the last cohort day."
- Bad: any phrase naming a period relative to today rather than a date. C-05 requires
  absolute dates, and `check-output.sh` flags them. The exact phrases it looks for are
  listed at the bottom of this template.

If the window is not the same for every number, say so here and repeat the window
next to each number in Facts.

## Filters

Every `WHERE` clause that is not an exclusion rule. Segment, plan, geography, event
property, anything that narrows the population.

- Good: "`accounts.plan_type IN ('team','enterprise')`. Grain: account, per
  `entities.md` section 1. Plan measured at window end."
- Bad: "Paid customers only."

State the grain here even when it is the default. A reader should not have to infer
which level from `entities.md` section 1 a number counts.

## Exclusions applied

List the rule ids from `knowledge-base/entities.md` section 3 that you applied, with
the effect where it is material. C-10 makes this mandatory.

- Good: "E-1 internal domains, E-2 internal account ids, E-4 demo, E-5 non-production,
  E-7 bots. Applied. E-6 test-name heuristic not applied, it is unconfirmed and it
  moves the count by 140. Both numbers are in Facts. Unfiltered signups 12,400,
  after exclusions 9,850."
- Bad: the single word "none". If you genuinely applied no exclusion rules, say so and
  give the reason in the same sentence: "No exclusion rules applied, because this is a
  raw table count used to size a backfill, not a product number."

## Facts

Only what a query returned. No interpretation. C-04: nothing invented, and C-05:
every number carries its query.

Each fact is a number, then the query that produced it in a fenced code block, then
the row count.

- Good:

  Accounts connecting a second carrier in week 1: **312**. Row count: 312.

  ```sql
  -- The GROUP BY produces one row per qualifying account, so it must be
  -- wrapped to return a single count. Reporting the inner query's row count
  -- as the answer works by accident and breaks the moment a filter changes.
  SELECT COUNT(*) AS accounts
  FROM (
    SELECT a.id
    FROM accounts a
    JOIN integrations i ON i.account_id = a.id
    WHERE i.connected_at < a.created_at + INTERVAL '7 days'
      AND a.created_at >= '2025-11-01' AND a.created_at < '2025-12-01'
      AND a.is_internal IS NOT TRUE
      AND a.account_type <> 'demo'
    GROUP BY a.id
    HAVING COUNT(DISTINCT i.carrier_id) >= 2
  ) t
  LIMIT 10000;
  ```

- Bad: "Roughly 300 accounts connected a second carrier, which is up a lot."
  No query, a rounded number, and "up a lot" is interpretation.

If a number came from a dashboard tile rather than a query you ran, say so and name
the tile. It is still a fact, but a fact of a different kind.

## Interpretation

What you think the facts mean. Kept separate so a reader can accept the facts and
reject this. C-03.

- Good: "The 22-point retention gap tracks with account size, not with the second
  connection. Accounts connecting two carriers have a median 14 seats against 3.
  Seat count is the confounder I did not rule out."
- Bad: "Connecting a second carrier drives retention." That states a cause. C-03
  forbids it unless you ran something that can establish one, and a cohort split
  cannot.

## Confidence and gaps

What is shaky, what is missing, and what would change the conclusion.

- Good: "Medium confidence. Two gaps. First, E-7 drops API-only accounts, roughly 8%
  of the population, and they are not random. Second, `properties.origin` did not
  exist before 2025-06-11, so nothing here extends earlier. The conclusion flips if
  the seat-count gap disappears when you match accounts on seats."
- Bad: "Data looks clean." Say what you checked.

## Recommended next check

One query or one experiment, specific enough to run. Not a roadmap.

- Good: "Rerun the split matched on seat-count decile. If the retention gap holds
  inside deciles, the connection is doing work. One query against the same two
  sources, no new access needed."
- Bad: "Investigate further."

---

## Worked example, full form

Everything below is an EXAMPLE for a fictional company called Nimbus Freight, which
does not exist. It is short on purpose. A real report carries more facts.

````markdown
# Did signups drop in January 2026?

## Question
Did new account signups fall in January 2026 versus December 2025? Feeds the
decision on whether to renew the comparison-site ad spend.

## Sources
Postgres read replica, `public.accounts`. Ready per `sources/sources.md`.

## Time range
2025-12-01 00:00:00 UTC to 2026-01-31 23:59:59 UTC, inclusive. Two calendar months,
compared whole.

## Filters
Grain: account, per `entities.md` section 1. No plan or geography filter. Signup date
is `accounts.created_at`.

## Exclusions applied
E-1 internal domains, E-2 internal account ids, E-3 internal flag, E-4 demo.
E-6 test-name heuristic not applied, it is unconfirmed. Applying it would remove a
further 41 accounts across both months and does not change the direction.

## Facts
December 2025 signups: **1,204**. Row count: 1.

```sql
SELECT COUNT(*) FROM accounts
WHERE created_at >= '2025-12-01' AND created_at < '2026-01-01'
  AND email NOT ILIKE '%@nimbusfreight.example'
  AND id NOT IN (1,2,7,41,903)
  AND is_internal IS NOT TRUE
  AND account_type <> 'demo'
LIMIT 10;
```

January 2026 signups: **1,131**. Row count: 1. Same query, window moved to
`>= '2026-01-01' AND < '2026-02-01'`.

Unfiltered counts for the same windows, for comparison: 1,502 and 1,410.

## Interpretation
Signups fell 6.1%. Both months have 31 days, so this is not a day-count effect. It
sits inside the month-to-month spread seen across 2025, which was 5.8%. I would not
read a trend from two points.

## Confidence and gaps
Medium. One gap: `accounts.created_at` records the row insert, not the moment the
user submitted the form, and a 2025-09 backfill inserted 88 rows out of order. Those
rows land in December, not January, so if anything December is overstated. The
conclusion flips if the ad-attribution source shows the drop concentrated in paid
signups, which this query cannot see.

## Recommended next check
Split the same two months by `accounts.signup_source`. One query, same source. If
paid signups are flat and organic fell, the ad spend is not the thing to cut.
````

---

## Worked example, short form

Same fictional company. Same rigor, one source, no decision riding on it. This is what
most questions should look like. Four headings, no padding, and the exclusions and the
query are still there because those are what make the number checkable.

````markdown
# How many accounts signed up in January 2026?

## Question
New accounts created in January 2026. Grain: account, `accounts.id`, per
`entities.md` section 1.

## Facts
January 2026 signups: **1,131 accounts**. Row count: 1.

```sql
SELECT COUNT(*) AS accounts FROM accounts
WHERE created_at >= TIMESTAMP '2026-01-01 00:00:00+00'
  AND created_at <  TIMESTAMP '2026-02-01 00:00:00+00'
  AND is_internal IS NOT TRUE          -- E-3
  AND account_type <> 'demo'           -- E-4
  AND deleted_at IS NULL               -- E-9
LIMIT 10;
```

Unfiltered, the same window returns 1,410 accounts.

## Exclusions applied
E-3 internal flag, E-4 demo, E-9 soft delete. E-1 and E-2 are `users`-grain and
account-id rules that remove nothing from this window, and are not in the clause.
E-6 not applied, it is unconfirmed, and it would remove a further 19 accounts.
`postgres-replica` is `blocked` in `sources/sources.md`, so nobody has verified this
source through a bounded read.

## Interpretation
Down 6.1% on December's 1,204. That sits inside the 2025 month-to-month spread, so I
would not read a trend from two points.
````

Note what is still in there: the query, the exclusion ids, the unfiltered comparison,
absolute dates with an offset, and the readiness caveat in one line. What is gone is
five headings that would have repeated those same facts in other words.

---

## Relative-date phrases the checker flags in Time range

Resolve each one to absolute dates before writing it: the phrases meaning the
previous 30 days, the previous week, the previous month, "recently", and
year-to-date. They are ambiguous the moment the report is read on a different day.
