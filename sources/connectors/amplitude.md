# Amplitude

Type: event. Access: official remote MCP server, plus the Taxonomy API for
schema introspection and the Segmentation API for event volumes.

## Env vars

| Name | What it is |
|---|---|
| `AMPLITUDE_MCP_URL` | `https://mcp.amplitude.com/mcp`, or `https://mcp.eu.amplitude.com/mcp` for EU. |
| `AMPLITUDE_API_KEY` | Project API key. Username half of the Taxonomy API Basic auth. |
| `AMPLITUDE_SECRET_KEY` | Project secret key. Password half of the same pair. |

## Create the read-only credential

Read this part carefully, because the default is not what you want.

Amplitude gates MCP with two RBAC permissions, `USE_MCP_READ` and
`USE_MCP_WRITE`. **Every role grants `USE_MCP_READ`.** Member, Manager and Admin
also grant `USE_MCP_WRITE`. So there is no way to hand a Member account an MCP
connection and call it read-only.

**Read-only requires putting the account in a Viewer-tier role.** That is the
whole control. Steps:

1. Create or pick a dedicated account for the agent.
2. Assign it a Viewer-tier role in the org, one that does not carry
   `USE_MCP_WRITE`.
3. Confirm in the role's permission list that `USE_MCP_WRITE` is absent.
4. Scope the account to the one project you intend to read.

The API key and secret key pair is per project. It is used for the Taxonomy and
Segmentation REST APIs, not for MCP auth.

## Connect

MCP auth is OAuth 2.0. The client runs the flow.

```json
{
  "type": "http",
  "url": "${AMPLITUDE_MCP_URL}"
}
```

Claude Code has a marketplace entry:

```bash
/plugin marketplace add amplitude/mcp-marketplace
```

## Schema introspection

Taxonomy API, HTTP Basic auth with `api-key:secret-key`:

```bash
curl -s -u "$AMPLITUDE_API_KEY:$AMPLITUDE_SECRET_KEY" \
  "https://amplitude.com/api/2/taxonomy/event"

curl -s -u "$AMPLITUDE_API_KEY:$AMPLITUDE_SECRET_KEY" \
  "https://amplitude.com/api/2/taxonomy/event-property?event_type=signup_completed"
```

## Event volumes

Use the Segmentation API. Always pass an explicit start and end date. Resolve
"last 30 days" to real dates before you send the request, so the number in the
report carries a real range.

## Limits to set

- One project per key pair.
- Bound every Segmentation call with an explicit date range.
- Do not use an Admin account to run the agent, even temporarily. An Admin
  account has `USE_MCP_WRITE`, which means the MCP connection can change event
  taxonomy. That is a write, and writes need per-action approval (CHARTER C-02).

## Smoke test

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  -u "$AMPLITUDE_API_KEY:$AMPLITUDE_SECRET_KEY" \
  "https://amplitude.com/api/2/taxonomy/event"
```

Expect `200` and a non-empty event list. Then, through MCP, list the available
tools and confirm no write-shaped tool is exposed. If a write tool appears, the
account is not Viewer-tier. Fix the role before marking the source `ready`.

## Gotchas

- **Every role grants MCP read.** Read-only is achieved by choosing a Viewer-tier
  role, not by a server flag. There is no read-only switch to set.
- Amplitude describes its MCP server as under active development, with possible
  breaking changes. Pin nothing to its exact tool names in a skill without a
  fallback, and re-run the smoke test after any client update.
- EU data lives behind the EU endpoint. Pointing at the US endpoint returns an
  empty or partial answer rather than an error, which is the worst failure mode
  in this doc: it looks like a real result.
- The MCP server's tool annotations are not a boundary. The role is.
