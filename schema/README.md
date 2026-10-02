# schema

One directory per source: `schema/<source>/schema.md`. Captured, never guessed.

`_template/schema.md` is the format. Copy it, do not edit it in place.

Everything here except this README and `_template/` is gitignored. A capture holds your
real table and column names, so it stays on this machine.

## Why this exists

`AGENTS.md` says a column that is not in the captured schema is drift, not permission
to guess a name. That rule only works if the capture is real and recent. A schema file
written from memory is worse than no schema file, because the agent trusts it.

## Capture

1. Run the introspection query for that source. The template lists one per source
   type. It is a read.
2. Paste the result into the table listing. Keep type, nullability, and comment.
3. Record the capture date, the method, and the exact introspection query used.
4. Compute the hash and record it.

The introspection query goes in the file because a schema captured by an unknown
method cannot be reproduced or compared.

## The hash includes the type

Hash the sorted list of `table.column:type:nullable`, not just the names.

A name-only hash misses the change that matters most. Widening `INT64` to `NUMERIC`
leaves every column name identical, so a name-only diff reports no change. But the
aggregation changes: sums that used to overflow now do not, averages that used to
truncate now carry decimals, and a report charted across the change date shows a step
that nobody can explain. Same for `TIMESTAMP` to `TIMESTAMPTZ`, and for a nullable
column becoming `NOT NULL`, which changes what a `LEFT JOIN` returns.

Suggested command, run from the repo root:

```
grep -E '^\| ' schema/<source>/schema.md | awk -F'|' '{print $2":"$3":"$4":"$5}' | sort | shasum -a 256
```

Adjust the field numbers to match the template's column order. Whatever you use,
write the command into the schema file so the next capture uses the same one. Two
hashes computed different ways are not comparable.

## Refresh

Refresh when any of these is true:

- A query fails on an unknown column or table.
- A number changes and no product change explains it.
- The capture date is more than 30 days old and a report depends on the source.
- Anyone shipped a migration.

Run `skills/schema/refresh-schema`. Then record in `log.md` what changed, and which
existing reports depend on the changed field. That second half is the part people
skip, and it is the part that stops a stale number being requoted.

## Drift is not permission to guess

The agent needs `shipment_status` and the schema has `status`. The names are close.
Guessing is how a report ends up describing a column that means something else.

On drift the agent does one of two things:

- Refresh the schema, then requery against the refreshed capture.
- Stop, name the missing column, and say which part of the question it cannot answer.

It does not substitute a similar name, and it does not silently drop the part of the
question that needed the column.

## Sampled sources

MongoDB and any other schemaless source is inferred from a sample, not read from a
catalog. The template carries a banner for this and it stays in the file. A field
present in 1% of documents can be absent from a 1,000-document sample and still be
the field the question is about.
