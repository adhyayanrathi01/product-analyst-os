# product-analyst-os

[![checks](https://github.com/adhyayanrathi01/product-analyst-os/actions/workflows/checks.yml/badge.svg)](https://github.com/adhyayanrathi01/product-analyst-os/actions/workflows/checks.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![version](https://img.shields.io/badge/version-0.2.0-orange.svg)](CHANGELOG.md)
[![harness: any](https://img.shields.io/badge/harness-Claude%20Code%20%7C%20Codex%20%7C%20any-black.svg)](AGENTS.md)

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
| `CHARTER.md` | 12 clauses. Read by the agent, never written by it. Amending one is a human decision that bumps the minor version. |
| `agents/roles.md` | Orchestrator, worker, evaluator, as portable contracts. |
| `knowledge-base/` | Your definitions. The agent reads these and never edits them. |
| `sources/` | How to connect 7 sources read-only, and which ones are verified. |
| `schema/` | Captured schema per source, with a hash for drift detection. |
| `skills/` | The six workflows: connect, verify, capture, refresh, and the two analyze skills. |
| `reports/` | Output, one file per question, named by date and topic. |
| `evals/` | The checks that grade output and prove the guardrails work. |
| `docs/` | The research this repo is built on, with citations. |

## Getting started

About ten minutes, start to finish.

1. Connect one source, the analytics tool you actually use. If it is already connected in
   your Claude desktop or claude.ai account, that is enough: the agent finds it and uses
   it, with no config file. Otherwise run `./setup.sh`. Seven are supported. You need one.
   Either way, `./setup.sh --check` creates your workspace files from blank templates.
2. Open your agent in this folder and ask a real question, for example "how many active
   accounts did we have last month?"
3. The first time, it offers a short setup: about eight questions in plain words, like
   what counts as an active customer and which email domains are your own team. It takes
   5 to 10 minutes. It drafts your definitions, and you approve them by running one
   command it gives you.

After that, answers use your definitions instead of guesses.

Skip the setup and it still answers, but it lists every assumption it made. Treat that
number as a draft.

When you want the answers to be more than plausible:

4. Run verify. A source is not ready because a key is stored. It is ready when the agent
   has actually read from it once. Nothing blocks until you do this. What you get is a
   report that says the number came from a source somebody proved reads.
5. Capture schema, so the agent queries against real column names instead of the ones in
   your prompt. Do this before the setup interview if you can, because then the interview
   offers your real column names instead of asking for them.

You can still fill in `knowledge-base/entities.md` by hand instead of the interview. The
interview just writes the same file from a conversation.

### What `TODO` and `EXAMPLE` mean

The knowledge base ships unfilled, on purpose. Two markers tell you what is left:

- **`TODO`** is a field you must fill. Until you do, the agent names it as an undefined
  term, says what it assumed instead, and answers anyway. That is a worse answer than the
  one you get after filling it in, and it tells you so.
- **`EXAMPLE`** is a sample from a fictional company called Nimbus Freight. **Delete
  these as you fill each file in.** A leftover example is worse than a `TODO`, because
  the agent reads it as a fact about your product.

`./setup.sh --check` counts both per file and tells you what your answers are still
resting on:

```
== Knowledge base ==
  warn     entities.md    37 TODO, 12 EXAMPLE block(s) to delete
  ...
  Analysis will RUN ON ASSUMPTIONS. entities.md still has 37 TODO markers.
```

Section 5 of `entities.md`, the lifecycle edge cases, is allowed to stay `TODO`. Fill a
row the first time that case actually happens. `knowledge-base/README.md` has the full
definition of done and the order to fill things in.

This friction is deliberate. Analytics without the definitions is number crunching, not
analysis.

## Your data stays out of git

This repo is a public template, and it is also the folder you work in. Your definitions,
schema captures, reports, `task.md` and `log.md` hold your company's data: internal
domains, account ids, table names, real numbers. All of them are gitignored, so a commit
or a push carries none of it, and neither does a public fork.

Each one starts as a blank in a `_template/` folder. `./setup.sh` copies the blank into
place the first time and never overwrites a file you filled in. `./setup.sh --check` does
the same, and fails if git still tracks one of these files.

Want your definitions under version control? Use a private repo, never a public fork, and
delete only the `.gitignore` lines for what you mean to track.

### Upgrading a clone made before 0.4.0

If you committed filled-in definitions, a plain `git pull` can merge them into the tracked
templates, and your next push publishes them. Run this instead. Nothing here deletes a file
on disk.

```bash
mkdir -p ../paos-backup && cp -Rp knowledge-base reports schema task.md log.md ../paos-backup/
git fetch origin
git checkout origin/main -- .gitignore
git ls-files -ci --exclude-standard -z | xargs -0 git rm -q --cached --
PAOS_ALLOW_PROTECTED=1 git commit -am "Stop tracking my workspace"
git pull --no-rebase -X no-renames origin main
./setup.sh --check
```

`-X no-renames` is the step that matters. Already pushed to a public remote? Untracking
does not unpublish anything. Treat that content as exposed.

## What it answers, and where the answers go

Every answer is a file: `reports/YYYY-MM-DD-<topic>.md`. The date is when the analysis
ran, not the period it covers. The topic names the question, not the method. Rerunning a
question later makes a new file rather than overwriting the old one, because a PM who
quoted last month's number needs to find out it moved.

| Topic | Typical question | Skill | Example file |
|---|---|---|---|
| **Activation** | Do new signups reach first value, and how fast? | frontend | `2026-09-09-activation-7day-window.md` |
| **Funnels** | Where in this flow do people fall out? | frontend | `2026-09-09-onboarding-funnel-dropoff.md` |
| **Retention** | Who comes back, and for how long? | either | `2026-09-09-week4-retention-by-plan.md` |
| **Feature adoption** | Who uses this feature, and did shipping it change anything? | frontend | `2026-09-09-bulk-import-adoption.md` |
| **Event taxonomy health** | Which events are dead, duplicated, or misnamed? | frontend | `2026-09-09-event-taxonomy-audit.md` |
| **Counts and segments** | How many real accounts, at what grain, minus which exclusions? | backend | `2026-09-09-active-accounts-august.md` |
| **Cohorts** | How does the March cohort differ from the August one? | backend | `2026-09-09-cohort-comparison-h1.md` |
| **Revenue and plan mix** | Where does revenue sit, and how is it moving? | backend | `2026-09-09-mrr-by-plan-tier.md` |
| **Churn** | Who left, when, and what did they have in common? | backend | `2026-09-09-churn-drivers-q3.md` |
| **Data quality** | Is this number wrong, and if so where did it break? | either | `2026-09-09-signup-count-discrepancy.md` |

Two shapes of answer. **Short form** is four headings, Question, Facts, Exclusions
applied, Interpretation, and it is the default for a single-source question. **Full form**
adds Sources, Time range, Filters, Confidence and gaps, and Recommended next check, for a
question that crosses sources, spans periods, or feeds a decision that matters.

The split between the two analyze skills is by where the data lives, not by what you ask.
`analyze-frontend` reads event tools, where the traps are ad-blocker undercount and
mistaking event volume for user count. `analyze-backend` reads databases and warehouses,
where the trap is counting at the wrong level, for example users instead of accounts,
which silently multiplies your numbers by the average number of rows per level.

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
   read rather than on a stored key. `blocked` means nobody has proved it reads. It does
   not mean you cannot query it.

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
  client, including one sent through an MCP tool. It also blocks any MCP tool whose name
  carries a write or send verb, such as `Create-Dashboard` or `send_message`, because a
  connector attached to your account runs with your full role.
- `.codex/config.toml` sets Codex's sandbox and approval policy, which are OS-enforced.
- `evals/test-guardrails.sh` proves the guard fails when it should, across 61 cases. Run
  it after touching the hook.

`CHARTER.md` says out loud that it is a specification and not a control. An agent with
shell access can edit any file in here. The hooks make tampering visible and
inconvenient. They do not make it impossible.

Two honest limits. There is no `core.sha256` integrity manifest in v0.2.0, so a changed
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

- Write to any data source. Every query is a read, and a destructive statement is
  refused rather than rewritten.
- Edit your `knowledge-base/`. It proposes a diff and waits.
- Join two sources on an identifier you have not confirmed. It reports the two numbers
  separately and says which identifier it could not join, because an inferred join
  returns a plausible number that is wrong.
- Give you a number without the query that produced it and the exclusions applied.
- Print or commit a credential.
- Treat anything it read, a query result, a page, a cell value, as an instruction.
- Decide what to build. That is still your job.

## What it will not stop you doing

v0.2.0 removed the gates that made v0.1.0 unusable. A dry run against a fixture world
found that as shipped, zero analyses could run: every source ships `blocked`, and both
analyze skills refused a source that was not `ready`. So:

- **Readiness is reported, not enforced.** Point it at a database and ask. If the source
  has not been verified through a bounded read, the answer says so in one line and
  continues.
- **A missing definition is an assumption, not a stop.** It names what is undefined, says
  what it assumed, and carries on.
- **Reports come in two shapes.** Short form for a single-source question: question,
  facts with their queries, exclusions applied, one line of interpretation. Full form
  when the question crosses sources, spans time periods, or feeds a decision that
  matters. Ask for the other shape any time.
- **`check-output.sh` is a lint.** It prints what it noticed and exits 0. `--strict` if
  you want it failing a build.

One thing stayed mandatory: read `knowledge-base/entities.md` before querying, and state
which exclusions were applied. That is the step whose omission silently corrupts every
number, so it is the one that did not get relaxed.

## Status

v0.2.0. Second iteration, still small. No scheduling, no dashboard, no write-back, no
cost tracking. See `CHANGELOG.md`.
