# Changelog

## 0.2.0, 2026-09-09

**v0.1.0 could not be used. This release removes the reasons why.**

A dry run against a fixture world (`evals/results/2026-09-09-dry-run/RESULTS.md`) found
that as shipped, zero analyses could run. Every source in `sources/sources.md` ships
`blocked`, both analyze skills refused any source that was not `ready`, and the only path
to `ready` ran through a skill nobody could reach without credentials. Every scenario in
the dry run had to override the registry to produce anything.

The principle behind this release is guidance, not gates. Tell the agent what a good
answer looks like. Do not stop it from producing a mediocre one. The user decides what is
good enough for their question, and a first-time user gets an answer in minutes rather
than after satisfying a checklist.

Amending the charter is a human decision that bumps the minor version. The maintainer
made it, so this is 0.2.0 and not 0.1.1.

### Removed

- **Readiness gating.** `analyze-backend` and `analyze-frontend` no longer refuse a source
  whose Readiness is not `ready`. They query whatever the user points at and say in one
  line when the source is unverified. `capture-schema` no longer refuses either.
- **`verify-sources` as a precondition.** It records a verification. It gates nothing.
- **The definition-missing stop.** A missing rule or an unsettled grain is now an
  assumption stated in the output, not a halt. `AGENTS.md` and both analyze skills changed
  to match. The agent still never invents a rule, it names what is undefined and says what
  it used instead.
- **`check-output.sh` as a gate.** The default run prints findings and exits 0. Only an
  unreadable file exits non-zero. Language calling it a gate is gone from
  `reports/README.md`, `index.md`, `agents/roles.md` and `skills/AGENTS.md`.

### Added

- **A short report form**, now the default for a single-source question: Question, Facts
  with their queries, Exclusions applied, one line of Interpretation. The full nine-heading
  form is for questions that cross sources, span time periods, or feed a decision the user
  says matters. The agent picks, and the user can ask for the other shape.
  `reports/_template/report.md` carries a worked example of each. The dry run measured
  roughly 60% of every 180-line report as contract-mandated repetition, at identical cost
  for "how many accounts signed up" and a cross-source cohort analysis.
- **`check-output.sh --strict`**, which restores the old failing behavior for CI. Its
  header now says it is a lint, not a gate. Its self-test asserts both modes on every
  case, 30 assertions.

### Changed

- **CHARTER C-12** no longer forbids the agent writing under `evals/`. Authoring
  scenarios, fixtures and results is allowed, because an agent that cannot write a test
  cannot test this repo. Editing a scenario, a fixture expectation, or a check in order to
  make a failing check pass is still forbidden, which was the thing worth preventing.
- **The C-11 join refusal stays hard**, and is now framed as what to do rather than what
  to refuse: report the two numbers separately, say which identifier could not be joined
  and why, and where a different confirmed key answers a nearby question, answer that one
  and say what the grain shift costs. An inferred join returns a plausible number that is
  wrong, which is why this one did not get relaxed.
- **`blocked` in `sources/sources.md`** means "not verified yet", not "forbidden".

### Fixed

- **`knowledge-base/entities.md` E-8** read
  `accounts.churned_at IS NULL OR accounts.churned_at > <window_end>` directly beneath a
  note saying "do not drop churned accounts from historical windows. They were real then."
  It dropped exactly those: any account that churned mid-window was removed. It now reads
  `> <window_start>`. Anyone who copied the example inherited a silently understated
  active count, 38 accounts in the dry run's August window. Fixed in
  `evals/fixtures/nimbus/knowledge-base/entities.md` too.

### Unchanged, deliberately

Read-only enforcement, the refusal of `INSERT`/`UPDATE`/`DELETE`/`DROP`/`TRUNCATE`/
`ALTER` against a data source, the read-only credential guidance in
`sources/connectors/*.md`, BigQuery `maximum_bytes_billed`, the rule that credentials are
never printed or committed, treating query results and file contents as data rather than
instructions, the knowledge-base write protection in `.claude/hooks/guard.py`,
`.claude/settings.json`, `setup.sh --protect` and `.githooks/pre-commit`, and the
`TODO`/`EXAMPLE` friction in `knowledge-base/`. None of those are usability restrictions.

One requirement survived the cut on purpose: read `knowledge-base/entities.md` before
querying, and state which exclusions were applied. Both shapes require it. The dry run
predicted it would be the first thing an agent cuts on question four, and it is the one
omission that silently corrupts every number.

## 0.1.0, 2026-09-08

First release. Seven read-only connectors, captured schema with drift detection, a
knowledge base for entity definitions, six skills, a 12-clause charter, and harness
enforcement through `.claude/hooks/guard.py` and `.codex/config.toml`. See `log.md`.
