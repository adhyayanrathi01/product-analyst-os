# Current task

Read this first if you are picking the project up cold. `log.md` has the full
chronological record and the reasoning behind every decision. This file is the state and
the open list.

**Repo:** https://github.com/adhyayanrathi01/product-analyst-os, public, MIT.
**Local:** `~/Desktop/pm-portfolio/pm interview prep/product-analyst-os`
**Version:** 0.2.0. **Branch:** `main`.

---

## What this is

A workspace that lets an AI agent answer product usage questions without inventing
numbers. Read-only sources, captured schema, definitions in one file, and every number
carries the query that produced it. Model-agnostic: one rule file, read by Claude Code,
Codex, or anything that reads `AGENTS.md`.

Built as a focused sibling of `product-manager-os`, reusing its conventions but scoped
only to analytics.

## Status

Shippable. Nothing is connected, which is the expected state for a fresh clone.

All 7 sources in `sources/sources.md` are `blocked`. `blocked` means nobody has proved
the source reads. It does not mean you cannot query it. A source becomes `ready` after
`verify-sources` observes one bounded read, per CHARTER C-08, and until then an answer
drawn from it says in one line that the source is unverified.

`knowledge-base/` is unfilled. The agent will still answer, and will name what it assumed.
That answer is worse than the one you get after filling in `entities.md`, and it says so.

## Verify it still works

```bash
./setup.sh --check                     # exit 0
./evals/test-guardrails.sh             # 19/19
./evals/test-protection.sh             # 24/24
./evals/check-output.sh --self-test    # 30/30
```

CI runs all four plus a style check on every push. Badge is in the README.

---

## Done

**v0.1.0.** Repo skeleton, `CHARTER.md` with 12 clauses, `AGENTS.md` as the single rule
source with `CLAUDE.md` importing it, `agents/roles.md` defining orchestrator, worker and
evaluator as portable contracts, six skills, seven connector docs, knowledge-base
templates, report and schema contracts, and two research docs with citations in `docs/`.

**Guardrails, real ones.** `.claude/settings.json` plus `.claude/hooks/guard.py`, because
permission rules are enforced by the harness and not by the model. Claude Code's path
rules do not apply to `Write` at all, so a `Write(path)` deny rule is silently ignored.
That specific gap is why `guard.py` exists.

**Portable protection.** `setup.sh --protect` and `--unprotect` chmod 24 rule files, plus
a git pre-commit hook. One filesystem mechanism every harness sees, rather than one guard
per vendor API. Protection is a toggle, not a setup step, because `knowledge-base/` has to
stay writable until the user fills it in.

**Two evaluator passes.** 22 defects, every one a cross-file disagreement invisible to any
single author. Both recorded in `log.md`.

**A dry run against a fixture world.** `evals/fixtures/nimbus/` plus three scenarios. This
is the step that found the repo could not run at all as shipped, and that the output gate
could not tell a good report from a confidently wrong one.

**v0.2.0.** Usage gates removed. Readiness no longer blocks a query. The nine-field
contract became two shapes with short form as the default. `check-output.sh` became a lint
rather than a gate. The whole safety layer stayed: read-only, secrets, injection handling,
knowledge-base protection.

**Five exclusion rule bugs fixed**, in two classes that both lose rows silently. Missing
column reference in E-1 and E-7, so pasting them verbatim produced invalid SQL. Empty
values silently dropped in E-4, E-6 and E-7. E-9 decided as point-in-time: a number that
went out in a report stands, and a later change is shown as a restatement.

**Published.** MIT license, GitHub Actions running every suite, README badges pointing at
real CI rather than decorative ones.

---

## Open, and what each needs

### Blocking

Nothing. The repo is shippable as it stands.

### Deliberately skipped, add when there is a reason

**1. `core.sha256` integrity manifest.** Hashes each skill's `CORE:BEGIN/END` region so a
quiet self-edit shows up in `setup.sh --check`. It guards against an agent weakening its
own rules, and there is no self-improvement loop here for it to guard. **Add it the day
you add one, not before.**

**2. `.claude/rules/` with `paths:` frontmatter.** Would load connector and schema docs
only when a matching file is read, instead of by convention through `index.md`. Real
benefit, no urgency. `docs/harness-practices.md` explains the mechanism.

**3. Three `UNVERIFIED` connector facts.** Flagged in place rather than presented as
confirmed. Confirm against real instances if you use these: Mixpanel Lexicon sub-paths,
Metabase MCP minimum version and whether an API-key path exists, and whether Codex expands
`${VAR}` inside `config.toml`.

### Holes in the checker, all advisory since v0.2.0

**4. The exclusions check tests for prose, not application.** A report naming five rule
ids without applying any of them passes clean. `analyze-backend` already specifies the
grep that would catch it. Roughly ten lines. **Largest remaining hole.**

**5. The query check is file-wide and only warns.** A report with a fabricated number and
no query anywhere passes with exit 0. Verified directly. C-05 is this repo's central
promise and the check enforcing it does not fail.

**6. Minor.** "the last day of August 2026" is flagged as a relative date, a false
positive. The secret scan misses raw email addresses.

### Structural, needs thought rather than typing

**7. Hook enforcement depends on `$CLAUDE_PROJECT_DIR` resolving to this repo.** When a
session's root is the parent directory, no settings load and no hook runs. Observed twice
during the build. `setup.sh --protect` is the mitigation, which is why it exists.

**8. `guard.py` and `.githooks/pre-commit` disagree about `evals/`.** C-12 now permits
writing there, `guard.py` still blocks it. Pick one.

**9. `sources/sources.md` last-verified column can drift** from what `verify-sources`
actually recorded. Cosmetic today, misleading later.

### The one that matters most

**10. Nobody has run this against a real database.** Every check so far is structural or
against fixtures. The fixture dry run was genuinely useful and it is not the same thing.
**The first real run will find things none of this caught.** Do it on one source with a
read-only credential before recommending this to anyone.

---

## Things that would be easy to get wrong later

- **`knowledge-base/` belongs to the user.** The agent proposes a diff and waits. During
  the build an agent edited it without being asked. If that happens again it is a defect.
- **Rules in `entities.md` KEEP wanted rows.** They `AND` into a `WHERE` clause. Inverting
  the polarity keeps exactly the rows you meant to drop and raises no error.
- **Write predicates so an empty value is kept.** `type <> 'demo'` silently drops rows
  where `type` is blank. Use `IS DISTINCT FROM`, or add the `IS NULL` half.
- **Never template `@modelcontextprotocol/server-postgres`.** Archived, unpatched SQL
  injection, still the top search result. Use `postgres-mcp --access-mode=restricted`.
- **`CHARTER.md` is a specification, not a control.** It says so itself. Real enforcement
  is the hook, the chmod and the pre-commit hook, and each has stated limits.
- **No em dashes.** House style, and CI fails on one.
- **CleverTap was cut on purpose.** No API lists its event names, so schema capture is
  impossible, and its passcode auth has no read-only scope. Reasoning is preserved in
  `docs/connectors-research.md`.

## Next action

Pick one real source, give it a read-only credential, fill in section 3 of
`knowledge-base/entities.md`, and ask one question you already know the answer to.

That single run will tell you more than the next ten items on this list.
