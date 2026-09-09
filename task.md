# Current task

## Goal

Ship v0.1.0: connect 7 analytics sources read-only, capture their schema, and answer
product usage questions in a checkable format.

## Status

Repo built. Nothing is connected yet, which is the expected state for a fresh clone.

All 7 sources in `sources/sources.md` are `blocked`. That is correct, not a failure.
A source becomes `ready` only after `verify-sources` performs one bounded read against
it, per CHARTER C-08. A stored credential is not readiness.

`knowledge-base/` is empty template. No analysis can run until `entities.md` is filled
in, because every query depends on knowing what active means and which accounts are
internal.

## Blockers

None technical. The repo is waiting on human input, in this order:

1. `knowledge-base/entities.md` needs the grain (account or user), the active
   definition, and the exclusion rules. This blocks all analysis.
2. Read-only credentials need to be created per source and named in `.env`. The steps
   are in `sources/connectors/<source>.md`.

## Next action

1. Run `./setup.sh` and choose which sources to connect.
2. Fill in `knowledge-base/entities.md`. Start there, not with the connectors.
3. Run `verify-sources` to move sources from blocked to ready.
4. Run `capture-schema` per ready source.
5. Ask the first real question and check the report against
   `./evals/check-output.sh reports/<file>`.

## Open questions for the maintainer

- Several connector facts are marked UNVERIFIED in `docs/connectors-research.md`,
  specifically the Mixpanel Lexicon sub-paths, the Metabase MCP API-key path, and
  whether a local PostHog MCP package exists. Confirm against a real instance before
  relying on them.
- No `core.sha256` integrity manifest yet. The CORE fences exist in every skill, but
  nothing hashes them, so a drifted core region is not currently detectable.
- No `.claude/rules/` directory. Progressive disclosure is by convention through
  `index.md`, not enforced by a mechanism. See `docs/harness-practices.md`.
- Under Codex, `workspace-write` does not protect files inside the repo, so C-12 and the
  knowledge-base rule are prose only there. Claude Code enforces them via `guard.py`.
