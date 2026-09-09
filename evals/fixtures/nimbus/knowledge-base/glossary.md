# Glossary

**FILLED FIXTURE. Nimbus Freight is fictional.**

## Product nouns

| Term | What it is |
|---|---|
| Shipment | One load moving from origin to destination. The object a coordinator watches. Whether a cancelled shipment counts is settled: it does, and reports label the cancelled share. |
| Carrier integration | A credentialed connection to one carrier's tracking API. One row in `integrations`. |
| Tracking link | A public URL a customer sends to their own customer. No login, no `account_id` on the events. |

## Internal shorthand

| Term | What it means here |
|---|---|
| AE console | The internal tool an account executive uses to spin up a demo account for a prospect. Writes to the same `accounts` table with `account_type = 'demo'` and `signup_source = 'sales_created'`. |
| The push | The 2026-08-10 to 2026-08-21 outbound sprint. Three new AEs were onboarded and every prospect got a demo account. This is the cause of the August signup spike. |

## Words whose everyday meaning differs here

| Word | Everyday meaning | What it means at Nimbus |
|---|---|---|
| Signup | A person creating an account. | A row in `accounts`, which may have been created by an AE for a prospect who never saw the product. Unqualified "signups" is ambiguous and reports say which. |
| Active | Logged in recently. | `active_28d_core` in `entities.md`. Created or updated a shipment in a rolling 28 days. |
| User | A person. | A row in `users`. A PostHog `distinct_id` is a device key, not a user, and the two are not joinable. |
| Free | Not paying. | The `solo` plan. It is a real business account with a real company behind it, not a trial. |

## Terms we deliberately do not use

| Term | Why not |
|---|---|
| MAU | Ambiguous between the rolling and calendar-month definitions, and ambiguous between account and user grain. Name the metric instead. |
| Customer | Ambiguous between account and user. Say "account". |
