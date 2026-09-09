# Log

Append-only. What was done, what was assumed, and what is unverified, so a fresh
session can resume without the transcript.

---

## 2026-09-08, v0.1.0 built

**Built.** Repo scaffolded from the conventions in `product-manager-os`, scoped to
product analytics. Core contract files, guardrails, 7 connectors, 6 skills,
knowledge-base templates, report and schema contracts, two research docs.

**Researched first.** Two areas, both written to `docs/` with citations: agent harness
practices, and connector reality for 8 candidate sources.

**Decisions and why.**

- CleverTap cut from v1. No API lists event names, so schema capture is impossible, and
  its passcode auth has no read-only scope. Reasoning kept in
  `docs/connectors-research.md` rather than deleted.
- `@modelcontextprotocol/server-postgres` deliberately not templated. It is archived
  with an unpatched SQL injection and still pulls 20k+ weekly downloads from stale
  tutorials. Using `postgres-mcp --access-mode=restricted` instead. This is the single
  most likely mistake anyone rebuilding this repo would make.
- Guardrails moved out of prose and into the harness after research confirmed that
  permission rules are enforced by Claude Code, not by the model.

**Assumptions made, and they are assumptions.**

- The 200-line target for instruction files is Anthropic's guidance for Claude Code
  specifically. Treated as directional. No source gives a defensible universal number.
- Postgres read-only is enforced through GRANTs, not through
  `default_transaction_read_only`, which Postgres documents as a client default that a
  session can unset. If a future maintainer relaxes the grants and relies on the session
  setting, the read-only guarantee is gone.
- MongoDB schema capture samples 1000 documents, so an inferred schema misses rare
  fields. This is recorded in each capture rather than hidden.

**Unverified.** Carried forward from the research and flagged in place: Mixpanel Lexicon
schema sub-paths (OpenAPI spec 404'd), Metabase MCP minimum version and API-key config
path (docs show OAuth only), and whether a published local PostHog MCP package exists
for self-hosting. None of these are blockers for the remote endpoints.

**Verified.** `evals/test-guardrails.sh` passes 19 of 19, covering protected-path writes
via `Write` (which Claude Code's own path rules do not cover), shell reads of `.env`,
redirects into protected files, destructive SQL aimed at a database client, and
fail-closed behavior on unparseable hook input. The allow cases confirm normal work is
not blocked.

**Known gap.** No `core.sha256` manifest. The CORE fences are in place in every skill but
nothing hashes them yet, so core-region drift is undetectable in v0.1.0.

---

## 2026-09-08, evaluator pass 1 and fixes

**Verdict: FAIL, 17 defects.** All were found by an adversarial evaluator reading the
whole repo. None were visible to the three build workers, because each worker could only
see its own files. The defects clustered exactly where predicted, at the seams.

**The two blockers, both silent.**

- Both setup skills named `POSTHOG_PERSONAL_API_KEY`. Every other file used
  `POSTHOG_API_KEY`. The smoke test would have sent an empty bearer token, returned 401,
  and PostHog could never have left `blocked`. Nothing would have errored in a way that
  pointed at the cause.
- Both analyze skills required a field called `Absolute date range with timezone`. The
  checker, the template and the reports README all required `Time range`. Every report
  written to the skill contract would have failed its own gate.

**The most dangerous defect was not a blocker.** `entities.md` writes exclusion rules as
retention predicates, meaning the rows to keep. `analyze-backend` built an `excluded` CTE
expecting the opposite polarity. Pasting a rule from one into the other inverts the
filter, keeps exactly the rows that should have been dropped, and raises no error. The
repo's whole promise is that numbers are not silently wrong, and its two most central
files disagreed about the direction of every filter. Fixed by canonicalizing on KEEP
predicates, stating the polarity in the `entities.md` column header, and removing the CTE
in favor of rules ANDed directly into the WHERE clause with their ids cited.

**Also fixed, and worth naming because each was a claim that was not true.**

- `CLAUDE.md` said path-scoped rules in `.claude/rules/` were why files are not
  preloaded. That directory does not exist. v0.1.0 does it by convention through
  `index.md`, and now says so.
- `README.md` credited "the manifest and the hooks". There is no manifest.
- `CHARTER.md` claimed `.codex/config.toml` was part of real enforcement. Codex
  `workspace-write` bounds writes to the repo but does not protect files inside it, so
  C-12 and the knowledge-base rule are prose only under Codex. The charter now says that
  plainly rather than implying protection it does not have.
- `README.md` and this log said five skills. There are six.
- `setup.sh` promoted a row from `blocked` to `partial`, which the skill that calls it
  declares a defect, and invented a `pending smoke test` value the registry does not
  document. It no longer changes Readiness at all. Only an observed read does.
- `sources/sources.md` was writable by no rule, yet `verify-sources` exists to update it.
- `.claude/hooks/guard.sh` was a python3 script with a `.sh` extension, so `bash -n`
  failed on it and the next person to "fix" that would have broken the guard. Renamed to
  `guard.py`.

**Verified after fixes.** `bash -n` clean on all three shell scripts, `ast.parse` clean on
`guard.py`, guardrails 19/19, check-output self-test 13/13, report template passes its own
checker, `setup.sh --check` exit 0, zero em dashes repo-wide, `settings.json` parses.

## 2026-09-08, evaluator pass 2 and final fixes

**Verdict: FAIL again, 15 of 17 fixes landed, 2 incomplete, 3 more found.** The second
pass earned its cost. Both incomplete fixes were the same failure mode: a rename applied
to the definition but not to every reference.

- `analyze-backend` still told the agent to "grep the Facts section for the CTE name",
  referencing the `excluded` CTE that the polarity fix had deleted. The check was
  unrunnable, so the failure it guards against, exclusions applied to one query in a set
  and not the others, was silently unguarded. Restated as grepping for the cited rule ids.
- `guard.py` still printed "BLOCKED by .claude/hooks/guard.sh". That string is the one
  reference a user actually reads, and it pointed at a file that no longer exists.

**Three more found.**

- `sources/connectors/bigquery.md` used a bare `DATASET.__TABLES__` literal while the
  skill used the substituted version. Fix 6 had just made the connector doc the authority
  for smoke tests, which made the authority the less correct of the two.
- The Facts exemplar in `reports/_template/report.md` was wrong. Its
  `COUNT(DISTINCT a.id) ... GROUP BY a.id HAVING ...` returns 312 rows each valued 1, not
  the single `312` the sentence above it asserts. Pre-existing, and the template every
  report copies. Now wrapped in an outer `COUNT(*)`.
- `analyze-frontend` had the unconfirmed-rule treatment but not the polarity warning that
  `analyze-backend` got. Asymmetry rather than contradiction, since AGENTS.md covers it
  globally, but mirrored anyway.

**The lesson worth keeping.** Every defect in both passes was a cross-file disagreement,
and none were inside a single file. Three workers each produced internally consistent
work that did not agree at the boundaries. The evaluator pass is not a formality here,
it is the only step that can see the seams, and one pass was not enough because fixing a
seam creates new references to get wrong.

**Verified after the second round.** Guardrails 19/19, check-output self-test 13/13,
report template passes its own checker 5/0/0, `setup.sh --check` exit 0, `bash -n` clean,
`guard.py` compiles, block message names the right file, zero em dashes.

## 2026-09-09, knowledge-base readiness made visible

**Gap found by the maintainer, not by an evaluator.** `knowledge-base/README.md` defined
the `TODO` and `EXAMPLE` conventions well, including what done looks like. But the root
`README.md` never mentioned them and `setup.sh` never checked them. Someone could run
setup, be told to fill in the knowledge base, and have nothing explain the convention or
measure whether they had done it. The friction was real but invisible and unmeasured.

**Fixed.** `setup.sh --check` now has a Knowledge base section counting `TODO` and
`EXAMPLE` markers per file, and stating plainly whether analysis is blocked. It warns
rather than fails, for the same reason blocked sources warn: a fresh clone is supposed to
be unfilled, so failing there would make the exit code meaningless on day one. Root
README now explains both markers and shows the check output.

**Connector docs reframed, not cut.** The target user runs Claude Code or Codex and
already has official connectors, so installation was never the hard part. The connector
docs are now explicitly framed as covering the three things an official connector does
not give you: a read-only credential, the schema introspection query, and a bounded smoke
test. The `sources/mcp/*.example` templates stay, because a user on an open-source
harness has no official connector to lean on.

**Verified.** `bash -n` clean, guardrails 19/19, check-output 13/13, `setup.sh --check`
exit 0, zero em dashes, zero banned words outside `docs/`.

---

## 2026-09-09, portable protection, first commit, and the dry run

**Protection added.** `setup.sh --protect` / `--unprotect` chmod 24 rule files, plus a
git pre-commit hook that refuses commits touching protected paths without
`PAOS_ALLOW_PROTECTED=1`. Deliberately not a Codex-specific hook: one filesystem
mechanism every harness sees beats one guard per vendor API. Protection is a toggle,
not a setup step, because `knowledge-base/` must stay writable until the user has
filled it in. `evals/test-protection.sh` covers 24 cases including that execute bits
survive both operations. Honest limit, stated in the README: `chmod` is undone by
another `chmod`. It converts a silent successful write into a visible failed one.

**First commit.** `91b8943` on `main`, 50 files. The pre-commit hook cannot be wired
before the initial commit, because that commit necessarily touches every protected file.

**Dry run, and it is the most useful thing built so far.** Everything before it tested
structure: files exist, scripts parse, guards block. Nothing had tested whether an agent
following these skills produces a good report. A fixture world (`evals/fixtures/nimbus/`,
a filled knowledge base, two captured schemas, canned query results) plus three scenarios
run end to end.

**The three reports were good.** S-2's trap worked: signups looked doubled at 1,188 to
2,401 rows, but grew 12.1% at customer grain, with 1,102 demo accounts from a sales push
explaining the gap. S-3's C-11 refusal actually fired, and stayed useful by answering at
account grain on a confirmed key. C-07 held: an instruction-shaped account name in the
fixture data was quoted and ignored rather than obeyed.

**The process was not good, and that is the finding.** Two verified directly:

- `evals/check-output.sh` passes a report with a **fabricated number and no query at
  all**, exit 0, one warning. C-05 is the repo's central promise and its gate only warns.
  A probe naming five exclusion rule ids without applying any of them also passes clean,
  because the check tests for prose about exclusions rather than their application.
  `analyze-backend` specifies the grep that would catch this; the script never
  implemented it.
- `knowledge-base/entities.md:144` E-8 reads `churned_at > <window_end>` beneath a note
  saying "do not drop churned accounts from historical windows". It drops exactly those.
  `window_start` is correct. A real logic bug in the example every user will copy.

**Structural problems found.**

- Hook enforcement is conditional on `$CLAUDE_PROJECT_DIR` resolving to this repo. When a
  session root is the parent directory, no settings load and no hook runs. Observed twice,
  once by the dry-run agent writing seven files into a protected path with no prompt, and
  once during the original build. The only real enforcement depends on a fact the repo
  cannot observe.
- CHARTER C-12 forbids the agent writing under `evals/`, but building and running evals
  requires exactly that. A compliant agent refuses to test its own repo.
- Every source ships `blocked` and both analyze skills refuse non-`ready` sources, so as
  shipped zero analyses can run and there is no fixture mode. Every scenario needed a
  registry override.

**The verdict worth keeping.** A PM would trust those three reports. They would not trust
the process, because the gate cannot separate a good report from a confidently wrong one.
And an agent will follow this contract for about three questions: eight files read before
the first number, roughly 60% of each 180-line report mandated repetition, the same
disclosure in all three reports changing nothing in any. The contract is not too strict,
it is too uniformly strict. The same cost applies to "how many accounts signed up" as to a
cross-source cohort analysis. The first thing an agent drops under that load is re-reading
`entities.md`, which is the one omission that silently corrupts every number.
