# Metabase

Type: BI. Access: built-in MCP endpoint, plus the REST API with an API key.

## Env vars

| Name | What it is |
|---|---|
| `METABASE_HOST` | Instance base URL, for example `https://metabase.example.com`. |
| `METABASE_API_KEY` | Sent as the `x-api-key` header. Requires v0.47 or later. |
| `METABASE_DATABASE_ID` | Numeric database id inside Metabase. |
| `METABASE_MCP_URL` | `https://{host}/api/metabase-mcp`. Requires AI features enabled. |

## Create the read-only credential

The important part: **an API key's permissions come from the group it is
assigned to at creation, not from the superuser who created it.** Creating a key
as an admin does not make it an admin key, and it does not make it a safe key
either. The group is the control.

1. Create a group, for example `agent-readonly`.
2. Give that group view-only data access to the databases the agent needs.
3. Remove native query rights from the group. Without native query permission
   the key cannot run arbitrary SQL, which is the boundary that matters here.
4. Create the API key in Settings, Authentication, API keys, and assign it to
   that group.
5. Store it as `METABASE_API_KEY`.

## Connect

REST, which is the verified path:

```bash
curl -s -H "x-api-key: $METABASE_API_KEY" \
  "$METABASE_HOST/api/database/$METABASE_DATABASE_ID/metadata"
```

MCP, Streamable HTTP with OAuth 2.0:

```json
{
  "type": "http",
  "url": "${METABASE_MCP_URL}"
}
```

The MCP endpoint requires AI features enabled on the instance.

## Schema introspection

```bash
curl -s -H "x-api-key: $METABASE_API_KEY" \
  "$METABASE_HOST/api/database/$METABASE_DATABASE_ID/metadata"
```

This returns tables and fields as Metabase has them after its own metadata sync,
which is not always what the underlying database has right now. Metabase runs a
scheduled sync and surfaces drift as new or inactive fields. Treat the Metabase
view as a second opinion on the warehouse, not as the source of truth for schema.

## Limits to set

- No native query rights on the group, so arbitrary SQL is not reachable.
- View-only data access on the specific databases the agent needs, not all.
- One key per agent, so revoking one does not break the others.

## Smoke test

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  -H "x-api-key: $METABASE_API_KEY" \
  "$METABASE_HOST/api/database/$METABASE_DATABASE_ID/metadata"
```

Expect `200` with a table list. A `401` means the key is wrong or the instance
is older than v0.47. A `403` means the key's group cannot see that database.

Second check, and do not skip it: try a native query through the API and confirm
it is refused. A key that can run native SQL is not read-only, whatever the
group settings screen says.

## Gotchas

- **Key permissions come from the group the key is created in.** This is the
  single most common way a Metabase key ends up with more access than intended.
- API keys need Metabase v0.47 or later.
- **UNVERIFIED:** the MCP endpoint has no stated minimum version and no stated
  plan tier, and no API-key config path is documented for it, OAuth only. It has
  not been verified against any specific instance version. Use the REST path
  until you have confirmed MCP works on your instance.
- A number read off a Metabase dashboard tile is not a query result. If a figure
  came from a cached tile, say so and name the tile (CHARTER C-05).
