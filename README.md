# product-analyst-os

A workspace that lets an AI agent answer questions about your product's usage without
making numbers up.

It connects to your analytics tools and databases read-only, captures their schema so
the agent stops guessing column names, holds your definitions of active, demo and
internal in one file, and refuses to hand you a number without the query that produced
it.

Works with Claude Code, Codex, and any harness that reads `AGENTS.md`. The rules live in
one file, not three.

## Why this exists

Ask an agent "how many active users did we have last month" and you usually get a
confident number that is wrong. Not because the model is bad, but because:

- Nobody told it your demo accounts and your employees are in that table.
- It guessed a column name that sounds right.
- It resolved "last month" against today, not against your reporting calendar.
- It answered from a dashboard tile that was itself filtered.
- The number arrived without the query, so nobody could check it.

Each of those is a workspace problem, not a model problem. This repo fixes them by
making the definitions explicit, the schema captured, and the query mandatory.

## What is in here

| Path | What it is |
|---|---|
| `AGENTS.md` | Every operating rule. The single source. |
| `CLAUDE.md` | `@AGENTS.md` plus Claude-specific mechanics. |
| `CHARTER.md` | 12 immutable clauses. Read, never written. |
| `agents/roles.md` | Orchestrator, worker, evaluator, as portable contracts. |
| `knowledge-base/` | Your definitions. The agent reads these and never edits them. |
| `sources/` | How to connect 7 sources read-only, and which ones are verified. |
| `schema/` | Captured schema per source, with a hash for drift detection. |
| `skills/` | The six workflows: connect, verify, capture, refresh, and the two analyze skills. |
| `reports/` | Output, one file per question, named by date and topic. |
| `evals/` | The checks that grade output and prove the guardrails work. |
| `docs/` | The research this repo is built on, with citations. |

## Getting started

```bash
./setup.sh
```

Then, in this order:

1. **Fill in `knowledge-base/entities.md` first.** Everything else is downstream of it.
   If the agent does not know what "active" means or which accounts are internal, every
   number it produces is wrong in a way that looks right.
2. Point your agent at your sources, and make the credentials read-only.
3. Run verify. A source is not ready because a key is stored. It is ready when the agent
   has actually read from it once.
4. Capture schema, so the agent queries against real column names.
5. Ask a question.

### What `TODO` and `EXAMPLE` mean

The knowledge base ships unfilled, on purpose. Two markers tell you what is left:

- **`TODO`** is a field you must fill. The agent treats a `TODO` as a missing definition
  and stops rather than guessing.
- **`EXAMPLE`** is a sample from a fictional company called Nimbus Freight. **Delete
  these as you fill each file in.** A leftover example is worse than a `TODO`, because
  the agent reads it as a fact about your product.

`./setup.sh --check` counts both per file and tells you whether analysis is unblocked:

```
== Knowledge base ==
  warn     entities.md    37 TODO, 12 EXAMPLE block(s) to delete
  ...
  Analysis is BLOCKED. entities.md still has 37 TODO markers.
```

Section 5 of `entities.md`, the lifecycle edge cases, is allowed to stay `TODO`. Fill a
row the first time that case actually happens. `knowledge-base/README.md` has the full
definition of done and the order to fill things in.

This friction is deliberate. Analytics without the definitions is number crunching, not
analysis.

## Sources

PostHog, Mixpanel, Amplitude, BigQuery, Metabase, MongoDB, Postgres and Supabase.

**If you already have these connected, that is fine. Connecting was never the hard part.**
Most of these ship official remote MCP servers, and Claude Code and Codex both install
them in a click. `sources/connectors/<name>.md` is not an installation guide. It exists
for the three things an official connector does not give you:

1. **A read-only credential.** An official connector will happily use a read-write key,
   because it has no opinion about that. Three are easy to get wrong. Amplitude grants
   MCP read to *every* role, so read-only needs a Viewer-tier role specifically. Postgres
   `default_transaction_read_only` is not a security control, a session can unset it, so
   the `GRANT` set is the only real boundary. BigQuery's MCP Toolbox has no read-only flag
   at all, so it is IAM plus a mandatory `maximum_bytes_billed` and a project quota.
2. **The schema introspection query** for that source, so `capture-schema` pulls real
   column names instead of the agent guessing. BigQuery needs
   `INFORMATION_SCHEMA.COLUMN_FIELD_PATHS`, not `COLUMNS`, or nested event fields vanish.
3. **A bounded smoke test**, so a source can move from `blocked` to `ready` on an observed
   read rather than on a stored key.

The one installation warning worth reading anyway: **never use
`@modelcontextprotocol/server-postgres`.** It is archived with an unpatched SQL injection
and still pulls 20k+ weekly downloads from stale tutorials.

CleverTap was researched and cut from v1. It has no API that lists event names, so the
schema cannot be captured, and its passcode auth has no read-only scope. The reasoning
is in `docs/connectors-research.md` rather than deleted, because "why is this missing"
is a fair question.

## The guardrails are real

Prose in an instructions file is guidance. The model can ignore it. So the actual
enforcement is in the harness:

- `.claude/settings.json` denies edits to the charter, the rules, and your knowledge
  base, and denies reads of `.env`.
- `.claude/hooks/guard.py` covers what settings cannot: Claude Code's path rules do not
  apply to `Write` at all, so a deny rule there is silently ignored. The hook also blocks
  shell paths around the deny rules and any destructive statement aimed at a database
  client.
- `.codex/config.toml` sets Codex's sandbox and approval policy, which are OS-enforced.
- `evals/test-guardrails.sh` proves the guard fails when it should, across 19 cases. Run
  it after touching the hook.

`CHARTER.md` says out loud that it is a specification and not a control. An agent with
shell access can edit any file in here. The hooks make tampering visible and
inconvenient. They do not make it impossible.

Two honest limits. There is no `core.sha256` integrity manifest in v0.1.0, so a changed
CORE region in a skill is not currently detectable. And Codex's `workspace-write` sandbox
bounds writes to this repo but does not protect files inside it, so under Codex the
knowledge-base and charter rules have no enforcement beyond the prose.

### Protection that is not tied to one harness

The hook above only exists under Claude Code. Codex fences the folder, not the files in
it. Other harnesses have nothing. Writing one guard per vendor means rewriting it every
time a vendor changes its API, so instead there is one mechanism every harness sees,
the filesystem:

```bash
./setup.sh --protect          # chmod the rule files and the knowledge base read-only
./setup.sh --protect --status # list what is locked and what is not
./setup.sh --unprotect        # make them writable again
```

`--protect` locks `CHARTER.md`, `AGENTS.md`, `CLAUDE.md`, `setup.sh`, every
`skills/**/SKILL.md`, `.claude/`, `.githooks/pre-commit` and `evals/*.sh`. It locks
`knowledge-base/` only once `entities.md` has no `TODO` markers left, because you have to
write to those files to finish setup, and locking you out on day one would be a bug, not
a guardrail. `--protect --force` locks it unfilled if you really mean to. It also wires
`.githooks/pre-commit`, which refuses any commit touching a protected path and names the
files it saw. To commit one on purpose: `PAOS_ALLOW_PROTECTED=1 git commit -m "..."`.

**Its limit, plainly: `chmod` is a speed bump.** Anyone who can run `chmod a-w` can run
`chmod u+w`, and an agent with shell access is anyone. This is not a security boundary
and does not become one. What it buys is that the accidental write fails on every harness
instead of only on Claude Code, and the deliberate write costs a separate visible step
that shows up in a transcript. `./setup.sh --check` reports how many protected files are
currently writable, as a warning, since a fresh clone is unprotected on purpose.

## What it will not do

- Write to any data source. Every query is a read.
- Edit your `knowledge-base/`. It proposes a diff and waits.
- Join two sources on an identifier you have not confirmed.
- Give you a number without the query, the date range, and the exclusions applied.
- Decide what to build. That is still your job.

## Status

v0.1.0. First iteration, deliberately small. No scheduling, no dashboard, no write-back,
no cost tracking.
