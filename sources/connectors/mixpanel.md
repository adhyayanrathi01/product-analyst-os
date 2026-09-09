# Mixpanel

Type: event. Access: official remote MCP server only. There is no Mixpanel CLI.

## Env vars

| Name | What it is |
|---|---|
| `MIXPANEL_PROJECT_ID` | Project id. Scopes every tool call to one project. |
| `MIXPANEL_MCP_URL` | Region endpoint, see below. |
| `MIXPANEL_SERVICE_ACCOUNT_USER` | Service account username. Only for the service account path. |
| `MIXPANEL_SERVICE_ACCOUNT_SECRET` | Service account secret. Read scopes only. |

Region endpoints:

- US: `https://mcp.mixpanel.com/mcp`
- EU: `https://mcp-eu.mixpanel.com/mcp`
- IN: `https://mcp-in.mixpanel.com/mcp`

Use the endpoint for the region your project is in. A US endpoint will not see
EU project data.

## Create the read-only credential

Two paths.

**OAuth 2.1 with PKCE, code challenge method S256.** The default. The client
runs the flow, you approve the scopes in the browser, no secret lands in `.env`.

**Service accounts.** In beta for MCP. Create the service account in project
settings and grant only these scopes:

```
projects analysis events insights segmentation retention
data:read funnels flows data_definitions
```

Every scope in that list is a read scope. Do not add anything outside it. There
is no import or write scope in the set, and that absence is the read-only
boundary.

## Connect

```json
{
  "type": "http",
  "url": "${MIXPANEL_MCP_URL}"
}
```

OAuth is handled by the client at first connect, so no header is stored. If you
use the beta service account path, the client sends
`${MIXPANEL_SERVICE_ACCOUNT_USER}` and `${MIXPANEL_SERVICE_ACCOUNT_SECRET}` as
HTTP Basic credentials instead.

## Schema introspection

Use the MCP tools, not the REST Lexicon endpoint:

- `Get-Events` lists event names.
- `List-Properties` lists properties for an event.
- `Get-Property-Values` lists observed values for a property.

The REST Lexicon Schemas endpoint returns only entities that have an explicit
schema defined, so it under-reports. An event that is tracked but never given a
Lexicon schema will not appear. Introspecting through Lexicon alone produces a
taxonomy that looks complete and is not.

## Limits to set

- 600 MCP requests per hour per user. A loop that calls `List-Properties` once
  per event will hit that on a large taxonomy. Batch by fetching the event list
  first and only expanding the events the question needs.
- Reported rate limit on the Lexicon Schemas API is 5 requests per minute.
- Always pass the project id so a multi-project account cannot read the wrong
  project by default.

## Smoke test

Call `Get-Events` for `${MIXPANEL_PROJECT_ID}` and confirm it returns a non-empty
event list. Then call `List-Properties` for exactly one event from that list.
Two bounded calls, well inside the hourly budget, and they prove auth, project
scope and taxonomy access in one pass.

If the client cannot list tools at all, the OAuth flow did not complete. Re-run
the client's connect step before touching credentials.

## Gotchas

- The Lexicon Schemas API path pattern was confirmed from the reference index,
  but the OpenAPI spec returned 404, so the sub-paths and query parameters are
  **UNVERIFIED**. Do not build introspection on them. Use the MCP tools.
- Service accounts for MCP are in beta. A beta auth path can change without a
  deprecation window, so prefer OAuth unless you need headless access.
- 600 requests per hour is per user, not per project. Two agents sharing one
  account share one budget.
