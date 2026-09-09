@AGENTS.md

## Claude-specific notes

Everything above applies. These are the Claude Code mechanics on top of it.

- Real enforcement lives in `.claude/settings.json` and `.claude/hooks/guard.py`, not in prose. Rules in this file shape what you try to do. They do not change what the harness allows.
- Connector docs, schema files and knowledge-base files are not preloaded. Find them through `index.md` and read the one you need. v0.1.0 does this by convention, not by mechanism: there is no `.claude/rules/` directory yet. Path-scoped rules with `paths:` frontmatter would enforce it, and `docs/harness-practices.md` explains why that is the better pattern.
- A built-in subagent does not inherit this instruction hierarchy or the auto memory. When you delegate, paste the indispensable rules into the task prompt: read-only, exclusions from `entities.md`, the output contract, and the allowed write paths.
- Roles for delegation are in `agents/roles.md`. Use the fewest workers that answer the question.
- Before calling any analysis complete, run `./setup.sh --check`.
