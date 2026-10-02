---
paths:
  - "schema/**/*.md"
---
<!-- Restates AGENTS.md "Schema is captured, not guessed" for the moment you touch a schema file. If this ever disagrees with AGENTS.md or a SKILL.md, they win. -->

# Working in schema/

- A column or event that is not in the capture is drift. It is not permission to guess a name.
- On drift, run `skills/schema/refresh-schema`, or stop and name the column you could not find. Do not substitute a similar name. Do not drop the part of the question that needed it.
- A removed column plus an added one with a close name is two facts. It is not a rename. Only the PM can claim a rename.
- A type change is drift. `INT64` to `NUMERIC` keeps every column name and changes every `SUM` and `AVG`.
- Never write a column, type or event name that introspection did not return. A gap is written as a gap. A schema written from memory is worse than none.
- Log each schema assumption in `log.md` when you make it, and on a refresh, name every report under `reports/` that uses a changed field.
- Copy `_template/schema.md`. Do not edit the template in place.
- MongoDB and other schemaless sources are sampled. Keep the sampled-source banner. A rare field can be missing from the sample.
- The hash covers `(schema, table, column, type, nullable)`. Record the exact hash command in the file so the next capture is comparable.
- Connection strings never go in a schema file. Name the env var only.
