# Entities

**Status: FILLED. Fixture for Nimbus Freight, a fictional B2B freight SaaS.**

This is eval fixture data. Nimbus Freight does not exist. Nothing here is a fact about
any real product. It exists so the analysis skills can be exercised end to end without a
live data source. Every `TODO` from `knowledge-base/entities.md` is answered and every
`EXAMPLE` marker is gone, because an agent under test must read this as fact.

Filled: 2026-09-09. Owner: PM, freight core.

---

## 1. Grain

| Field | Answer |
|---|---|
| Primary grain | Account. Nimbus sells one contract per shipping company. A count of "customers" is a count of accounts. |
| The id column that expresses it | `accounts.id` |
| Where that column lives | Postgres, `public.accounts.id` |
| When the other grain is allowed | Seat adoption and feature-usage questions only. The report must say "user grain" in its Filters section. |
| How to roll the other grain up | `COUNT(DISTINCT account_id)`. Never `COUNT(*)` on a user-level table. |

**Why this matters:** the mean seat count is 3.34 users per account as of 2026-09-01. A
user-grain count read as a customer count overstates by roughly 3.3x.

### Both shapes

Nimbus sells to businesses only. The `solo` plan is a single-seat business account, not
a consumer product, so there is one grain and no B2C split.

| Field | Answer |
|---|---|
| Rule that assigns a row to the B2B grain | All rows. Every account is B2B. |
| Rule that assigns a row to the B2C grain | Not applicable. No B2C grain exists. |
| Rows matching neither rule | None. |
| Rows matching both rules | None. |

---

## 2. Active

| Field | Answer |
|---|---|
| Window | 28 days |
| Window anchor | Rolling, ending at the query's end date inclusive |
| Timezone | UTC |
| Qualifying action | PostHog event `shipment_created` or `shipment_status_updated` |
| Actions that do NOT qualify | `user_signed_in`, `page_viewed`, `settings_opened`, `shipment_list_loaded`, and any event where `properties.$lib` is a server-side library |
| Grain | Account |
| Threshold | At least one qualifying event from at least one non-excluded user in the account |

**Why this matters:** "active = signed in" returns roughly 2.4x the count that
"active = created or updated a shipment" returns. Both are defensible. Only one goes in
a report, and the report says which.

### Named variants

| Variant name | Definition | Where it may be used | Where it may not |
|---|---|---|---|
| `active_28d_core` | The definition above. Rolling 28 days, UTC, account grain. | Every product report. This is the default and the only unqualified meaning of "active". | Never used to reconcile against the billing dashboard. |
| `active_login_30d` | At least one `user_signed_in` event in a rolling 30 days, account grain. | Only when explicitly comparing against the billing dashboard, and the report labels it. | Never called "active" without the suffix. Never used in a product report. |

### Calendar-month questions

**Open item, unsettled as of 2026-09-09.** `active_28d_core` is a rolling window. A
question phrased "active in August" is not the same shape. There is no settled rule for
mapping a calendar month onto the rolling definition.

Until this is settled, an analysis that is asked for a calendar month reports both:

- The rolling 28-day window ending on the last day of that month, labelled
  `active_28d_core`.
- The calendar-month window, labelled `active_calendar_month`, and flagged as a variant
  with no owner.

It does not silently pick one. Recorded as an open dispute in `metrics.md`.

---

## 3. Exclusions

C-10 requires every analysis to apply these and to state which ones it applied.

Rules are written to KEEP wanted rows. They `AND` together directly into a `WHERE`
clause. Never invert one.

| # | Category | Rule (literal predicate, written to KEEP wanted rows) | Source | Confidence | Notes |
|---|---|---|---|---|---|
| E-1 | Internal by email domain | `users.email NOT ILIKE '%@nimbusfreight.example' AND users.email NOT ILIKE '%@nimbus-qa.example'` | Postgres `public.users` | confirmed | Two live domains. A third, `nimbusfreight.test`, was retired in 2025 and still has 6 user rows, all on accounts already caught by E-3. |
| E-2 | Internal by account id list | `accounts.id NOT IN (1, 2, 7, 41, 903)` | Postgres `public.accounts` | confirmed | Founder-owned accounts registered on real customer domains, so E-1 misses them. All five were created in 2023 and 2024, so this rule removes zero rows from any 2026 signup window. |
| E-3 | Internal by flag | `accounts.is_internal IS NOT TRUE` | Postgres `public.accounts` | confirmed | Nullable column. Use `IS NOT TRUE`, not `= FALSE`. NULL means never reviewed, and there are 411 such rows. |
| E-4 | Demo accounts | `accounts.account_type IS DISTINCT FROM 'demo'` | Postgres `public.accounts` | confirmed | Sales creates one per prospect from the AE console. Volume tracks sales headcount and campaign timing, not product demand. Roughly 300 live at any time in a normal month. |
| E-5 | Sandbox and staging | `events.properties.environment = 'production'` | PostHog | confirmed | Staging writes into the same PostHog project. The property is missing on events before 2025-03-01. Treat missing as non-production before that date. Applies to event queries only. It has no Postgres equivalent, so a Postgres-only query states E-5 as not applicable rather than applied. |
| E-6 | Test accounts created by real users | `(accounts.name IS NULL OR accounts.name !~* '^(test\|asdf\|delete me\|zzz\|xxx)')` | Postgres `public.accounts` | unconfirmed | Heuristic over a free-text field. Never applied silently. Name it, say what it would change, and let the PM promote it. Two real customers are named "Testa Logistics" and "ZZZ Haulage" and this pattern removes both. |
| E-7 | Bots and automated traffic | `events.properties.$lib NOT IN ('posthog-python','posthog-node','posthog-go') AND events.properties.$user_agent !~* '(bot\|crawler\|spider\|headless)'` | PostHog | confirmed | Server-side libraries here are backfills and integration tests, not humans. Known cost: this also drops genuine API-only customer traffic, roughly 8% of accounts. That is a known defect, recorded in `metrics.md`, not a decision. |
| E-8 | Churned entities | `accounts.churned_at IS NULL OR accounts.churned_at > <window_start>` | Postgres `public.accounts` | confirmed | Do not drop churned accounts out of historical windows. They were real customers then. `<window_start>` is substituted with the literal start timestamp of the query window. Comparing against `<window_end>` instead removes every account that churned mid-window, which is the opposite of what this rule is for. |
| E-9 | Deleted entities | Current-state questions: `accounts.deleted_at IS NULL`. Historical windows: `accounts.deleted_at IS NULL OR accounts.deleted_at >= <window_start>` | Postgres `public.accounts` | confirmed | Soft delete. Rows stay in the table. |
| E-10 | Free vs paid | Not excluded by default. Split by `accounts.plan_type = 'solo'` when the question is about revenue or retention. | Postgres `public.accounts` | confirmed | `solo` is the free tier. It is 39% of the account count and 0% of revenue. Mixing it in flattens any revenue-adjacent metric. Not a filter, a required split. |

**Why this matters:** applying E-1 through E-4 and E-9 to the August 2026 signup count
drops it from 2,401 to 1,173. A report showing only one of those numbers hides a 51%
swing and reverses the headline.

### How to state exclusions in a report

Every report lists the rule ids it applied, by id, in the `Exclusions applied` section,
and gives the unfiltered number wherever an exclusion moved the answer materially. If it
applied none, it says why in the same sentence. "None" on its own fails
`evals/check-output.sh`.

### When a case has no rule

Stop. Do not invent one. Report the case, the row count it affects, and ask.

---

## 4. Identity and joins

C-11 forbids inferring a join. A join runs only on an identifier listed as `confirmed`
here, with its cardinality and precedence stated.

### Confirmed identifiers

| Identifier | Links which sources | Cardinality | Source of truth | Precedence when they disagree | Verified how, and when |
|---|---|---|---|---|---|
| `account_id` | Postgres `accounts.id` to PostHog `events.properties.account_id` | 1 to many. One account, many events. | Postgres | Postgres wins. PostHog copies the value at event time and never updates it after an account merge, so a longitudinal query maps through `account_merges`. | Sampled 5,000 PostHog `account_id` values against Postgres on 2026-08-14. 11 orphans, all from two merged accounts. Orphan rate 0.22%. |
| `account_id` | Postgres `accounts.id` to Postgres `users.account_id`, `integrations.account_id`, `subscriptions.account_id` | 1 to many in all three cases. | Postgres `accounts` | Not applicable, single source. `subscriptions` has at most one row with `status = 'active'` per account, enforced by a partial unique index. | Foreign key constraints, verified in the 2026-08-14 catalog capture. |

### Unconfirmed, do not join

These look joinable. They are not. Any analysis that needs one stops and says what it
could not join.

| Identifier pair | Why it is not confirmed | What to do instead |
|---|---|---|
| PostHog `distinct_id` to Postgres `users.id` | **This is the important one.** Nimbus never called PostHog `identify()` with the Postgres user id. `distinct_id` is an anonymous device key, and a user on a laptop plus a phone has two of them. A 2026-08-14 sample of 5,000 `distinct_id` values resolved to a Postgres user for 61% of them, and the unresolved 39% skew heavily to mobile and to enterprise accounts. The mapping is many-to-many and there is no merge table. | Do not produce any per-user rate that spans PostHog and Postgres. Report the PostHog number at `distinct_id` grain and the Postgres number at `users.id` grain, side by side, and say in one sentence that they were not joined and why. Where the question can be answered at account grain instead, answer it there using the confirmed `account_id` and say that the grain moved. |
| `users.email` to Zendesk `requester.email` | Users file tickets from personal addresses. A 2026-06 check matched 58% of tickets. The unmatched 42% are not random, they skew to enterprise. | Report ticket volume unjoined at Zendesk grain and say it cannot be attributed to accounts. |
| `accounts.name` to Salesforce `Account.Name` | Free text on both sides. Casing, legal suffixes, "Inc" against "Inc." | Ask the PM for a mapping table. Do not fuzzy match. |
| PostHog `$session_id` to Postgres `sessions` rows | Different definitions. PostHog closes a session after 30 minutes idle. The app holds a 14-day token. | Pick one, say which. Never treat them as the same object. |

---

## 5. Lifecycle edge cases

| Event | Rule |
|---|---|
| Account merge: two accounts become one | The surviving `account_id` is the one with the earlier `created_at`. The merged account's PostHog events keep the old `account_id` forever, so any longitudinal query maps through `account_merges(old_id, new_id, merged_at)` in Postgres. The cohort date is the surviving account's, not the merge date. 14 merges to date, 2 of them in 2026. |
| Account split: one account becomes two | The new account is a new entity with a new cohort date. The original keeps its full history. Both sides are listed in `account_splits`. 3 cases total, none in 2026. |
| Plan change: upgrade, downgrade, trial to paid | The entity keeps its original cohort date. Plan is a point-in-time attribute, so every plan filter states whether it means the plan at window start, at window end, or today. Default is plan at window end. |
| Re-signup: a churned entity comes back | Same `account_id` and the same cohort if it returns within 90 days of `churned_at`. After 90 days it is a new entity with a new cohort date and a second `accounts` row. This 90-day line is a decision, not a fact, and it is the reason two retention numbers ever disagree. 31 re-signups in 2026, 19 inside the 90-day line. |
| Seat added or removed on an existing account | No effect at account grain. At user grain the user's cohort date is their own `users.created_at`, never the account's. |
| Hard delete or a GDPR erasure request | The row is gone and the history is not recoverable. Aggregates computed before the erasure are not restated. Any window covering an erasure states the count of erased entities from `erasure_log`. 4 erasures in 2026, none in July or August. |

**Why this matters:** treating a 100-day re-signup as the same entity turns a new
customer into a retained one and inflates every retention cohort it lands in.

---

## 6. Change log

| Date | Section | What changed | Reports affected |
|---|---|---|---|
| 2026-08-14 | Identity and joins | Re-sampled `distinct_id` resolution. Rate fell from 71% to 61% after the mobile app shipped. Confirmed the pair stays unconfirmed. | None yet. Any future per-user cross-source rate is blocked by this. |
| 2026-08-20 | Exclusions | Added `posthog-go` to E-7 after the tracking backfill service was rewritten. | None. The service started emitting on 2026-08-19. |
| 2026-09-01 | Active | Recorded the calendar-month question as unsettled. Previously the agent picked the rolling window silently. | Any report before this date that answered a calendar-month question used the rolling window without saying so. |
