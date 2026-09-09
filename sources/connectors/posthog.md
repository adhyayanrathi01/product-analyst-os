# PostHog

Type: event. Access: official remote MCP server, plus the REST API for schema
introspection and HogQL for event volumes.

## Env vars

| Name | What it is |
|---|---|
| `POSTHOG_API_KEY` | Personal API key, prefix `phx_`. Read scopes only. |
| `POSTHOG_PROJECT_ID` | Numeric project id. Scopes every call to one project. |
| `POSTHOG_HOST` | Regional API host, for example `https://us.posthog.com`. |
| `POSTHOG_MCP_URL` | `https://mcp.posthog.com/mcp` |

## Create the read-only credential

1. Go to `/settings/user-api-keys` in PostHog.
2. Create a personal API key using the **MCP Server** preset.
3. Confirm the scopes include, and are limited to:
   - Query Read, needed for the Query API and HogQL.
   - `event_definition:read`
   - `property_definition:read`
4. Scope the key to the single project you intend to read.

There is no separate read-only key type. The read-only guarantee comes from the
scope list plus the `x-posthog-read-only: true` header below. Both, not either.

## Connect

Remote HTTP MCP server. Headers carry the key, the read-only switch, and the
project scope.

```json
{
  "type": "http",
  "url": "${POSTHOG_MCP_URL}",
  "headers": {
    "Authorization": "Bearer ${POSTHOG_API_KEY}",
    "x-posthog-read-only": "true",
    "x-posthog-project-id": "${POSTHOG_PROJECT_ID}"
  }
}
```

PostHog also ships an installer that writes this block for you:

```bash
npx @posthog/wizard mcp add
```

Run it yourself. `setup.sh` never installs anything.

## Schema introspection

Events, then properties for the events you care about:

```bash
curl -s -H "Authorization: Bearer $POSTHOG_API_KEY" \
  "$POSTHOG_HOST/api/projects/$POSTHOG_PROJECT_ID/event_definitions"

curl -s -H "Authorization: Bearer $POSTHOG_API_KEY" \
  "$POSTHOG_HOST/api/projects/$POSTHOG_PROJECT_ID/property_definitions?event_names=signup_completed"
```

## Event volumes

HogQL through the Query API:

```sql
SELECT event, count()
FROM events
WHERE timestamp > now() - INTERVAL 30 DAY
GROUP BY event
ORDER BY 2 DESC
```

## Limits to set

- One project per key. Do not issue an org-wide key.
- Always send `x-posthog-read-only: true`, even though the scopes already block
  writes. Two layers, because either one can be misconfigured.
- Bound every HogQL query with a date range and a `LIMIT`. `events` is large and
  an open-ended scan is slow and expensive.

## Smoke test

A bounded read that proves the key, the project scope and the endpoint all work:

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  -H "Authorization: Bearer $POSTHOG_API_KEY" \
  "$POSTHOG_HOST/api/projects/$POSTHOG_PROJECT_ID/event_definitions?limit=5"
```

Expect `200`. A `401` means the key is wrong. A `403` means the scopes are too
narrow. Then run the HogQL query above with `LIMIT 5` added and confirm rows
come back. Only after rows come back does the row in `sources/sources.md` move
off `blocked`.

## Gotchas

- The PostHog MCP GitHub repo was archived on 19 January 2026 and the code was
  folded into the monorepo. The hosted endpoint is the current path.
- **UNVERIFIED:** no currently published local npm package for self-hosting was
  found. Template the remote URL only. Do not write a local-server config that
  has not been confirmed to exist.
- The key is a personal API key. It carries the permissions of the person who
  created it, so create it from an account that has read access only.
- Never treat the MCP server's own `readOnlyHint` as the boundary. The MCP spec
  calls annotations untrusted. The scope list is the boundary.
