# BigQuery

Type: warehouse. Access: Google MCP Toolbox for Databases, plus the `bq` CLI.

## Env vars

| Name | What it is |
|---|---|
| `BIGQUERY_PROJECT` | GCP project that owns the data and runs the jobs. |
| `BIGQUERY_DATASET` | Default dataset for introspection and the smoke test. |
| `BIGQUERY_MAXIMUM_BYTES_BILLED` | Hard cost cap in bytes on every query. `1000000000` is 1 GB. |
| `GOOGLE_APPLICATION_CREDENTIALS` | Path to the service account key file for Application Default Credentials. Leave unset if you use user ADC. |
| `TOOLBOX_BIN` | Path to the Toolbox binary, for example `./toolbox`. |

## Create the read-only credential

Auth is Application Default Credentials. The read-only guarantee is IAM and
nothing else.

Grant exactly two roles, at the dataset or project level:

```bash
gcloud projects add-iam-policy-binding "$BIGQUERY_PROJECT" \
  --member="serviceAccount:agent-ro@$BIGQUERY_PROJECT.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataViewer"

gcloud projects add-iam-policy-binding "$BIGQUERY_PROJECT" \
  --member="serviceAccount:agent-ro@$BIGQUERY_PROJECT.iam.gserviceaccount.com" \
  --role="roles/bigquery.jobUser"
```

`dataViewer` reads data. `jobUser` lets it run a query job. Never grant
`roles/bigquery.dataEditor`. Run these yourself. `setup.sh` never calls `gcloud`.

Also set a project-level custom query quota in BigQuery, so a runaway agent
cannot bill past a ceiling even if a per-query cap is forgotten.

## Connect

MCP, through the Toolbox binary in stdio mode:

```json
{
  "command": "${TOOLBOX_BIN}",
  "args": ["--prebuilt", "bigquery", "--stdio"],
  "env": {
    "BIGQUERY_PROJECT": "${BIGQUERY_PROJECT}",
    "BIGQUERY_MAXIMUM_BYTES_BILLED": "${BIGQUERY_MAXIMUM_BYTES_BILLED}"
  }
}
```

CLI, for the same reads:

```bash
bq query --use_legacy_sql=false \
  --maximum_bytes_billed="$BIGQUERY_MAXIMUM_BYTES_BILLED" \
  --max_rows=1000 'SELECT ...'
```

## Already connected in your client

A BigQuery connector attached to your Claude desktop or claude.ai account runs
as you, usually with more than `dataViewer` and `jobUser`, so it is not
read-scoped and verifies to `partial` at best. Under Claude Code,
`.claude/hooks/guard.py` blocks write SQL and write-named tools, on the client
side only. Check the query tool's input fields for a bytes-billed cap. If it has
none, `maximum_bytes_billed` is not enforceable on that path: say so, prefer
`INFORMATION_SCHEMA` reads, use a dry-run field if the tool has one, and ask
before any scan. The
same gap applies to BigQuery reached through Metabase, see
`sources/connectors/metabase.md`.

## Schema introspection

Per dataset. Use `COLUMN_FIELD_PATHS`, not `COLUMNS`. `COLUMN_FIELD_PATHS`
flattens nested RECORD and STRUCT paths, which is exactly where event-shaped
data lives. `COLUMNS` shows the top-level RECORD and stops there.

```sql
SELECT table_name, column_name, field_path, data_type, description
FROM `PROJECT.DATASET.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS`
ORDER BY table_name, field_path;
```

Cheap drift pre-filter, effectively free because `INFORMATION_SCHEMA` is not
billed like a table scan:

```sql
SELECT table_id, last_modified_time
FROM `${BIGQUERY_PROJECT}.${BIGQUERY_DATASET}.__TABLES__`
ORDER BY table_id
LIMIT 5;
```

## Limits to set

- `maximum_bytes_billed` on every single query. This is mandatory, not a default
  you can lean on. An unbounded scan is a spend, and spend needs approval.
- `--max_rows=1000` on CLI reads, and a `LIMIT` in the SQL itself.
- A project-level custom quota as the backstop.

## Smoke test

Bounded, cheap, and it proves both roles at once:

```bash
bq query --use_legacy_sql=false \
  --maximum_bytes_billed="$BIGQUERY_MAXIMUM_BYTES_BILLED" \
  --max_rows=5 \
  "SELECT table_name, column_name, data_type
   FROM \`$BIGQUERY_PROJECT.$BIGQUERY_DATASET.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS\`
   LIMIT 5"
```

Rows back means `dataViewer` and `jobUser` are both in place and the project and
dataset names resolve. A permission error naming `bigquery.jobs.create` means
`jobUser` is missing, not `dataViewer`.

## Gotchas

- **The `bigquery` prebuilt toolset has no documented read-only flag.** There is
  no server-side switch to set. Read-only is enforced through IAM, not through
  server config. If the IAM binding is wrong, nothing else in this file stops a
  write.
- A query that would exceed `maximum_bytes_billed` fails before it runs. That is
  the intended behavior. Raise the cap deliberately and say why, do not remove it.
- Dry runs still cost nothing, so use `--dry_run` to size a scan before running
  a query you are unsure about.
- Do not confuse a dataset-level `dataViewer` grant with a project-level one. A
  dataset-level grant will pass the smoke test on one dataset and fail on the
  next, which reads as intermittent breakage.
