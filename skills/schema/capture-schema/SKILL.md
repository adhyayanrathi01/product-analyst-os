---
name: capture-schema
description: First-run schema capture for one source. Introspects real column and event metadata, writes schema/<source>/schema.md and a deterministic sha256. Use once per source after verify-sources.
---

# Capture schema

<!-- CORE:BEGIN -->
## Contract

Records what a source actually contains, so every later query is written against
captured metadata rather than a guessed column name.

Guarantees:

- Introspection only. No table data is read except MongoDB's bounded `$sample`, which is
  required because Mongo has no schema catalog.
- Writes exactly two files per source: `schema/<source>/schema.md` and
  `schema/<source>/schema.sha256`. Nothing else.
- The hash covers the tuple `(schema, table, column, type, nullable)` for every column,
  sorted deterministically by that same tuple, serialized as canonical JSON. Type is
  inside the hash on purpose: a widening from `INT64` to `NUMERIC` changes downstream
  aggregations and a name-only diff never sees it.
- One hash per table plus one roll-up per source, so `refresh-schema` can skip unchanged
  tables.
- For MongoDB, the recorded sample size and an explicit statement that the schema is
  probabilistic.

Refuses:

- To run against a source whose Readiness in `sources/sources.md` is not `ready`.
  Capturing from an unverified source per **C-08** produces a schema nobody can trust.
- To infer, complete, or prettify a column name, type, or event name that introspection
  did not return, per **C-04**. A gap is written as a gap, per **C-06**.
- To use BigQuery `INFORMATION_SCHEMA.COLUMNS`. It hides nested `RECORD` and `STRUCT`
  paths, which is exactly where event-shaped data lives. `COLUMN_FIELD_PATHS` only.
- To claim a Mongo sample-inferred schema is complete.
- To write anything outside `schema/<source>/`.

Bound by **C-04**, **C-06**, **C-08**, **C-09** (no connection string in a schema file),
**C-02** (introspection never becomes a write).

## Output contract

**Required fields** in `schema/<source>/schema.md`:

- **Source**
- **Captured at**: absolute timestamp with timezone
- **Captured by**: the literal introspection query or API call, verbatim
- **Capture method**: `catalog` or `sampled`
- **Sample size**: the number of documents sampled, or `n/a` for catalog capture
- **Completeness**: `complete` for catalog capture, `probabilistic` for sampled
- **Objects**: table or collection or event count
- **Columns**: total column, field, or property count
- **Per object**: name, and per column: `column`, `type`, `nullable`, `description` where
  the source carries one
- **Unreadable**: every object that introspection could not return, with the reason
- **Roll-up hash**: the sha256 that also lives in `schema/<source>/schema.sha256`
- **Per-table hashes**: table name to sha256

**Required in the chat response:** Source, Capture method, Objects, Columns, Roll-up
hash, Unreadable, Files written.
<!-- CORE:END -->

## Process

1. Read `sources/sources.md`. If the source is not `ready`, stop and say which C-08
   condition is missing. Run `verify-sources` first.

2. Run the introspection for that source kind. Use these queries verbatim.

   **Postgres and Supabase.** One round trip, column comments included:

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

   **BigQuery.** Per dataset. `COLUMN_FIELD_PATHS`, never `COLUMNS`:

   ```sql
   SELECT table_name, column_name, field_path, data_type, description
   FROM `PROJECT.DATASET.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS`
   ORDER BY table_name, field_path;
   ```

   Set `maximum_bytes_billed` on the job even though `INFORMATION_SCHEMA` is cheap. The
   rule is unconditional so nobody has to remember the exception.

   **MongoDB.** Sample-infer, per collection:

   ```js
   db.events.aggregate([
     { $sample: { size: 1000 } },
     { $project: { kv: { $objectToArray: "$$ROOT" } } },
     { $unwind: "$kv" },
     { $group: { _id: { f: "$kv.k", t: { $type: "$kv.v" } }, n: { $sum: 1 } } },
     { $sort: { n: -1 } }
   ]);
   ```

   Record `size: 1000` as the Sample size and set Completeness to `probabilistic`. Write
   this sentence into the schema file: "Inferred from 1000 sampled documents. Fields
   present in fewer than roughly 1 in 1000 documents are likely missing from this file."
   A field appearing with two `$type` values is a real polymorphic field, not noise.
   Record both types.

   **PostHog.**

   ```
   GET /api/projects/:id/event_definitions
   GET /api/projects/:id/property_definitions?event_names=<event>
   ```

   Optionally record volumes via HogQL:
   `SELECT event, count() FROM events WHERE timestamp > now() - INTERVAL 30 DAY GROUP BY event ORDER BY 2 DESC`.

   **Amplitude.**

   ```
   GET https://amplitude.com/api/2/taxonomy/event
   GET https://amplitude.com/api/2/taxonomy/event-property?event_type=<event>
   ```

   HTTP Basic with `api-key:secret-key`.

   **Mixpanel.** Use the MCP tools `Get-Events`, `List-Properties`, `Get-Property-Values`.
   Do not use the REST Lexicon endpoint as the primary source: it returns only entities
   with an explicit schema, so it under-reports. If you use it anyway, say so and mark
   the capture `partial`. Mixpanel MCP is rate limited to 600 requests per hour per user,
   so batch by event rather than looping per property.

   **Metabase.** `GET /api/database/:id/metadata`.

3. Normalize every source into the same tuple: `(schema, table, column, type, nullable)`.
   For event sources, map: schema is the project, table is the event name, column is the
   property, type is the property type, nullable is whether the property is optional. For
   BigQuery use `field_path` as the column so nested paths survive.

4. Compute hashes. Sort by the tuple, serialize as canonical JSON with sorted keys and no
   whitespace, then sha256. One hash per table, then sha256 over the sorted list of
   per-table hashes for the roll-up. Deterministic sort is the whole point: an unstable
   order makes every refresh look like drift.

   ```bash
   jq -S -c '[.[] | {schema,table,column,type,nullable}] | sort_by(.schema,.table,.column,.type,.nullable)' \
     cols.json | shasum -a 256 | cut -d' ' -f1
   ```

5. Write `schema/<source>/schema.md` with every required field, then
   `schema/<source>/schema.sha256` containing the roll-up hash alone.

6. Note anything unreadable: a permission-denied dataset, a collection that timed out, an
   event with no property definitions. Name it in **Unreadable**. Do not omit it.

7. Update `index.md` to map the new schema file, and append the capture to `log.md`.

## Failure modes

- **BigQuery nested fields silently missing.** `INFORMATION_SCHEMA.COLUMNS` returns the
  `RECORD` column and none of its children, so `properties.plan_tier` never appears and a
  later query invents it. Check: the schema file must contain at least one `field_path`
  containing a dot for any dataset that has a `RECORD` column. If it has zero dots, the
  wrong view was queried.

- **Mongo schema treated as complete.** A field present in 0.3% of documents does not
  appear in a 1000-document sample, so a later query filters on it and returns zero rows,
  which reads as a real finding. Check: Completeness must be `probabilistic` and Sample
  size must be a number. If either is missing, the file is invalid.

- **Hash changes on every run with no schema change.** Caused by unsorted input, included
  `ordinal_position`, or an embedded capture timestamp. Check: run the hash step twice
  back to back on the same introspection output. The two hashes must be byte-identical.

- **Type dropped from the hash to make diffs quieter.** Then `INT64` widening to `NUMERIC`
  passes as unchanged and every average shifts. Check: mutate one type in a copy of the
  input and confirm the hash changes.

- **Mixpanel taxonomy under-reported from Lexicon.** Events that were never given an
  explicit schema are absent, so the file looks like a small clean taxonomy. Check: cross
  the event count against a 30-day volume query. A large gap means Lexicon was used.

- **Capture run against a `blocked` source and written anyway.** Check: the first step of
  every run is reading `sources/sources.md`. If the Readiness value is not in the output,
  the check did not happen.

- **A schema file carries a connection string in the "Captured by" field.** Check: grep
  the written file for `://`, `password`, and any configured secret variable's value
  pattern before finishing.
