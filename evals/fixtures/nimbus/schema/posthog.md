# Schema: posthog

**FIXTURE. Stands in for `schema/posthog/schema.md`. Nimbus Freight is fictional and
this taxonomy was never read from a real project.**

Format follows `schema/_template/schema.md`.

---

## Capture record

| Field | Value |
|---|---|
| Source | `posthog` |
| Source type | posthog |
| Database / project / dataset | project `4412`, US cloud |
| Capture date | 2026-08-14 |
| Captured by | agent run, task `2026-08-14-schema-refresh` |
| Capture method | sampled. Event names from the definitions API, properties inferred from 5,000 sampled events. |
| Credential used | `POSTHOG_API_KEY` |
| Hash | `sha256:b30d7e14ca9f6208d5417be3c02a8f19764d5e0b3ac81f92d6e4470bb1c3592a` |
| Hash command | see `schema/README.md`, run verbatim |
| Previous hash | `sha256:5ae8102cf7b34d6690e1a72c8bd450f31ee97c04a2b6f8d17390cb45ea2d6618` |
| What changed since | `shipment_created` gained `properties.origin`. `$lib` value `posthog-go` first seen 2026-08-19, after this capture, and was added to E-7 by hand on 2026-08-20. |

## Introspection query used

```sql
SELECT event, count() AS events, count(DISTINCT distinct_id) AS actors,
       min(timestamp) AS first_seen, max(timestamp) AS last_seen
FROM events
WHERE timestamp >= toDateTime('2026-05-14 00:00:00', 'UTC')
  AND timestamp <  toDateTime('2026-08-14 00:00:00', 'UTC')
GROUP BY event
ORDER BY events DESC
LIMIT 200
```

---

## INFERRED FROM A SAMPLE

**This property listing was inferred from 5,000 sampled events, not read from a catalog.
Rare properties may be missing entirely. A property present on under 1% of events can be
absent from this listing and still exist in the data.**

- Events sampled: 5,000
- Event volume in the sampled window: 41.2 million
- Sample method: `$sample` over the 90 days ending 2026-08-14
- Properties seen on under 5% of sampled events are marked `rare`.
- A query needing a property that is not listed is not automatically drift. Widen the
  sample before concluding either way. Event **names** come from the definitions API and
  are a full listing, so a missing event name **is** drift.

---

## Listing

### Event names (full listing, from the definitions API)

| Event | Type | Comment | Notes |
|---|---|---|---|
| `shipment_created` | event | A shipment record is created in the UI | Qualifying action for `active_28d_core`. Client-side. No server-side equivalent exists in `postgres-replica`, so any count is a floor. |
| `shipment_status_updated` | event | A status changes on a shipment | Qualifying action for `active_28d_core`. Fires from both the UI and the carrier poller. Poller fires carry `$lib = 'posthog-python'` and E-7 drops them. |
| `shipment_update_failed` | event | A status update failed | Guardrail metric numerator. |
| `shipment_update_attempted` | event | A status update was attempted | Guardrail metric denominator. |
| `shipment_list_loaded` | event | Main screen render | Does NOT qualify for active. Carries `properties.duration_ms`. |
| `carrier_connected` | event | A carrier integration validated | Mirrors `integrations.connected_at`, usually within 2 seconds. |
| `user_signed_in` | event | Login | Does NOT qualify for active. Basis of `active_login_30d` only. |
| `page_viewed` | event | Page view | Does NOT qualify for active. |
| `settings_opened` | event | Settings screen | Does NOT qualify for active. |
| `tracking_link_viewed` | event | A public tracking link was opened | **Carries no `account_id`.** Fired by carrier dispatchers who have no `users` row. Never attributable to an account. |

### Event columns and properties

| Column | Type | Nullable | Comment | Notes |
|---|---|---|---|---|
| `event` | `string` | no | Event name | |
| `timestamp` | `timestamp` | no | Client time, UTC | Client clock, can be wrong. `$sent_at` is the server time. Stored in UTC regardless of what the project UI displays. |
| `distinct_id` | `string` | no | PostHog person key | **Not `users.id`.** Device-scoped. One person on a laptop and a phone has two. Unconfirmed join, `entities.md` section 4. |
| `properties.account_id` | `string` | yes | Account id, copied at event time | Confirmed join to Postgres `accounts.id`, 1 to many, Postgres wins. Stale after an account merge. Absent on `tracking_link_viewed`. |
| `properties.environment` | `string` | yes | `production` or `staging` | Exclusion E-5. Missing on events before 2025-03-01, treat missing as non-production before that date. |
| `properties.$lib` | `string` | yes | Client library | `web`, `posthog-js`, `posthog-python`, `posthog-node`, `posthog-go`. Server-side libs are backfills and pollers, not humans. Exclusion E-7. |
| `properties.$user_agent` | `string` | yes | User agent string | Exclusion E-7 bot pattern. |
| `properties.origin` | `string` | yes | `nimbus` or `portal` | `rare` before 2026-06-11, added that date. Do not chart across it. |
| `properties.shipment_id` | `string` | yes | Shipment id | Present on the four `shipment_*` events. Opaque id, safe to aggregate on. |
| `properties.duration_ms` | `integer` | yes | Render time | `rare`. Present only on `shipment_list_loaded`. |

---

## Known gaps

| What | Why it is missing | Effect on analysis |
|---|---|---|
| Any property under 1% frequency | Sampled capture, 5,000 events. | An absent property is not proof it does not exist. Widen the sample first. |
| A `distinct_id` to `users.id` mapping | PostHog `identify()` was never called with the Postgres user id, and there is no person-merge export in this project. | **No per-user rate can span PostHog and Postgres.** C-11 blocks the join. Account grain via `properties.account_id` is the only cross-source path. |
| Events before 2025-03-01 | `properties.environment` did not exist, so staging and production cannot be separated. | E-5 cannot be applied before that date. Nothing in this fixture reaches back that far. |
| `tracking_link_viewed` attribution | No `account_id` on the event by design. | Any funnel starting at a tracking link is unattributable. |
