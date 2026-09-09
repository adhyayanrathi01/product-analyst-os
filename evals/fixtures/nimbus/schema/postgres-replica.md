# Schema: postgres-replica

**FIXTURE. Stands in for `schema/postgres-replica/schema.md`. Nimbus Freight is
fictional and this catalog was never read from a real database.**

Format follows `schema/_template/schema.md`.

---

## Capture record

| Field | Value |
|---|---|
| Source | `postgres-replica` |
| Source type | postgres |
| Database / project / dataset | `nimbus_prod`, schema `public` |
| Capture date | 2026-08-14 |
| Captured by | agent run, task `2026-08-14-schema-refresh` |
| Capture method | full catalog read |
| Credential used | `DATABASE_URI` |
| Hash | `sha256:7c1f9ab4d2e05c8813fa6b7709e4c1d20f5a3b6e8c9d0142ab77e3f5c6019d4e` |
| Hash command | see `schema/README.md`, run verbatim |
| Previous hash | `sha256:41be0c73a9d8f2115e6c40bb7723d9ae018f5c62d4e73a0916bb2c8ef50d7307` |
| What changed since | `accounts.signup_source` backfilled to NOT NULL. `subscriptions.mrr_cents` widened from `integer` to `bigint`. No columns removed. |

## Introspection query used

```sql
SELECT c.table_name, c.column_name, c.data_type, c.is_nullable,
       pgd.description AS column_comment
FROM information_schema.columns c
LEFT JOIN pg_catalog.pg_statio_all_tables st ON st.relname = c.table_name
LEFT JOIN pg_catalog.pg_description pgd
       ON pgd.objoid = st.relid AND pgd.objsubid = c.ordinal_position
WHERE c.table_schema = 'public'
ORDER BY c.table_name, c.ordinal_position
LIMIT 5000;
```

---

## Listing

### `public.accounts`

| Column | Type | Nullable | Comment | Notes |
|---|---|---|---|---|
| `id` | `bigint` | no | Account id | The account grain, per `entities.md` section 1. |
| `name` | `text` | no | Display name | Free text. Do not join on it, see `entities.md` section 4. E-6 pattern-matches this column and E-6 is unconfirmed. |
| `plan_type` | `text` | no | `solo`, `team`, `enterprise` | Point in time. A filter must say window start, window end, or today. `solo` is the free tier, E-10. |
| `account_type` | `text` | no | `standard`, `demo`, `sandbox` | Exclusions E-4 and E-5. `demo` rows are created by an AE from the AE console, not by a prospect. |
| `signup_source` | `text` | no | `organic`, `paid`, `sales_created`, `partner` | Backfilled to NOT NULL on 2026-08-14. Values before 2025-04-01 are `organic` by backfill default and are not trustworthy. |
| `is_internal` | `boolean` | yes | Internal account flag | Nullable. NULL means never reviewed, 411 rows. Use `IS NOT TRUE`, not `= FALSE`. Exclusion E-3. |
| `created_at` | `timestamptz` | no | Row insert time, UTC | Not form submit time. Demo accounts are inserted at the moment the AE clicks, which is the AE's working hours, not the prospect's. |
| `churned_at` | `timestamptz` | yes | Billing cancel date | NULL for live accounts. Exclusion E-8. |
| `deleted_at` | `timestamptz` | yes | Soft delete | Rows stay in the table. Exclusion E-9. |
| `stripe_customer_id` | `text` | yes | Stripe customer | NULL for every `solo` account. Not used in this fixture, Stripe is not a fixture source. |

### `public.users`

| Column | Type | Nullable | Comment | Notes |
|---|---|---|---|---|
| `id` | `bigint` | no | User id | User grain. **Not** a PostHog `distinct_id`. See `entities.md` section 4, unconfirmed pairs. |
| `account_id` | `bigint` | no | Owning account | Foreign key to `accounts.id`. Many users to one account. |
| `email` | `text` | no | Login email | Personal data. Never paste into a report, per C-09. Exclusion E-1 filters on it. |
| `role` | `text` | yes | `coordinator`, `ops_director`, `admin` | 94% populated. NULL is not a persona. |
| `created_at` | `timestamptz` | no | Row insert time, UTC | The user's own cohort date at user grain, never the account's. |
| `deleted_at` | `timestamptz` | yes | Soft delete | Rows stay. |

### `public.integrations`

| Column | Type | Nullable | Comment | Notes |
|---|---|---|---|---|
| `id` | `bigint` | no | Integration id | |
| `account_id` | `bigint` | no | Owning account | Foreign key to `accounts.id`. |
| `carrier_id` | `text` | no | Carrier code | Fixed vocabulary of 41 carriers. |
| `connected_at` | `timestamptz` | no | When the credential first validated, UTC | |
| `disconnected_at` | `timestamptz` | yes | When it was removed | NULL means still connected. A reconnect writes a new row, so counting rows overcounts distinct carriers. |

### `public.subscriptions`

| Column | Type | Nullable | Comment | Notes |
|---|---|---|---|---|
| `id` | `bigint` | no | Subscription id | |
| `account_id` | `bigint` | no | Owning account | At most one row with `status = 'active'` per account, enforced by a partial unique index. |
| `status` | `text` | no | `active`, `past_due`, `cancelled` | |
| `mrr_cents` | `bigint` | no | Monthly recurring revenue in cents, USD | Widened from `integer` on 2026-08-14. Any aggregation captured before that date used a narrower type. Account-level. Summing it over a row set joined to `users` multiplies it by seat count. |
| `started_at` | `timestamptz` | no | Subscription start, UTC | |
| `cancelled_at` | `timestamptz` | yes | Subscription cancel, UTC | Billing's churn date, which is the settled definition in `metrics.md`. |

---

## Known gaps

| What | Why it is missing | Effect on analysis |
|---|---|---|
| `public.shipments` | Not in this capture. Shipments live in a separate service with its own store, which is not a connected source. | **There is no server-side equivalent of the PostHog `shipment_created` event.** Any activation or shipment-volume number from PostHog is a floor, not a count, and the report must say so. |
| `public.account_merges` and `public.account_splits` | Read role has no grant on either. | Longitudinal queries across a merge cannot map the old `account_id`. 2 merges in 2026. Any 2026 longitudinal number carries that as a known gap. |
| `public.erasure_log` | Read role has no grant. | GDPR erasure counts cannot be stated. 4 erasures in 2026 per the PM, none in July or August. |
| Column comments on `integrations` | None are set in the database. | The `Comment` column there is a human note, not a database comment. Treat it as a claim. |
