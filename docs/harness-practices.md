# Harness practices

Research from September 2026 on building a model-agnostic agent harness, and what
this repo does about each finding. Sources are named inline.

## AGENTS.md as the portable instruction file

AGENTS.md is plain Markdown with no required schema. It is stewarded by the Agentic AI
Foundation under the Linux Foundation, with 20+ supporting tools including Codex,
Copilot coding agent, Jules, Gemini CLI, Cursor, Zed, Amp, Warp, Aider and Windsurf
([agents.md](https://agents.md/)). In monorepos, the closest AGENTS.md to the edited
file wins, and an explicit user prompt overrides everything.

**Claude Code does not read AGENTS.md.** Anthropic's memory docs say so plainly, and
this is the most consistently misreported fact in this space. Several popular blog
posts claim a fallback exists. It does not. The two sanctioned single-source patterns
are `@AGENTS.md` as the first line of `CLAUDE.md`, or a symlink. Imports resolve
relative to the importing file, recurse to 4 hops, and skip paths inside backticks.
Windows symlinks need Administrator or Developer Mode, so the import is the portable
choice.

**What this repo does:** `AGENTS.md` holds every rule. `CLAUDE.md` is `@AGENTS.md` plus
Claude-only mechanics. `.codex/config.toml` sets Codex's sandbox, and Codex reads
`AGENTS.md` directly. One copy of the rules, three harnesses.

Other findings worth keeping: target under 200 lines, since adherence drops with length
even though files load fully to 4 MiB. Do not document what an agent can read from the
code itself. Anthropic's own trim check strips directory layouts and dependency lists
and keeps pitfalls, rationale, and conventions that differ from tool defaults. HTML
comments are stripped before injection, so maintainer notes cost zero tokens.

## Context engineering

The goal, in Anthropic's framing, is the smallest set of high-signal tokens that gets
the outcome. Recall degrades as context grows, which is why monolithic instruction files
underperform ([effective context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)).

The four failure modes the field has settled on
([Breunig](https://www.dbreunig.com/2025/06/22/how-contexts-fail-and-how-to-fix-them.html)):
**poisoning**, a hallucination enters context and gets referenced repeatedly;
**distraction**, history outweighs training; **confusion**, irrelevant content the model
feels obliged to use; **clash**, contradictory instructions accumulate. Anthropic's docs
add that contradictory rules mean the model picks one arbitrarily, which is why
resolving conflicts on sight is a rule in `AGENTS.md` rather than an aspiration.

Prefer just-in-time retrieval: hold identifiers, paths, table names and query stubs, and
fetch content when needed. `.claude/rules/*.md` with `paths:` frontmatter is the real
mechanism, loading instructions only when a matching file is read. Imports do not save
context. Rules do.

For cold resume, the pattern that works is a short always-loaded index plus detail files
loaded on demand, with a hard cap on the index. Anthropic enforces this mechanically in
its own auto-memory, erroring when the index exceeds its read limit, because content
past the cap is silently dropped.

**What this repo does:** `index.md` is the map and stays short. Connector docs, schema
files and knowledge-base files load on demand. `task.md` carries current state and
`log.md` carries assumptions and what is unverified, so a fresh session can resume
without the transcript. Since v0.2.2, four path-scoped rules in `.claude/rules/` load
the pitfalls for schema, connectors, reports and the knowledge base when a matching file
is read. They restate `AGENTS.md` and never originate a rule, so a harness that ignores
them loses a reminder, never a rule.

The 200-line target is Anthropic's, for Claude Code. No source gives a defensible
universal token budget, so treat it as directional.

## Orchestrator and subagents

Anthropic's multi-agent research system used roughly 15x the tokens of chat, against
about 4x for single-agent, and token usage alone explained 80% of performance variance
([multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)).
The same post is explicit that multi-agent underperforms when agents need shared context
or subtasks are interdependent, and that most coding tasks lack enough parallelizable
work. Delegation is neither free nor a default.

Task specs must be precise: without detailed descriptions, agents duplicate work, leave
gaps, or fail to find what they need. The consensus write rule is that no two agents
write the same file; genuine parallel mutation gets separate git worktrees and one merge.

On portability: Codex has since shipped native parallel agents and worktree isolation.
This space moves fast enough that betting the repo on any one harness's primitive is a
mistake. The portable expression is a written role contract naming inputs, allowed
writes, output format and stop condition. A harness with subagents maps it to one; a
harness without runs it inline as a phase.

Failure modes to name rather than hope about: context poisoning propagating from a bad
worker summary the orchestrator cannot audit, cascading errors from a vague brief, and
workers that cannot see each other's state, which is structural rather than a bug. The
orchestrator-to-worker interface is natural language, so correctness rests on phrasing,
not on a typed contract.

**What this repo does:** `agents/roles.md` defines orchestrator, worker and evaluator as
contracts with a seven-field brief. `AGENTS.md` requires all four delegation conditions
to hold, requires single write ownership, and requires spot-checking one worker claim.

## Guardrails

The load-bearing sentence from Anthropic's permissions docs: permission rules are
enforced by Claude Code, not by the model, and instructions in a prompt or CLAUDE.md
shape what Claude tries to do but do not change what Claude Code allows. **Anything that
must not happen belongs in `permissions.deny` or a `PreToolUse` hook, never in prose.**

Mechanics worth knowing, all from
[the permissions docs](https://code.claude.com/docs/en/permissions):

- Rules evaluate deny, then ask, then allow. First match wins. Specificity does not
  change ordering, so a broad deny cannot carry allowlist exceptions.
- A bare tool name in `deny` removes the tool from context entirely. A scoped rule like
  `Bash(rm *)` leaves the tool visible and blocks matching calls.
- A `Read` deny rule also blocks Edit and Write on that path, but not NotebookEdit.
- **Path rules only work on `Read` and `Edit`. A `Write(...)` path rule is accepted and
  never consulted.** This is the trap: it looks like protection and is not.
- A `PreToolUse` hook exiting 2 blocks before permission rules evaluate and overrides
  allow rules. It cannot override deny.

`PostToolUse` runs after a tool call succeeds and cannot block it, so it is for feedback
rather than enforcement. A hook returns text to the model by printing
`hookSpecificOutput.additionalContext` and exiting 0. This repo uses it to run the report
lint automatically, keeping success silent and failures verbose. See
[the hooks docs](https://code.claude.com/docs/en/hooks).

Codex uses two orthogonal dials: `sandbox_mode` (`read-only`, `workspace-write`,
`danger-full-access`), an OS-enforced boundary with network off by default in
workspace-write, and `approval_policy` (`untrusted`, `on-request`, `never`). Configure
both. A tight sandbox with rare approvals beats frequent prompts in an unbounded
environment.

MCP's `readOnlyHint` and `destructiveHint` are hints. The spec states clients must
consider annotations untrusted unless they come from trusted servers
([MCP tools spec](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)).
Never build a permission model on them.

OWASP's LLM Top 10 2026, published 2026-08-04, keeps Prompt Injection at #1 and promotes
Excessive Agency from #6 to #3. The useful framing: injection is architectural, because
instructions and data share one channel and there is no parameterized-query equivalent.
Every mitigation lowers probability without reaching zero. Damage is mediated by the
permissions the agent holds, so least privilege is the actual control.

**What this repo does:** `.claude/settings.json` carries deny rules using `Edit(...)`
rather than the ignored `Write(...)`, `.claude/hooks/guard.py` covers the Write gap plus
shell paths around the deny rules plus destructive SQL aimed at a data client, and
`.codex/config.toml` sets both Codex dials. `evals/test-guardrails.sh` proves the guard
fails when it should, in 67 cases. `CHARTER.md` states plainly that it is a
specification rather than a control.

## Repos worth reading

| Repo | Steal | Avoid |
|---|---|---|
| [agentsmd/agents.md](https://github.com/agentsmd/agents.md) | Canonical minimal spec, nesting and precedence | No opinion on content quality |
| [anthropics/skills](https://github.com/anthropics/skills) | SKILL.md frontmatter, progressive disclosure via bundled reference files | Star count is hype-inflated |
| [openai/codex](https://github.com/openai/codex) | Sandbox and approval as two separate dials | Fast-moving primitives, do not hard-couple |
| [retentioneering/retentioneering-tools](https://github.com/retentioneering/retentioneering-tools) | Closest analyst-agent exemplar found: MCP server plus skills for auditable, reproducible event-log analytics | Specific to clickstream |
| [humanlayer/humanlayer](https://github.com/humanlayer/humanlayer) | Human-in-the-loop approval as a first-class primitive | Last push 2026-06, staleness risk |
| [Kiln-AI/Kiln](https://github.com/Kiln-AI/Kiln) | Eval definitions as versioned artifacts beside the agent | GUI-centric, not harness-shaped |
| [langchain-ai/how_to_fix_your_context](https://github.com/langchain-ai/how_to_fix_your_context) | Runnable demos of write, select, compress, isolate | Unmaintained since 2025-07 |
| [ai-boost/awesome-harness-engineering](https://github.com/ai-boost/awesome-harness-engineering) | Live index of harness patterns, evals, permissions, observability | A curation list, not a design |

Skeptical note from the research: several very-high-star "skills pack" repos surfaced in
search are marketing artifacts whose star counts do not track engineering quality.
