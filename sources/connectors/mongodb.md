# MongoDB

Type: database. Access: official `mongodb-mcp-server`, plus `mongosh`.

## Env vars

| Name | What it is |
|---|---|
| `MDB_MCP_CONNECTION_STRING` | Connection string for the read-only DB user. Read by the MCP server directly. |
| `MDB_MCP_READ_ONLY` | Set to `true`. |
| `MONGODB_DATABASE` | Target database name for introspection and the smoke test. |

## Create the read-only credential

Create a database user that holds the built-in `read` role on the target
database only. Not `readAnyDatabase`, not `readWrite`, and not a cluster-wide
role.

```js
db.getSiblingDB("admin").createUser({
  user: "agent_ro",
  pwd: passwordPrompt(),
  roles: [ { role: "read", db: "app" } ]
});
```

Replace `app` with your database. One role, one database. If the agent needs a
second database later, add a second `read` entry deliberately rather than
widening to `readAnyDatabase`.

## Connect

```json
{
  "command": "npx",
  "args": ["-y", "mongodb-mcp-server@latest", "--readOnly"],
  "env": {
    "MDB_MCP_CONNECTION_STRING": "${MDB_MCP_CONNECTION_STRING}",
    "MDB_MCP_READ_ONLY": "true"
  }
}
```

Both layers, the `--readOnly` flag and the `read`-role user. The flag is a
server setting and a server setting can be changed by whoever launches the
server. The role is enforced by the database. Keep both.

## Schema introspection

MongoDB has no schema catalog, so the schema is inferred by sampling. Bounded
and cheap:

```js
db.events.aggregate([
  { $sample: { size: 1000 } },
  { $project: { kv: { $objectToArray: "$$ROOT" } } },
  { $unwind: "$kv" },
  { $group: { _id: { f: "$kv.k", t: { $type: "$kv.v" } }, n: { $sum: 1 } } },
  { $sort: { n: -1 } }
]);
```

Grouping on both the field name and the BSON type matters. A field that is a
string in old documents and an int in new ones shows up as two rows, which is
exactly the drift you want to catch.

**Record the sample size in `schema/mongodb/schema.md`.** A reader must know the
inferred schema is probabilistic, not complete.

## Limits to set

- `$sample` size of 1000. Raise it deliberately and record the new number.
- A `limit` on every find. A collection scan on a large collection is slow and
  can evict the working set from cache.
- One database per connection string.

## Smoke test

```bash
mongosh "$MDB_MCP_CONNECTION_STRING" --quiet --eval \
  'db.getSiblingDB(process.env.MONGODB_DATABASE).getCollectionNames().slice(0,5)'
```

A list of collection names means auth, network and the `read` grant are all
working. Then run the aggregation above with `size: 50` as a one-off and confirm
field rows come back.

Third check: attempt one write and confirm it is refused. A connection that can
write is not read-only, whatever the flag says.

## Gotchas

- **Sampling 1000 documents misses rare fields.** A field present on 0.05 percent
  of documents will usually not appear. An absent field in the captured schema
  is not proof the field does not exist. Say so when a report depends on it.
- `--readOnly` is a server flag, not a database permission. Alone it stops
  nothing if someone launches the server without it. The `read` role is the
  boundary.
- `readAnyDatabase` looks convenient and quietly hands the agent every database
  on the cluster, including ones with data nobody meant to expose.
- Never write the connection string into a report, a schema file or `log.md`
  (CHARTER C-09). Refer to it as `MDB_MCP_CONNECTION_STRING`.
