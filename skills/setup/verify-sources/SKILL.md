---
name: verify-sources
description: Prove each configured source is actually readable with one bounded read, then update Readiness in sources/sources.md. Use after connect-sources and before any analysis.
---

# Verify sources

<!-- CORE:BEGIN -->
## Contract

This skill is the only thing in the repo that may set a source to `ready`. It does that
by observing a read, not by trusting a claim.

It records a verification. It does not gate anything. An unverified source can still be
queried, and the analysis says in one line that it is unverified. What running this skill
buys is that the reader knows the source answered a real read on a real date.

**C-08** requires four conditions together. All four, or the source is not ready:

1. **Authorized.** A credential exists and the user is entitled to use it.
2. **Read-scoped.** The grant itself is read-only, not just the intent.
3. **Runtime-addressable.** The endpoint or binary resolves from this machine, now.
4. **Observed through one bounded read.** This agent ran a query and saw rows.

Three states must stay distinct in the output, because they get conflated constantly:

| State | What it means | Readiness |
|---|---|---|
| **user-reported** | The user says it works. No evidence in this repo. | `blocked` |
| **credential-present** | An env var is set and non-empty. Nothing was read. | `blocked` |
| **agent-observed** | This agent ran one bounded read and saw a row count. | `ready` |

Only agent-observed makes a source ready. A named connection is not readiness. A stored
credential is not readiness. A green dot in a vendor UI is not readiness.

Guarantees:

- Exactly one bounded read per source. Not zero, not a suite.
- Every read is a `SELECT` or the read-only API equivalent, carries a `LIMIT`, and for
  BigQuery carries `maximum_bytes_billed`.
- The Readiness cell and the Last verified date in `sources/sources.md` are updated for
  every source attempted, including the failures.

Refuses:

- To mark a source `ready` on the user's say-so, on a non-empty environment variable, on
  a successful handshake, or on an MCP server's `readOnlyHint`. The MCP spec calls tool
  annotations untrusted.
- To retry a failed read with a broader credential, a write-capable role, or a different
  endpoint the user did not configure.
- To print any part of a credential or connection string into `sources/sources.md`,
  `log.md`, or the chat, per **C-09**.
- To invent a row count. If the read returned nothing readable, the source is `blocked`
  with the error named, per **C-04** and **C-06**.

Bound by **C-08**, **C-04**, **C-06**, **C-09**, **C-02**.

## Output contract

**Required fields:**

- **Verified at**: absolute timestamp with timezone.
- Per source, all of:
  - **Source**
  - **Evidence state**: exactly one of `user-reported`, `credential-present`, `agent-observed`
  - **Bounded read run**: the literal query or API call, verbatim
  - **Result observed**: row count or item count returned, or the error text
  - **Read scope**: the role, scope string, or header enforcing read-only
  - **Readiness set**: `ready`, `partial`, or `blocked`
  - **Blocking condition**: which of the four C-08 conditions failed, or `none`
- **sources.md rows updated**: list of source names whose Readiness or Last verified changed.
- **Safe to analyze**: the list of sources now `ready`, and the list that is not.
<!-- CORE:END -->

## Process

1. Read `sources/sources.md`. Verify every row, including ones already marked `ready`.
   A stale `ready` from three weeks ago is a claim, not an observation.

2. Run exactly one bounded read per source. `sources/connectors/<source>.md` is the
   authority for its smoke test: if a connector doc and this list ever disagree, the
   connector doc wins and this list is the defect. The copies below are here so you can
   see the shape without opening seven files. Each is cheap and returns a countable
   result:

   **Postgres / Supabase**

   ```sql
   SELECT table_schema, table_name
   FROM information_schema.tables
   WHERE table_schema NOT IN ('pg_catalog','information_schema')
     AND table_type = 'BASE TABLE'
   ORDER BY 1,2
   LIMIT 5;
   ```

   **BigQuery**. The cost cap is part of the test, not a wrapper around it:

   ```bash
   bq query --use_legacy_sql=false \
     --maximum_bytes_billed="$BIGQUERY_MAXIMUM_BYTES_BILLED" --max_rows=5 \
     "SELECT table_id, last_modified_time
      FROM \`$BIGQUERY_PROJECT.$BIGQUERY_DATASET.__TABLES__\`
      ORDER BY table_id LIMIT 5"
   ```

   **MongoDB**

   ```js
   db.getSiblingDB(DB).getCollectionNames().slice(0, 5);
   ```

   **PostHog**. Read-only header included, because the header is the scope claim:

   ```bash
   curl -s -H "Authorization: Bearer $POSTHOG_API_KEY" \
        -H "x-posthog-read-only: true" \
        "https://app.posthog.com/api/projects/$POSTHOG_PROJECT_ID/event_definitions?limit=5"
   ```

   **Mixpanel**: call the MCP tool `Get-Events` and count the events returned.

   **Amplitude**

   ```bash
   curl -s -u "$AMPLITUDE_API_KEY:$AMPLITUDE_SECRET_KEY" \
        "https://amplitude.com/api/2/taxonomy/event" | head -c 2000
   ```

   **Metabase**

   ```bash
   # METABASE_HOST already includes the scheme. Do not prefix another one.
   curl -s -H "x-api-key: $METABASE_API_KEY" \
        "$METABASE_HOST/api/database/$METABASE_DATABASE_ID/metadata" | head -c 2000
   ```

3. Record the count returned. Zero rows is still an observation, but it is `partial`,
   not `ready`: the endpoint answered and the scope may be empty or wrong.

4. Check read scope separately from the read succeeding. A successful read proves
   conditions 1, 3 and 4. It does not prove condition 2. Confirm the grant:

   - Postgres: `SELECT current_setting('default_transaction_read_only');` and, more
     importantly, that the role holds only `SELECT`. `default_transaction_read_only` is a
     client default a session can turn off. It catches accidents. The GRANT set holds.
   - BigQuery: the principal has `dataViewer` and `jobUser`, never `dataEditor`.
   - Amplitude: the user's role tier. Anything above Viewer also grants `USE_MCP_WRITE`.
   - Metabase: the API key's group has no native-query rights.
   - MongoDB: the server was started with `--readOnly` and the DB user holds `read`.

   If the read works but the scope is write-capable, set Readiness to `partial` and name
   it. Do not set `ready`.

5. Update the row in `sources/sources.md`: Readiness and the Last verified date, as an
   absolute date with timezone. Change nothing else in that file.

6. Append to `log.md`: what was verified, the state per source, and anything unverified.

7. State plainly which sources were verified and which were not. `analyze-frontend` and
   `analyze-backend` will query either kind. They name the readiness state in the output
   so the reader knows which numbers came from a source nobody has read from yet.

## Failure modes

- **A working handshake is mistaken for readiness.** An MCP server connects, lists its
  tools, and nothing was actually read. Check: the output must quote a literal query and
  a literal count. No query text in the output means the source stays `blocked`.

- **A read-only header is trusted as a boundary.** `x-posthog-read-only: true` is sent by
  the client. A client can stop sending it. Check: the Read scope field must name a
  server-side grant, not only a header. Header-only equals `partial`.

- **Amplitude verified from a Member account.** The read succeeds, so it looks ready, but
  the same role grants `USE_MCP_WRITE`. Check: ask for the role tier explicitly. Not
  Viewer means `partial`.

- **BigQuery verified without a cost cap and the "verification" bills a full scan.**
  Check: the recorded command must contain `--maximum_bytes_billed` or the MCP env must
  contain `BIGQUERY_MAXIMUM_BYTES_BILLED`. Missing means the read did not run.

- **Zero rows reported as success.** An empty project answers 200 with an empty list.
  Check: if the count is 0, Readiness is `partial` and the output says the scope may be
  pointed at the wrong project.

- **A previously `ready` row is skipped to save time.** Credentials expire, projects get
  archived, OAuth tokens rotate. Check: every row in `sources/sources.md` must appear in
  this run's output, or the run is incomplete.

- **A connection string leaks into `sources.md`.** Check: grep the diff for `://` and for
  `password`. Any match, revert the write.
