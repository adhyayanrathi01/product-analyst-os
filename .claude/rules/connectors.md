---
paths:
  - "sources/connectors/**/*.md"
---
<!-- Restates AGENTS.md "Read-only by default" and "Protect credentials", plus facts from the connector docs. If this ever disagrees with AGENTS.md or a connector doc, they win. -->

# Working in sources/connectors/

- Read-only is the credential's grants. It is not an MCP server flag and it is not a `readOnlyHint`. The MCP spec calls annotations untrusted.
- Keep a server-side read-only switch where one exists (`postgres-mcp --access-mode=restricted`, MongoDB `--readOnly`, PostHog `x-posthog-read-only`), and also set the grant. The switch can be dropped from a config. The grant cannot.
- Never template, recommend or add `@modelcontextprotocol/server-postgres`. It is archived with an unpatched SQL injection and still tops search results. Use `postgres-mcp` restricted or the Google MCP Toolbox.
- BigQuery has no read-only flag in the prebuilt toolset. IAM is the only boundary: `dataViewer` plus `jobUser`, never `dataEditor`. Every query sets `maximum_bytes_billed`.
- Amplitude: every role grants MCP read, so read-only means a Viewer-tier role.
- Metabase: a key's permissions come from its group. A key that can run native SQL is not read-only.
- Mixpanel: Lexicon REST under-reports. Use the MCP tools.
- Postgres: `default_transaction_read_only` is a client default, not a control. The GRANT set is.
- A smoke test that must fail (a write attempt) is part of proving a boundary. Do not skip it.
- Anything not confirmed against a real instance stays flagged `UNVERIFIED`. Do not write it as fact.
- Env var names only. Never a value or a connection string, in a doc, an example or a log.
