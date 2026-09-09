# Source registry

One row per source. This table records how far each source has been verified. It
does not decide what you may query. Read it before any query, and when you query a
source marked `partial` or `blocked`, say so in one line in the output.

## What readiness means

CHARTER C-08: a source is ready only when it is authorized, read-scoped,
runtime-addressable, and observed through one bounded read. A stored credential
is not readiness. An env var being set proves someone typed a key. It does not
prove the key works, that it is scoped read-only, or that the endpoint answers.

| Readiness | Meaning |
|---|---|
| `blocked` | Not verified yet. Either nothing is connected, or the smoke test has never been run and passed. Querying it is allowed. Say in the output that the source is unverified. |
| `partial` | Credentials exist and are scoped, but no bounded read has been observed yet, or the last observed read was on a subset of what the source holds. Say so in every output. |
| `ready` | One bounded read from the connector doc's smoke test was actually run and returned rows. Record the date in the verification column. |

`blocked` means "nobody has proved this reads", not "forbidden". A number from a
`blocked` source is a real number that nobody has reconciled against an observed
read, and the report says which it is.

A row only moves to `ready` by a human or agent running the smoke test in
`sources/connectors/<name>.md` and seeing rows come back. `./setup.sh --check`
checks that the named env vars are set. That is a precondition, not readiness.
Nothing in this repo promotes a row to `ready` automatically.

Every row ships `blocked`, because nothing has been verified yet.

CleverTap is deliberately excluded from v1. The reason is in
`docs/connectors-research.md`: there is no API that lists event names, so the
taxonomy cannot be introspected, and the passcode auth has no read-only scope.

## Registry

| Source | Type | Env vars | Read-only mechanism | Readiness | Last verified | Notes |
|---|---|---|---|---|---|---|
| PostHog | event | `POSTHOG_API_KEY`, `POSTHOG_PROJECT_ID`, `POSTHOG_HOST`, `POSTHOG_MCP_URL` | Personal API key with read scopes only, plus `x-posthog-read-only: true` and `x-posthog-project-id` headers | blocked | never | Remote MCP only. No published local npm package found for self-hosting, UNVERIFIED. |
| Mixpanel | event | `MIXPANEL_PROJECT_ID`, `MIXPANEL_MCP_URL`, `MIXPANEL_SERVICE_ACCOUNT_USER`, `MIXPANEL_SERVICE_ACCOUNT_SECRET` | OAuth 2.1 PKCE with read scopes, or a service account limited to the read scope list | blocked | never | 600 MCP requests per hour per user. Service accounts for MCP are in beta. |
| Amplitude | event | `AMPLITUDE_MCP_URL`, `AMPLITUDE_API_KEY`, `AMPLITUDE_SECRET_KEY` | Viewer-tier RBAC role. Every role grants `USE_MCP_READ`, so the role is the only thing keeping write out | blocked | never | Amplitude describes its MCP as under active development with possible breaking changes. |
| BigQuery | warehouse | `BIGQUERY_PROJECT`, `BIGQUERY_DATASET`, `BIGQUERY_MAXIMUM_BYTES_BILLED`, `GOOGLE_APPLICATION_CREDENTIALS`, `TOOLBOX_BIN` | IAM `roles/bigquery.dataViewer` plus `roles/bigquery.jobUser`, plus a mandatory `maximum_bytes_billed` on every query | blocked | never | The `bigquery` prebuilt toolset has no read-only flag. IAM is the enforcement. |
| Metabase | BI | `METABASE_HOST`, `METABASE_API_KEY`, `METABASE_DATABASE_ID`, `METABASE_MCP_URL` | API key created inside a view-only group with no native query rights | blocked | never | Key permissions come from the group, not from the creating user. MCP path UNVERIFIED against any instance version. |
| MongoDB | database | `MDB_MCP_CONNECTION_STRING`, `MDB_MCP_READ_ONLY`, `MONGODB_DATABASE` | DB user with the built-in `read` role on one database, plus `--readOnly` and `MDB_MCP_READ_ONLY=true` | blocked | never | Schema is sample-inferred from 1000 documents, so it is probabilistic, not complete. |
| Postgres/Supabase | database | `DATABASE_URI`, `SUPABASE_PROJECT_REF`, `SUPABASE_ACCESS_TOKEN` | Dedicated `agent_ro` role whose GRANTs allow SELECT only. Supabase adds `read_only=true` on the MCP URL | blocked | never | `default_transaction_read_only` is a client default, not a security control. Never use `@modelcontextprotocol/server-postgres`. |

## Changing a row

1. Run the smoke test in the connector doc for that source.
2. If it returns rows, set Readiness and put today's date in the verification
   column. Name the exact query you ran in the Notes column or in `log.md`.
3. If a credential is rotated or a role changes, set the row back to `blocked`
   and re-run the smoke test. A verification date older than the credential is
   not a verification.
