# product-analyst-os, v0.1.0 design

Date: 2026-09-08
Status: approved, built

## Problem

An agent asked a product usage question produces a confident wrong number. The causes
are workspace-level, not model-level: undefined segments, guessed column names,
unresolved relative dates, numbers arriving without their query, and no distinction
between a stored credential and a working connection.

## Scope

Connect 7 sources read-only, capture their schema, hold definitions in one place,
and answer usage questions in a checkable format.

In: PostHog, Mixpanel, Amplitude, BigQuery, Metabase, MongoDB, Postgres and Supabase.

Out of v1, deliberately: scheduling, dashboards, write-back to any source, cost
tracking, and CleverTap.

## Decisions

**Standalone repo, conventions reused from product-manager-os.** The proven skeleton
(`AGENTS.md` plus `CLAUDE.md` import, charter, index/task/log, CORE fences, evals) is
copied in shape but not in content. The alternative, a folder inside the existing repo,
was rejected because this needs to be separately installable.

**setup.sh configures and verifies, and never installs.** It writes config, prints
per-source read-only credential steps, and checks prerequisites. It never runs a package
manager, never runs an auth flow, and never handles a secret value. Verification is a
separate step that performs one bounded read, because CHARTER C-08 says a stored
credential is not readiness.

**Blank public template.** No company data ships. `knowledge-base/` and `schema/` are
templates with examples clearly labeled as examples.

**CleverTap cut.** No API lists event names, so `capture-schema` cannot introspect it,
and its passcode auth has no read-only scope. Supporting it would mean a hand-maintained
taxonomy plus a mechanism to mark reports built on it as unverified. That is a feature,
not a connector doc. Reasoning preserved in `docs/connectors-research.md`.

**Three roles, defined as contracts rather than as a harness primitive.** Orchestrator,
worker, evaluator live in `agents/roles.md` with a seven-field brief. A harness with
subagents maps a role to one. A harness without runs the same contract as a sequential
pass. This is what keeps the repo model-agnostic, since subagent primitives change every
few months while a written contract does not.

**Evaluation is two layers.** `evals/check-output.sh` is deterministic and checks
structure: required fields, absolute dates, exclusions stated, no leaked secrets. The
evaluator role is judgment and checks reasoning: traceable numbers, correlation not sold
as cause, gaps not papered over. Structure passing with judgment failing is still a fail.

**Enforcement is in the harness, not in prose.** Anthropic's docs state that permission
rules are enforced by Claude Code and not by the model. So hard prohibitions live in
`.claude/settings.json` and a `PreToolUse` hook, with `.codex/config.toml` covering
Codex's two dials. `CHARTER.md` states its own limits rather than implying it is a
control.

Two mechanics drove the implementation. Claude Code path rules do not apply to `Write`,
so a `Write(path)` deny rule is accepted and never consulted, which is why `guard.py`
exists. And rules evaluate deny, then ask, then allow, first match wins, so a broad deny
cannot carry exceptions.

## Architecture

`knowledge-base/entities.md` is the root dependency. Both analyze skills load it before
any query and state which exclusions they applied, so the definition of "active" cannot
drift between the frontend and backend paths.

The analyze split is by source type. `analyze-frontend` reads event tools, where the
traps are ad-blocker undercount, event volume mistaken for user count, and timestamp
timezone. `analyze-backend` reads SQL and document sources, where the trap is the B2B
account grain versus the B2C user grain, which silently double-counts when confused.

Schema capture writes a normalized dump plus a `sha256` over
`(schema, table, column, type, nullable)`. Type is in the hash because a widening from
`INT64` to `NUMERIC` changes aggregations and a name-only diff misses it. Refresh is the
one skill that legitimately delegates, since per-source introspection is parallel,
read-heavy and independent, satisfying all four delegation conditions.

## Risks

Prose rules can be ignored by the model, which is why the hook exists, and the hook
itself only covers the paths it knows about. A hand-maintained knowledge base goes stale
silently, and nothing here detects that. Several connector facts are marked UNVERIFIED in
the research and are templated with that flag rather than presented as confirmed.
