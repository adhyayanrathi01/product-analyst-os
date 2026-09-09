# Current task

## Goal

Ship v0.2.0: answer product usage questions in a checkable format, against whatever
sources the user has, without a checklist standing between the question and the answer.

v0.1.0 connected 7 analytics sources read-only and captured their schema. It also gated
every one of those steps on the previous one, and a dry run proved that as shipped, zero
analyses could run. v0.2.0 removes those gates. Rigor is the shape of a good answer now,
not a condition for producing one.

## Status

Repo built. Nothing is connected yet, which is the expected state for a fresh clone.

All 7 sources in `sources/sources.md` are `blocked`. `blocked` means nobody has proved
the source reads. It does not mean you cannot query it. A source becomes `ready` after
`verify-sources` observes one bounded read, per CHARTER C-08, and until then an answer
drawn from it says in one line that the source is unverified.

`knowledge-base/` is an empty template. Analysis will run against it, and every answer
will carry the assumptions it had to make in place of the definitions that are still
`TODO`. Filling in `entities.md` is what turns those assumptions into facts, and it is
still the highest-value thing to do first.

## Blockers

None. The repo answers questions in whatever state it is in, and says what it did not
know.

Two things make the answers better, in this order:

1. `knowledge-base/entities.md` needs the grain (account or user), the active definition,
   and the exclusion rules. Everything else is downstream of it.
2. Read-only credentials per source, named in `.env`. The steps are in
   `sources/connectors/<source>.md`.

## Next action

1. Run `./setup.sh` and choose which sources to connect.
2. Ask a question. Read what the answer says it assumed.
3. Fill in `knowledge-base/entities.md` for whatever the answer had to assume.
4. Run `verify-sources` and `capture-schema` when you want the numbers reconciled against
   an observed read and real column names.
5. `./evals/check-output.sh reports/<file>` lints a report. It reports and exits 0. Read
   what it says.

## Open questions for the maintainer

- `.claude/hooks/guard.py` still lists `evals/` as a protected path, while amended C-12
  now allows an agent to author evals and `.githooks/pre-commit` does not protect
  `evals/`. Two enforcement layers, two answers. Pick one list. `.claude/**` was out of
  scope for the v0.2.0 change.
- `check-output.sh` still cannot tell a report that applied its exclusions from one that
  only named them. The grep that would catch it is specified in
  `skills/analytics/analyze-backend/SKILL.md` under Failure modes and is roughly ten
  lines. It is now advisory either way, so the cost of adding it is low.
- Several connector facts are marked UNVERIFIED in `docs/connectors-research.md`,
  specifically the Mixpanel Lexicon sub-paths, the Metabase MCP API-key path, and
  whether a local PostHog MCP package exists. Confirm against a real instance before
  relying on them.
- No `core.sha256` integrity manifest yet. The CORE fences exist in every skill, but
  nothing hashes them, so a drifted core region is not currently detectable. The v0.2.0
  output-contract change edited two CORE regions, which is exactly the event a manifest
  would have recorded.
- No `.claude/rules/` directory. Progressive disclosure is by convention through
  `index.md`, not enforced by a mechanism. See `docs/harness-practices.md`.
- Under Codex, `workspace-write` does not protect files inside the repo, so C-12 and the
  knowledge-base rule are prose only there. Claude Code enforces them via `guard.py`.
