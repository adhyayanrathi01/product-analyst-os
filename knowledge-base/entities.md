# Entities

**Status: TEMPLATE. Nothing below is a fact about your product. Fill it in.**

Every row marked `EXAMPLE` describes a fictional company called **Nimbus Freight**, a
made-up B2B logistics SaaS. Nimbus Freight does not exist. Delete every EXAMPLE row
once you have written your own. An agent that reads an EXAMPLE row as fact will
produce a confidently wrong number.

This file blocks all analysis. `AGENTS.md` tells the agent to read it before any
query. If a section here is still `TODO`, the agent stops and asks instead of
guessing.

---

## 1. Grain

**Pick one. Write it as a sentence. Do not leave both.**

The grain is the thing you count one of. Getting it wrong does not throw an error.
It silently returns a number that is off by the average number of users per account.

| Field | Your answer |
|---|---|
| Primary grain | `TODO: account` or `TODO: user`. Pick one. |
| The id column that expresses it | `TODO` |
| Where that column lives | `TODO: source and table` |
| When the other grain is allowed | `TODO: name the cases, or write "never"` |
| How to roll the other grain up | `TODO: the exact aggregation` |

*EXAMPLE (fictional Nimbus Freight):*

| Field | Answer |
|---|---|
| Primary grain | Account. Nimbus sells one contract per shipping company. A count of "customers" is a count of accounts. |
| The id column that expresses it | `account_id` |
| Where that column lives | Postgres, `public.accounts.id` |
| When the other grain is allowed | Seat adoption and feature-usage questions only, and the report says "user grain" in the Filters section. |
| How to roll the other grain up | `COUNT(DISTINCT account_id)`, never `COUNT(*)` on a user-level table. |

**Why this matters:** a 40-seat account counted at user grain contributes 40 to a
number a PM will read as 40 customers.

### Both shapes

If you genuinely sell to both businesses and individuals, do not answer "both" here.
Write two grains with a rule that assigns every row to exactly one, then say which
grain each metric in `metrics.md` uses.

| Field | Your answer |
|---|---|
| Rule that assigns a row to the B2B grain | `TODO` |
| Rule that assigns a row to the B2C grain | `TODO` |
| Rows matching neither rule | `TODO: how to treat them, and roughly how many there are` |
| Rows matching both rules | `TODO: which rule wins` |

*EXAMPLE:* a row belongs to the B2B grain when `accounts.plan_type IN ('team','enterprise')`,
and to the B2C grain when `plan_type = 'solo'`. A solo user who later joins a team
account moves grain on the date of the join, and longitudinal metrics treat the two
periods as separate entities.

---

## 2. Active

**"Active" is not a word. It is a window plus a qualifying action. Write both.**

| Field | Your answer |
|---|---|
| Window | `TODO: exact number of days, e.g. 28` |
| Window anchor | `TODO: rolling from the query date, or calendar month` |
| Timezone the window is evaluated in | `TODO: e.g. UTC` |
| Qualifying action, as an event or column filter | `TODO` |
| Actions that explicitly do NOT qualify | `TODO` |
| Grain the definition applies to | `TODO: account or user, from section 1` |
| For account grain: how many active users make an account active | `TODO: at least one, or a threshold` |

*EXAMPLE (fictional Nimbus Freight):*

| Field | Answer |
|---|---|
| Window | 28 days |
| Window anchor | Rolling, ending at the query's end date inclusive |
| Timezone | UTC |
| Qualifying action | PostHog event `shipment_created` or `shipment_status_updated` |
| Actions that do NOT qualify | `user_signed_in`, `page_viewed`, `settings_opened`, any event where `$lib = 'posthog-python'` (backfills) |
| Grain | Account |
| Threshold | At least one qualifying event from at least one non-excluded user in the account |

**Why this matters:** at Nimbus, "active = signed in" returns roughly 2.4x the count
that "active = created or updated a shipment" returns. Both are defensible. Only one
can be in a report, and the report has to say which.

### Named variants

If more than one definition of active is in real use, name each one and say where it
is allowed. Do not let the agent pick.

| Variant name | Definition | Where it may be used | Where it may not |
|---|---|---|---|
| `TODO` | `TODO` | `TODO` | `TODO` |

*EXAMPLE:* `active_28d_core` is the definition above and is the only one allowed in
reports. `active_login_30d` exists because the billing dashboard uses it. It may be
quoted only when comparing against that dashboard, and the report must label it.

---

## 3. Exclusions

**Each rule must be mechanically applicable. A rule the agent cannot turn into a
`WHERE` clause is not a rule, it is a wish.**

C-10 requires every analysis to apply these and to state which ones it applied.

Fill one row per rule. `Rule` is the literal predicate. `Source` says which table or
event property carries the field. `Confidence` is `confirmed` or `unconfirmed`. The
agent applies confirmed rules automatically and stops to ask about unconfirmed ones.

| # | Category | Rule (literal predicate, written to KEEP wanted rows) | Source | Confidence | Notes |
|---|---|---|---|---|---|
| E-1 | Internal by email domain | `TODO` | `TODO` | `TODO` | `TODO` |
| E-2 | Internal by account id list | `TODO` | `TODO` | `TODO` | `TODO` |
| E-3 | Internal by flag | `TODO` | `TODO` | `TODO` | `TODO` |
| E-4 | Demo accounts | `TODO` | `TODO` | `TODO` | `TODO` |
| E-5 | Sandbox and staging | `TODO` | `TODO` | `TODO` | `TODO` |
| E-6 | Test accounts created by real users | `TODO` | `TODO` | `TODO` | `TODO` |
| E-7 | Bots and automated traffic | `TODO` | `TODO` | `TODO` | `TODO` |
| E-8 | Churned entities | `TODO` | `TODO` | `TODO` | `TODO` |
| E-9 | Deleted entities | `TODO` | `TODO` | `TODO` | `TODO` |
| E-10 | Free vs paid | `TODO` | `TODO` | `TODO` | `TODO` |

*EXAMPLE (fictional Nimbus Freight):*

| # | Category | Rule (literal predicate, written to KEEP wanted rows) | Source | Confidence | Notes |
|---|---|---|---|---|---|
| E-1 | Internal by email domain | `users.email NOT ILIKE '%@nimbusfreight.example'` and `NOT ILIKE '%@nimbus-qa.example'` | Postgres `public.users` | confirmed | Two domains. A third, `nimbusfreight.test`, was retired in 2025 and still has 6 rows. |
| E-2 | Internal by account id list | `accounts.id NOT IN (1, 2, 7, 41, 903)` | Postgres `public.accounts` | confirmed | Founder-owned accounts on real customer domains, so E-1 misses them. |
| E-3 | Internal by flag | `accounts.is_internal IS NOT TRUE` | Postgres `public.accounts` | confirmed | Nullable. `IS NOT TRUE` and not `= FALSE`, because NULL means "never reviewed". |
| E-4 | Demo accounts | `accounts.account_type <> 'demo'` | Postgres `public.accounts` | confirmed | Sales creates these per prospect. Roughly 300 live at any time. |
| E-5 | Sandbox and staging | `events.properties.environment = 'production'` | PostHog | confirmed | Staging writes to the same project. Property is missing on events before 2025-03-01, so treat missing as non-production before that date. |
| E-6 | Test accounts created by real users | `accounts.name !~* '^(test\|asdf\|delete me\|zzz)'` | Postgres `public.accounts` | unconfirmed | Heuristic on a free-text field. Report both numbers when it moves the answer. |
| E-7 | Bots and automated traffic | `events.properties.$lib NOT IN ('posthog-python','posthog-node')` and user agent not matching `bot\|crawler\|spider\|headless` | PostHog | confirmed | Server-side libs here are backfills and integration tests, not humans. |
| E-8 | Churned entities | `accounts.churned_at IS NULL OR accounts.churned_at > <window_end>` | Postgres `public.accounts` | confirmed | Do not drop churned accounts from historical windows. They were real then. |
| E-9 | Deleted entities | `accounts.deleted_at IS NULL` for current-state questions. For historical windows use `deleted_at IS NULL OR deleted_at > <window_end>`. | Postgres `public.accounts` | confirmed | Soft delete. Rows stay. |
| E-10 | Free vs paid | Not excluded by default. Split by `accounts.plan_type = 'free'` when the question is about revenue or retention. | Postgres `public.accounts` | confirmed | Free accounts are 61% of the account count and 0% of revenue. Mixing them flattens any revenue-adjacent metric. |

**Why this matters:** at Nimbus, applying E-1 through E-7 to a signup count drops it
from 12,400 to 9,850. A report that shows only one of those numbers is hiding a
21% swing.

### How to state exclusions in a report

Every report lists the rule ids it applied, by id, in the `Exclusions applied`
section. If it applied none, it says why in a sentence. "None" on its own fails
`evals/check-output.sh`.

### When a case has no rule

Stop. Do not invent one. Report the case, the row count it affects, and ask. A new
internal email domain is the common version of this.

---

## 4. Identity and joins

C-11 forbids inferring a join. A join runs only on an identifier listed as
`confirmed` here, with its cardinality and precedence stated.

### Confirmed identifiers

| Identifier | Links which sources | Cardinality | Source of truth | Precedence when they disagree | Verified how, and when |
|---|---|---|---|---|---|
| `TODO` | `TODO` | `TODO` | `TODO` | `TODO` | `TODO` |

*EXAMPLE (fictional Nimbus Freight):*

| Identifier | Links which sources | Cardinality | Source of truth | Precedence when they disagree | Verified how, and when |
|---|---|---|---|---|---|
| `account_id` | Postgres `accounts.id` to PostHog `events.properties.account_id` | 1 to many. One account, many events. | Postgres | Postgres wins. PostHog copies the value at event time and does not update it after an account merge. | Sampled 500 PostHog `account_id` values against Postgres on 2026-02-14. 3 orphans, all from a merged account. |
| `user_id` | Postgres `users.id` to PostHog `distinct_id` | 1 to many. One user can have several `distinct_id` values across devices before identify fires. | Postgres | Postgres wins. Resolve `distinct_id` to `user_id` through PostHog's person merge, never by string equality. | Same sample, same date. 11% of pre-identify events have no resolvable `user_id`. Those are dropped and the drop is stated. |
| `stripe_customer_id` | Postgres `accounts.stripe_customer_id` to Stripe `customer.id` | 1 to 1 | Stripe | Stripe wins on plan and amount. Postgres wins on account name and owner. | Reconciled 2026-01-30. 4 Postgres rows point at deleted Stripe customers. |

**Why this matters:** joining PostHog `distinct_id` directly to Postgres `users.id`
looks like it works, returns rows, and quietly drops every user who used two devices.

### Unconfirmed, do not join

These look joinable. They are not. Any analysis that needs one of them stops and says
what it could not join.

| Identifier pair | Why it is not confirmed | What to do instead |
|---|---|---|
| `TODO` | `TODO` | `TODO` |

*EXAMPLE (fictional Nimbus Freight):*

| Identifier pair | Why it is not confirmed | What to do instead |
|---|---|---|
| `users.email` to Zendesk `requester.email` | Users file tickets from personal addresses. A 2026-01 check matched 58% of tickets. The unmatched 42% are not random, they skew to enterprise. | Report ticket volume unjoined, at Zendesk grain, and say it cannot be attributed to accounts. |
| `accounts.name` to Salesforce `Account.Name` | Free text on both sides. Casing, suffixes, and "Inc" vs "Inc." differ. | Ask the user for a mapping table. Do not fuzzy match. |
| PostHog `$session_id` to Postgres session rows | Different definitions of a session. PostHog uses 30 minutes of inactivity, the app uses a 14-day token. | Pick one and say which. Never treat them as the same object. |

---

## 5. Lifecycle edge cases

These break longitudinal metrics quietly. Cohort counts drift, retention curves bend,
and nothing errors.

| Event | Your rule |
|---|---|
| Account merge: two accounts become one | `TODO: which id survives, what happens to the other one's history, whether the cohort date is the older or the newer` |
| Account split: one account becomes two | `TODO` |
| Plan change: upgrade, downgrade, trial to paid | `TODO: does the entity keep its original cohort date` |
| Re-signup: a churned entity comes back | `TODO: new entity or the same one, and the reactivation window` |
| Seat added or removed on an existing account | `TODO` |
| Hard delete or a GDPR erasure request | `TODO: how history is treated after the row is gone` |

*EXAMPLE (fictional Nimbus Freight):*

| Event | Rule |
|---|---|
| Account merge | The surviving `account_id` is the one with the earlier `created_at`. The merged account's events keep the old `account_id` in PostHog forever, so any longitudinal query maps through `account_merges(old_id, new_id, merged_at)` in Postgres. The cohort date is the surviving account's, not the merge date. |
| Account split | Rare, 3 cases total. The new account is a new entity with a new cohort date. The original keeps its history. Both are listed in `account_splits`. |
| Plan change | The entity keeps its original cohort date. Plan is a point-in-time attribute, so any plan filter must state whether it is the plan at window start, window end, or the plan today. Default is plan at window end. |
| Re-signup | Same `account_id` if it returns within 90 days of `churned_at`, and it does not enter a new cohort. After 90 days it is a new entity with a new cohort date. This 90-day line is a decision, not a fact, and it is the reason two retention numbers ever disagree. |
| Seat added or removed | No effect on account grain. At user grain the user's cohort date is their own `created_at`, not the account's. |
| Hard delete or GDPR erasure | The row is gone and the history is not recoverable. Aggregates computed before the erasure are not restated. Any window covering an erasure states the count of erased entities from `erasure_log`. |

**Why this matters:** treating a 100-day re-signup as the same entity turns a new
customer into a retained one, and quietly inflates every retention cohort it lands in.

---

## 6. Change log

Every edit to this file changes past numbers. Record it.

| Date | Section | What changed | Reports affected |
|---|---|---|---|
| `TODO` | `TODO` | `TODO` | `TODO` |

*EXAMPLE:* `2026-02-14 | Exclusions | Added E-2, five founder-owned accounts on customer
domains | 2026-01-20-signup-trend.md understated the exclusion by roughly 400 signups.`
