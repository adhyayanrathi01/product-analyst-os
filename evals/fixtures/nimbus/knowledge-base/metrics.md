# Metrics

**FILLED FIXTURE. Nimbus Freight is fictional.**

Every metric inherits the grain, the active definition, and the exclusion rules from
`entities.md`.

---

## North star

| Field | Answer |
|---|---|
| Name | `weekly_tracked_shipments_per_active_account` |
| Plain-language definition | How many shipments a typical customer actually runs through Nimbus in a week. |
| Exact computation | Numerator: distinct `properties.shipment_id` with at least one `shipment_status_updated` event in the ISO week, UTC. Denominator: accounts active that week per `active_28d_core`. Grain: account. Exclusions E-1 to E-5 and E-7 to E-9 applied. Median, not mean, because 3 accounts carry 40% of volume. |
| Source | PostHog events, joined to Postgres `accounts` on `account_id`, a confirmed identifier. |
| Owner | PM, freight core. |
| Known caveats | Undercounts API-only accounts, because API shipment updates emit with `$lib = 'posthog-python'` and E-7 drops them. Roughly 8% of accounts. Known defect, not a decision. |
| Value now | 31 shipments, week of 2026-08-24. |

---

## Input metrics

| Name | Definition | Computation | Source | Owner | Caveats | How it moves the north star |
|---|---|---|---|---|---|---|
| `carriers_connected_wk1` | Carrier integrations an account turns on in its first 7 days. | Distinct `integrations.carrier_id` with `connected_at` within 7 days of `accounts.created_at`. Account grain. E-1 to E-4, E-9. | Postgres `public.integrations` | PM, integrations | Counts a connection later removed. No dedup for reconnects. | Each carrier connected is a set of shipments trackable in Nimbus instead of a portal. |
| `activation_7d` | Share of new accounts that create a shipment within 7 days of signup. | Numerator: accounts with a `shipment_created` event where `timestamp < accounts.created_at + 7 days`. Denominator: accounts created in the cohort window. Account grain, joined on the confirmed `account_id`. E-1 to E-5, E-7, E-9. | PostHog and Postgres | PM, onboarding | **Account grain only.** The user-grain version of this metric does not exist, because `distinct_id` to `users.id` is unconfirmed. Do not compute a per-user activation rate. Also a floor, not a count: `shipment_created` is client-side and there is no server-side equivalent in the captured schema. | An account that never creates a shipment never reaches the tracking loop. |
| `time_to_first_shipment` | Hours from account creation to first shipment. | `MIN(shipment_created.timestamp) - accounts.created_at`, hours, median, account grain. | PostHog and Postgres | PM, onboarding | Accounts that never create a shipment fall out of the median, which flatters it. Always report next to the never-activated share. | A faster first shipment means the coordinator learns the loop inside the trial. |

---

## Guardrail metrics

| Name | Definition | Computation | Source | Owner | Threshold that triggers a stop |
|---|---|---|---|---|---|
| `shipment_update_error_rate` | Share of status updates that fail. | `count(shipment_update_failed) / count(shipment_update_attempted)`, rolling 7 days UTC. | PostHog | Eng lead, integrations | Above 2.0% for two consecutive days. |
| `p95_shipment_list_latency` | Load time for the slowest 5% on the main screen. | p95 of `shipment_list_loaded.properties.duration_ms`, rolling 7 days. | PostHog | Eng lead, freight core | Above 2,500 ms. |

---

## Definitions we have argued about

| Term | The two positions | What we settled on | Settled on | Who decided | What it costs us |
|---|---|---|---|---|---|
| Active | Sales wanted "signed in within 30 days" to match the billing dashboard. Product wanted "created or updated a shipment within 28 days". | Product's, named `active_28d_core`, the only one used in reports. Sales keeps `active_login_30d` under its own name. | 2025-11-04 | Head of product | Board decks quote a number 2.4x lower than the one sales quotes. Every deck carries the definition in a footnote. |
| Signup | Does a sales-created demo account count as a signup? | **Open.** Report both, labelled. Finance counts them because the AE console is the same form. Product does not. | | | Two numbers in every signup report until this is settled. This is why the August 2026 spike had two readings. |
| "Active in a calendar month" | Rolling 28-day window ending on the last day, or every day of the calendar month. | **Open.** Report both, labelled. See `entities.md` section 2. | | | Two numbers in every monthly active report. The two have never disagreed on direction, only on level. |

---

## Cuts

| Cut | Column or property | Source | Notes |
|---|---|---|---|
| Plan tier | `accounts.plan_type` | Postgres | Point in time. State whether it is the plan at window start or end. Default is window end. |
| Signup month cohort | `date_trunc('month', accounts.created_at)` | Postgres | Affected by the re-signup rule, `entities.md` section 5. |
| Signup source | `accounts.signup_source` | Postgres | `organic`, `paid`, `sales_created`, `partner`. 100% populated since 2025-04-01. |
| Account type | `accounts.account_type` | Postgres | `standard`, `demo`, `sandbox`. Do not use as a cut in a report where E-4 already removed demo. |
| Persona | `users.role` | Postgres | User-grain metrics only. 94% populated. |
| Carrier count | `count(integrations)` bucketed 0, 1, 2, 3+ | Postgres | Buckets are fixed. Do not rebucket per report. |
