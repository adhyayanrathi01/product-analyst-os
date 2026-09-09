# Company

**FILLED FIXTURE. Nimbus Freight is fictional. Nothing here describes a real company.**

## What the product does

Nimbus Freight is shipment tracking for mid-market freight forwarders and shippers. A
shipping coordinator creates a shipment in Nimbus, connects the carriers the load moves
on, and Nimbus pulls status from each carrier so the coordinator stops logging into six
carrier portals a day.

## Business model

B2B SaaS, per-seat subscription with an annual contract on the enterprise tier. One
contract per shipping company. The account is the customer.

## Pricing shape

| Plan | Price | What changes |
|---|---|---|
| Solo | $0 | 1 seat, 50 shipments a month, no API. This is the free tier. |
| Team | $49 per seat per month | Unlimited shipments, API, 3 carrier integrations |
| Enterprise | Negotiated, floor $40k a year | SSO, unlimited integrations, an assigned CSM |

## Sales motion

Product-led into Solo and Team. Sales-led into Enterprise, where an AE creates a demo
account per prospect from the AE console. Those demo accounts land in the same
`accounts` table as real customers with `account_type = 'demo'`, which is why E-4 exists
and why a sales push shows up as a signup spike.

## Stage

Series A. 1,173 real accounts signed up in August 2026. About 2,554 accounts were active
in August. Revenue is concentrated: 241 enterprise accounts carry most of it.

## Job to be done

"Tell me where my freight is without me chasing six carrier portals."
