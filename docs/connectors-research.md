# Connector research

Verified September 2026. Every claim below carries a source. Items marked
**UNVERIFIED** were not confirmed and must be checked before anyone relies on them.

CleverTap was researched and then cut from v1. The reason is recorded at the bottom,
because "why is this missing" is the question a future reader will actually have.

## Source matrix

| Source | MCP | CLI | Auth and minimum read scope | Schema introspection |
|---|---|---|---|---|
| **PostHog** | Official remote: `https://mcp.posthog.com/mcp`, HTTP. `Authorization: Bearer phx_...`. Read-only via header `x-posthog-read-only: true`. Scope with `x-posthog-project-id`. Installer `npx @posthog/wizard mcp add` | none | Personal API key, "MCP Server" preset at `/settings/user-api-keys`. Query API needs Query Read. Definitions need `event_definition:read`, `property_definition:read` | `GET /api/projects/:id/event_definitions`, `GET /api/projects/:id/property_definitions?event_names=...` |
| **Mixpanel** | Official remote: `https://mcp.mixpanel.com/mcp` (EU `mcp-eu`, IN `mcp-in`). OAuth 2.1 PKCE-S256, or Service Accounts in beta | none | Scopes: `projects analysis events insights segmentation retention data:read funnels flows data_definitions`. Rate limit 600 MCP requests per hour per user | Use MCP tools `Get-Events`, `List-Properties`, `Get-Property-Values`. The REST Lexicon endpoint returns only entities with an explicit schema, so it under-reports |
| **Amplitude** | Official remote: `https://mcp.amplitude.com/mcp` (EU `https://mcp.eu.amplitude.com/mcp`). OAuth 2.0. Claude Code: `/plugin marketplace add amplitude/mcp-marketplace` | none | RBAC `USE_MCP_READ` / `USE_MCP_WRITE`. **Every role grants read. Member, Manager and Admin also grant write, so read-only requires a Viewer-tier role** | `GET https://amplitude.com/api/2/taxonomy/event`, `GET .../taxonomy/event-property?event_type=...`, HTTP Basic `api-key:secret-key` |
| **BigQuery** | Google MCP Toolbox for Databases, binary `toolbox`. `{"command":"./toolbox","args":["--prebuilt","bigquery","--stdio"],"env":{"BIGQUERY_PROJECT":"..."}}` | `bq` | ADC. Read-only roles `roles/bigquery.dataViewer` + `roles/bigquery.jobUser`. Set `BIGQUERY_MAXIMUM_BYTES_BILLED` | `INFORMATION_SCHEMA.COLUMN_FIELD_PATHS` |
| **Metabase** | Built in: `https://{host}/api/metabase-mcp`, Streamable HTTP, OAuth 2.0. Requires AI features enabled | none | `x-api-key` header, v0.47+. Key permissions come from the group it is assigned to at creation, not from superuser | `GET /api/database/:id/metadata` |
| **MongoDB** | Official `mongodb-mcp-server`: `npx -y mongodb-mcp-server@latest --readOnly`. Env `MDB_MCP_CONNECTION_STRING`, `MDB_MCP_READ_ONLY=true` | `mongosh` | DB user with built-in `read` role on the target DB only | Sample-infer, see below |
| **Postgres / Supabase** | Postgres: `postgres-mcp`, `{"command":"uvx","args":["postgres-mcp","--access-mode=restricted"],"env":{"DATABASE_URI":"..."}}`. Supabase: `https://mcp.supabase.com/mcp?project_ref=<ref>&read_only=true` | `psql`, `supabase` | Dedicated read-only role, see grants below. Supabase PAT plus `read_only=true` runs every query as a read-only Postgres user | `information_schema.columns` |

## Do not use

**`@modelcontextprotocol/server-postgres` is archived and carries an unpatched SQL
injection.** It still pulls 20k+ weekly npm downloads because stale tutorials keep
recommending it. It is the obvious choice and it is the wrong one. Use `postgres-mcp`
with `--access-mode=restricted`, or the Google Toolbox `--prebuilt=postgres`.

## Schema introspection

**Postgres and Supabase**, one round trip including column comments:

```sql
SELECT c.table_schema, c.table_name, c.column_name, c.ordinal_position,
       c.data_type, c.is_nullable, c.column_default,
       col_description(format('%I.%I', c.table_schema, c.table_name)::regclass,
                       c.ordinal_position) AS column_comment
FROM information_schema.columns c
JOIN information_schema.tables t
  ON t.table_schema = c.table_schema AND t.table_name = c.table_name
WHERE c.table_schema NOT IN ('pg_catalog','information_schema')
  AND t.table_type = 'BASE TABLE'
ORDER BY 1,2,4;
```

**BigQuery**, per dataset. Use `COLUMN_FIELD_PATHS` rather than `COLUMNS`: it flattens
nested RECORD and STRUCT paths, which is exactly where event-shaped data lives.

```sql
SELECT table_name, column_name, field_path, data_type, description
FROM `PROJECT.DATASET.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS`
ORDER BY table_name, field_path;
```

**MongoDB**, sample-infer, bounded and cheap:

```js
db.events.aggregate([
  { $sample: { size: 1000 } },
  { $project: { kv: { $objectToArray: "$$ROOT" } } },
  { $unwind: "$kv" },
  { $group: { _id: { f: "$kv.k", t: { $type: "$kv.v" } }, n: { $sum: 1 } } },
  { $sort: { n: -1 } }
]);
```

Sampling 1000 documents misses rare fields. Record the sample size in the schema file
so a reader knows the inferred schema is probabilistic, not complete.

**Event volumes.** PostHog via HogQL:
`SELECT event, count() FROM events WHERE timestamp > now() - INTERVAL 30 DAY GROUP BY event ORDER BY 2 DESC`.
Amplitude via the Segmentation API.

## Drift detection

There is no first-party schema-hash primitive in dbt, Metabase, or BigQuery. This is a
pattern you implement.

1. Run the introspection query, sort deterministically, keep
   `(schema, table, column, type, nullable)`.
2. `sha256` the canonical JSON. Store one hash per table plus a roll-up per source.
3. Re-hash on demand. A changed hash triggers a column-set diff into added, removed,
   and type_changed.

Keep the type in the hash. Column-name diffing catches adds and drops, but a widening
from `INT64` to `NUMERIC` changes downstream aggregations silently and a name-only
diff will not see it.

Cheap pre-filters before hashing: BigQuery
`SELECT table_id, last_modified_time FROM \`DATASET.__TABLES__\``, which is effectively
free since INFORMATION_SCHEMA is not billed like a table scan. Postgres
`pg_stat_user_tables.last_autoanalyze` is a hint only, not a schema signal.

For reference, dbt's idiomatic equivalent is diffing two `catalog.json` files from
`dbt docs generate`. Metabase runs a scheduled metadata sync and surfaces drift as new
or inactive fields.

## Read-only enforcement

Layer all four: role, session, limits, cost cap. Any one alone is bypassable.

**Postgres and Supabase.** The grants are the only real boundary:

```sql
CREATE ROLE agent_ro LOGIN PASSWORD '...';
REVOKE ALL ON DATABASE app FROM PUBLIC;
GRANT CONNECT ON DATABASE app TO agent_ro;
GRANT USAGE ON SCHEMA public TO agent_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO agent_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO agent_ro;

ALTER ROLE agent_ro SET default_transaction_read_only = on;
ALTER ROLE agent_ro SET statement_timeout = '15s';
ALTER ROLE agent_ro SET idle_in_transaction_session_timeout = '30s';
```

**`default_transaction_read_only` is not a security control.** Postgres documents it as
a client default, and a session can `SET` it back off. It catches accidents. The GRANT
set is what actually holds. Add a statement allowlist on top: one statement, must start
with `SELECT` or `WITH`, reject embedded `;`.

**BigQuery.** IAM `dataViewer` plus `jobUser`, never `dataEditor`. The cost cap is not
optional, because an unbounded scan is a spend:

```bash
bq query --use_legacy_sql=false --maximum_bytes_billed=1000000000 --max_rows=1000 'SELECT ...'
```

Also set a project-level custom quota, so a runaway agent cannot bill past it.

**MongoDB.** `--readOnly` plus a DB user holding only the built-in `read` role.

**Metabase.** Permissions follow the API key's group. Put the key in a group with
view-only data access and no native-query rights to block arbitrary SQL.

**PostHog and Supabase.** Use the server-side switches, `x-posthog-read-only: true` and
`?read_only=true`, in addition to a scoped key.

## Flags

- **PostHog GitHub repo** archived 19 Jan 2026, code folded into the monorepo. The hosted
  endpoint is current. **UNVERIFIED:** no currently published local npm package for
  self-hosting was found. Template the remote URL only.
- **Mixpanel Lexicon Schemas API**: path pattern confirmed via the reference index, but
  the OpenAPI spec 404'd, so sub-paths and query params are **UNVERIFIED**. Reported
  rate limit 5 requests per minute.
- **Amplitude MCP** is self-described as under active development with possible
  breaking changes.
- **Metabase MCP**: no minimum version or plan tier stated, and no API-key config path
  documented, OAuth only. **UNVERIFIED** against any specific instance version.
- **BigQuery Toolbox**: no read-only flag documented for the `bigquery` prebuilt
  toolset. Enforce read-only through IAM, not through server config.

## Why CleverTap was cut from v1

There is no first-party MCP server. More decisively, **there is no API that lists event
names**. `event_name` is a mandatory parameter on `/1/events.json`, and CleverTap's own
support repo confirms no listing endpoint exists, so `capture-schema` cannot introspect
it and the taxonomy would have to be hand-maintained forever.

Auth is `X-CleverTap-Account-Id` plus `X-CleverTap-Passcode`, with no scoping mechanism:
the passcode is all-or-nothing, so there is no read-only credential to issue.

The `mcp.clevertap.com` endpoint that appears in search results is **UNVERIFIED and
probably does not exist**. The one community wrapper has 6 stars and 3 commits.

Adding it later means adding a hand-maintained taxonomy file and a way to mark reports
built on it as unverified. That is a real feature, not a connector doc.
