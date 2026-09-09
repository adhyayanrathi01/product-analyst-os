# Metrics

**Status: TEMPLATE. Nothing below is a fact about your product. Fill it in.**

Every block marked `EXAMPLE` describes a fictional company called **Nimbus Freight**.
Nimbus Freight does not exist. Delete the examples once you have written your own.

Every metric here inherits the grain, the active definition, and the exclusion rules
from `entities.md`. Fill that file first. A metric defined against an undefined grain
is a number with no unit.

---

## Every metric needs six fields

| Field | What it means |
|---|---|
| Name | The exact string a report uses. One name per metric. |
| Plain-language definition | One sentence a new hire understands. No SQL. |
| Exact computation | The numerator, the denominator, the window, the grain, and the exclusion rule ids applied. |
| Source | Which source, which table or event. |
| Owner | A role that answers questions about it. Not "the team". |
| Known caveats | What it undercounts, overcounts, or breaks on. |

---

## North star

The one metric that goes up when customers get more value. Exactly one.

| Field | Your answer |
|---|---|
| Name | `TODO` |
| Plain-language definition | `TODO` |
| Exact computation | `TODO` |
| Source | `TODO` |
| Owner | `TODO` |
| Known caveats | `TODO` |
| Value now, and on what date | `TODO` |

*EXAMPLE (fictional Nimbus Freight):*

| Field | Answer |
|---|---|
| Name | `weekly_tracked_shipments_per_active_account` |
| Plain-language definition | How many shipments a typical customer is actually running through Nimbus in a week. |
| Exact computation | Numerator: distinct `shipment_id` with at least one `shipment_status_updated` event in the ISO week, UTC. Denominator: accounts active in that week per `active_28d_core`. Grain: account. Exclusions E-1 through E-7 applied. Median, not mean, because three accounts carry 40% of volume. |
| Source | PostHog events, joined to Postgres `accounts` on `account_id`, a confirmed identifier. |
| Owner | PM, freight core. |
| Known caveats | Undercounts accounts using the API only, because API shipment updates emit `shipment_status_updated` with `$lib = 'posthog-python'`, which E-7 drops. That is roughly 8% of accounts and it is a known defect, not a decision. |
| Value now | 34 shipments, week of 2026-02-09. |

---

## Input metrics

The two to four things you can actually change that move the north star. If you
cannot name the mechanism by which an input moves the north star, it is not an input,
it is a correlation.

| Name | Definition | Computation | Source | Owner | Caveats | How it moves the north star |
|---|---|---|---|---|---|---|
| `TODO` | `TODO` | `TODO` | `TODO` | `TODO` | `TODO` | `TODO` |

*EXAMPLE:*

| Name | Definition | Computation | Source | Owner | Caveats | How it moves the north star |
|---|---|---|---|---|---|---|
| `carriers_connected_wk1` | How many carrier integrations an account turns on in its first 7 days. | Count of distinct `carrier_id` in `integrations` with `connected_at` within 7 days of `accounts.created_at`. Grain: account. E-1 to E-7. | Postgres `public.integrations` | PM, integrations | Counts a connection that was later removed. No de-duplication for reconnects. | Each connected carrier is a set of shipments that can be tracked in Nimbus instead of a portal. |
| `portal_free_updates` | Share of status updates a coordinator makes without opening a carrier portal. | Numerator: `shipment_status_updated` where `properties.origin = 'nimbus'`. Denominator: all `shipment_status_updated`. Window: rolling 28 days, UTC. Grain: account, then median across accounts. E-1 to E-7. | PostHog | PM, freight core | `properties.origin` was added 2025-06-11. Anything earlier is not comparable. Do not chart across that date. | A coordinator who never leaves Nimbus runs more shipments through it. |
| `time_to_first_shipment` | Hours from account creation to the first shipment created. | `MIN(shipment_created.timestamp) - accounts.created_at`, in hours. Grain: account. Median. E-1 to E-7. | PostHog and Postgres | PM, onboarding | Accounts that never create a shipment are excluded from the median, which makes it look better than it is. Always report alongside the share that never converts. | Faster first shipment means the coordinator learns the loop before the trial ends. |

---

## Guardrail metrics

The numbers that must not get worse while you move the input metrics. Each one needs
a threshold, not just a name.

| Name | Definition | Computation | Source | Owner | Threshold that triggers a stop |
|---|---|---|---|---|---|
| `TODO` | `TODO` | `TODO` | `TODO` | `TODO` | `TODO` |

*EXAMPLE:*

| Name | Definition | Computation | Source | Owner | Threshold that triggers a stop |
|---|---|---|---|---|---|
| `shipment_update_error_rate` | Share of status updates that fail. | `count(shipment_update_failed) / count(shipment_update_attempted)`, rolling 7 days, UTC. | PostHog | Eng lead, integrations | Above 2.0% for two consecutive days. |
| `support_tickets_per_100_accounts` | Ticket volume normalised by customer count. | Zendesk tickets created in the week, divided by active accounts, times 100. Zendesk is not joined to accounts, see `entities.md` section 4. | Zendesk, unjoined | Support lead | Above 14, or up more than 30% week on week. |
| `p95_shipment_list_latency` | How long the main screen takes to load for the slowest 5%. | p95 of `shipment_list_loaded` `properties.duration_ms`, rolling 7 days. | PostHog | Eng lead, freight core | Above 2,500 ms. |

---

## Definitions we have argued about

Settled disputes go here so they stay settled. An unsettled dispute is the reason two
people quote two different numbers for the same word in the same meeting.

One row per dispute. `Settled on` is a date. If it is blank, the dispute is open and
the agent reports both numbers rather than picking.

| Term | The two positions | What we settled on | Settled on | Who decided | What it costs us |
|---|---|---|---|---|---|
| `TODO` | `TODO` | `TODO` | `TODO` | `TODO` | `TODO` |

*EXAMPLE:*

| Term | The two positions | What we settled on | Settled on | Who decided | What it costs us |
|---|---|---|---|---|---|
| Active | Sales wanted "signed in within 30 days" because it matches the billing dashboard. Product wanted "created or updated a shipment within 28 days". | Product's definition, named `active_28d_core`, is the only one used in reports. The sales number keeps its own name, `active_login_30d`, and is never called "active" unqualified. | 2025-11-04 | Head of product | Board decks quote a number 2.4x lower than the one sales quotes. Every deck now carries the definition in a footnote. |
| Churn date | Billing uses the subscription cancel date. Product used the last activity date. | Billing's date. Last activity becomes a separate metric, `days_dark_before_churn`. | 2025-12-02 | CFO and head of product | Product's churn curve moved right by a median 23 days when this landed. Anything charted before 2025-12-02 uses the old definition. |
| Retention denominator | Some cohort charts counted all signups. Others counted only accounts that reached first shipment. | All signups. Activation gets its own metric rather than being hidden in the retention denominator. | 2026-01-19 | PM, onboarding | Retention as reported dropped from 51% to 38%. Nothing changed in the product. |
| A "shipment" | Does a cancelled shipment count? | Open. Report both, labelled. | | | Two numbers in every shipment volume report until this is settled. |

---

## Cuts

The segments a report is allowed to split by, and the column each one comes from.
An agent may not invent a cut.

| Cut | Column or property | Source | Notes |
|---|---|---|---|
| `TODO` | `TODO` | `TODO` | `TODO` |

*EXAMPLE:*

| Cut | Column or property | Source | Notes |
|---|---|---|---|
| Plan tier | `accounts.plan_type` | Postgres | Point-in-time. State whether it is the plan at window start or end. |
| Signup month cohort | `date_trunc('month', accounts.created_at)` | Postgres | Affected by the re-signup rule in `entities.md` section 5. |
| Persona | `users.role` | Postgres | Only for user-grain metrics. 94% populated. |
| Carrier count | `count(integrations)` bucketed 0, 1, 2, 3+ | Postgres | Buckets are fixed. Do not rebucket per report. |
