# Postgres and Supabase

Type: database. Access: `postgres-mcp` for self-hosted Postgres, the Supabase
remote MCP server for Supabase, plus `psql` and the `supabase` CLI.

## Do not use `@modelcontextprotocol/server-postgres`

**It is archived and carries an unpatched SQL injection.** It still pulls more
than 20,000 weekly npm downloads because stale tutorials keep recommending it.
It is the obvious choice and it is the wrong one. Never add it to a config in
this repo.

Use `postgres-mcp` with `--access-mode=restricted`, or the Google MCP Toolbox
with `--prebuilt=postgres`.

## Env vars

| Name | What it is |
|---|---|
| `DATABASE_URI` | Connection URI for the read-only role. Read by `postgres-mcp` directly. |
| `SUPABASE_PROJECT_REF` | Supabase project ref, the subdomain in the project URL. |
| `SUPABASE_ACCESS_TOKEN` | Supabase personal access token. |

## Create the read-only credential

The GRANTs are the only real boundary. Run this as a superuser, once:

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

`ALTER DEFAULT PRIVILEGES` matters: without it, a table created tomorrow is
invisible to `agent_ro` and the agent reports a table as missing when it is only
unreadable.

## Connect

Self-hosted Postgres:

```json
{
  "command": "uvx",
  "args": ["postgres-mcp", "--access-mode=restricted"],
  "env": { "DATABASE_URI": "${DATABASE_URI}" }
}
```

Supabase, remote:

```json
{
  "type": "http",
  "url": "https://mcp.supabase.com/mcp?project_ref=${SUPABASE_PROJECT_REF}&read_only=true"
}
```

`read_only=true` makes Supabase run every query as a read-only Postgres user.
Keep it in the URL. It is a server-side switch, so it is a real layer, but it is
still a switch someone can drop from a config, which is why the role grants
below it still matter.

## Schema introspection

One round trip, including column comments:

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

Column comments are worth the join. They are often the only place a team wrote
down what a column actually means.

## Limits to set

Layer all four. Any one alone is bypassable.

1. **Role.** The GRANT set above. This is what actually holds.
2. **Session.** `statement_timeout = '15s'` and
   `idle_in_transaction_session_timeout = '30s'`, so a bad query cannot hold a
   connection open.
3. **Statement allowlist, in the agent.** One statement per call, it must start
   with `SELECT` or `WITH`, reject any embedded `;`.
4. **Row cap.** A `LIMIT` on every query.

`pg_stat_user_tables.last_autoanalyze` is sometimes suggested as a drift
pre-filter. It is a hint about vacuum activity, not a schema signal. Do not
build drift detection on it.

## Smoke test

```bash
psql "$DATABASE_URI" -c \
  "SELECT table_schema, table_name FROM information_schema.tables
   WHERE table_type = 'BASE TABLE'
     AND table_schema NOT IN ('pg_catalog','information_schema')
   LIMIT 5"
```

Rows back means the role can connect and read the catalog. Then confirm the
boundary actually holds:

```bash
psql "$DATABASE_URI" -c "CREATE TABLE agent_ro_should_fail (x int)"
```

This must fail with a permission error. If it succeeds, the GRANTs are wrong.
Drop the table and fix the role before marking the source `ready`.

## Gotchas

- **`default_transaction_read_only` is not a security control.** Postgres
  documents it as a client default and a session can `SET` it back off. It
  catches accidents. The GRANT set is what actually holds the line.
- `@modelcontextprotocol/server-postgres` is archived with an unpatched SQL
  injection. Never use it, whatever a tutorial says.
- `GRANT SELECT ON ALL TABLES` covers tables that exist right now. New tables
  need `ALTER DEFAULT PRIVILEGES`, which is in the block above for exactly this
  reason.
- On Supabase, dropping `read_only=true` from the URL silently upgrades the
  connection. Check the URL, not the docs, when a write unexpectedly succeeds.
- Views can leak past a table-level GRANT if a view was defined by a role with
  wider access. Check what `agent_ro` can actually see, do not assume.
