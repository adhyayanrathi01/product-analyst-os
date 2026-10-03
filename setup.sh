#!/usr/bin/env bash
# setup.sh for product-analyst-os.
#
# This script is network-free and install-free. It never runs npm, pip, uvx,
# gcloud, psql or mongosh. It never touches a credential value. It writes config
# and prints instructions, and you run the install and credential steps yourself.
#
# Modes:
#   ./setup.sh          interactive first-run setup
#   ./setup.sh --check   non-interactive health check, exits non-zero on failure.
#                        Also creates any missing workspace file from its template.
#   ./setup.sh --help    this text
#
# Written to run on bash 3.2 as shipped with macOS, so no associative arrays and
# no mapfile.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO"

SOURCES_MD="sources/sources.md"
GUARD=".claude/hooks/guard.py"
SOURCE_KEYS="posthog mixpanel amplitude bigquery metabase mongodb postgres-supabase"

# Workspace files. Each is gitignored, because it holds the user's company data,
# and each has a tracked blank at <dir>/_template/<name>.
WORKSPACE_FILES="knowledge-base/entities.md knowledge-base/company.md
knowledge-base/personas.md knowledge-base/metrics.md knowledge-base/glossary.md
sources/sources.md task.md log.md"

ok()   { printf '  ok       %s\n' "$*"; }
warn() { printf '  warn     %s\n' "$*"; }
bad()  { printf '  MISSING  %s\n' "$*"; }
sec()  { printf '\n== %s ==\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

label_for() {
  case "$1" in
    posthog) echo "PostHog" ;;
    mixpanel) echo "Mixpanel" ;;
    amplitude) echo "Amplitude" ;;
    bigquery) echo "BigQuery" ;;
    metabase) echo "Metabase" ;;
    mongodb) echo "MongoDB" ;;
    postgres-supabase) echo "Postgres/Supabase" ;;
  esac
}

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
check_prereqs() {
  local missing=0 major
  sec "Prerequisites"

  if [ -n "${BASH_VERSION:-}" ]; then
    major="${BASH_VERSION%%.*}"
    if [ "$major" -ge 4 ] 2>/dev/null; then
      ok "bash $BASH_VERSION"
    else
      warn "bash $BASH_VERSION is older than 4. This script avoids bash 4 features, so it still runs."
    fi
  else
    warn "not running under bash. The POSIX fallback path is in use."
  fi

  if have python3; then
    ok "python3, $(python3 --version 2>&1)"
  else
    bad "python3. Required. .claude/hooks/guard.py is a python3 script, and without python3 the PreToolUse guard cannot run."
    missing=1
  fi

  if have git; then ok "git"; else warn "git not found. Optional, but nothing is version controlled without it."; fi

  if have sha256sum; then
    ok "sha256sum"
  elif have shasum; then
    ok "shasum found, sha256sum is not. Use: shasum -a 256"
  else
    warn "neither sha256sum nor shasum. Schema drift hashing needs one of them."
  fi

  return "$missing"
}

# ---------------------------------------------------------------------------
# Registry parsing. Column 3 of each row holds the env var names.
# ---------------------------------------------------------------------------
registry_rows() {
  awk -F'|' '
    NF >= 9 && $2 !~ /^ *Source *$/ && $2 !~ /^ *-+ *$/ { print }
  ' "$SOURCES_MD"
}

trim() { printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

# Never prints a value. Checks the process env first, then whether .env defines
# the name with something non-empty after the equals sign.
env_is_set() {
  local n="$1" v=""
  eval "v=\${$n:-}"
  [ -n "$v" ] && return 0
  [ -f .env ] || return 1
  grep -Eq "^[[:space:]]*(export[[:space:]]+)?${n}=[^[:space:]]" .env
}

row_exists() {
  grep -q "^| $1 |" "$SOURCES_MD"
}

# Records that a source was selected. It does NOT change Readiness.
#
# Configuring a credential is not readiness, and this script cannot observe a
# read, so it has no basis for promoting anything. Readiness is owned entirely
# by verify-sources, which performs one bounded read (CHARTER C-08).
#
# An earlier version promoted blocked to partial here. That contradicted
# skills/setup/connect-sources, which declares any non-blocked value written by
# this path a defect, and it invented a `pending smoke test` value that
# sources/sources.md does not document.
mark_selected() {
  local label="$1" envs="$2"
  if ! row_exists "$label"; then
    printf '| %s | unknown | %s | see sources/connectors/ | blocked | never | added by setup.sh |\n' \
      "$label" "$envs" >> "$SOURCES_MD"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Per-source instructions
# ---------------------------------------------------------------------------
mcp_block() {
  case "$1" in
    posthog) cat <<'EOF'
"posthog": {
  "type": "http",
  "url": "${POSTHOG_MCP_URL}",
  "headers": {
    "Authorization": "Bearer ${POSTHOG_API_KEY}",
    "x-posthog-read-only": "true",
    "x-posthog-project-id": "${POSTHOG_PROJECT_ID}"
  }
}
EOF
;;
    mixpanel) cat <<'EOF'
"mixpanel": { "type": "http", "url": "${MIXPANEL_MCP_URL}" }
OAuth 2.1 PKCE S256 is run by the client, so no token is stored here.
EOF
;;
    amplitude) cat <<'EOF'
"amplitude": { "type": "http", "url": "${AMPLITUDE_MCP_URL}" }
OAuth 2.0. There is no read-only flag. The role is the control.
EOF
;;
    bigquery) cat <<'EOF'
"bigquery": {
  "command": "${TOOLBOX_BIN}",
  "args": ["--prebuilt", "bigquery", "--stdio"],
  "env": {
    "BIGQUERY_PROJECT": "${BIGQUERY_PROJECT}",
    "BIGQUERY_MAXIMUM_BYTES_BILLED": "${BIGQUERY_MAXIMUM_BYTES_BILLED}"
  }
}
EOF
;;
    metabase) cat <<'EOF'
"metabase": { "type": "http", "url": "${METABASE_MCP_URL}" }
UNVERIFIED against any instance version. Use the REST API with the
x-api-key header until you have confirmed MCP works on your instance.
EOF
;;
    mongodb) cat <<'EOF'
"mongodb": {
  "command": "npx",
  "args": ["-y", "mongodb-mcp-server@latest", "--readOnly"],
  "env": {
    "MDB_MCP_CONNECTION_STRING": "${MDB_MCP_CONNECTION_STRING}",
    "MDB_MCP_READ_ONLY": "true"
  }
}
EOF
;;
    postgres-supabase) cat <<'EOF'
"postgres": {
  "command": "uvx",
  "args": ["postgres-mcp", "--access-mode=restricted"],
  "env": { "DATABASE_URI": "${DATABASE_URI}" }
}
"supabase": {
  "type": "http",
  "url": "https://mcp.supabase.com/mcp?project_ref=${SUPABASE_PROJECT_REF}&read_only=true"
}
Never use @modelcontextprotocol/server-postgres. It is archived and carries
an unpatched SQL injection.
EOF
;;
  esac
}

credential_steps() {
  case "$1" in
    posthog) cat <<'EOF'
1. PostHog, /settings/user-api-keys, create a personal API key with the
   "MCP Server" preset.
2. Limit scopes to Query Read, event_definition:read, property_definition:read.
3. Scope the key to one project, and send x-posthog-read-only: true as well.
EOF
;;
    mixpanel) cat <<'EOF'
1. Prefer OAuth. The client runs the flow and no secret lands in .env.
2. If you use a service account, in beta, grant only these scopes:
   projects analysis events insights segmentation retention data:read
   funnels flows data_definitions
3. Budget your calls. 600 MCP requests per hour per user.
EOF
;;
    amplitude) cat <<'EOF'
1. Every Amplitude role grants USE_MCP_READ. Member, Manager and Admin also
   grant USE_MCP_WRITE, so read-only requires a Viewer-tier role.
2. Put the agent account in a Viewer-tier role and confirm USE_MCP_WRITE is
   absent from that role's permission list.
3. The API key and secret key pair is for the Taxonomy API, not for MCP auth.
EOF
;;
    bigquery) cat <<'EOF'
1. Grant roles/bigquery.dataViewer and roles/bigquery.jobUser to the agent
   service account. Never roles/bigquery.dataEditor.
2. The bigquery prebuilt toolset has no read-only flag, so IAM is the only
   enforcement.
3. Set BIGQUERY_MAXIMUM_BYTES_BILLED and a project-level custom quota. An
   unbounded scan is a spend.
EOF
;;
    metabase) cat <<'EOF'
1. Create a group, for example agent-readonly, with view-only data access and
   no native query rights.
2. Create the API key inside that group. Key permissions come from the group
   it is created in, not from the superuser who created it.
3. API keys need Metabase v0.47 or later.
EOF
;;
    mongodb) cat <<'EOF'
1. Create a DB user with the built-in read role on the target database only:
   db.getSiblingDB("admin").createUser({ user: "agent_ro",
     pwd: passwordPrompt(), roles: [ { role: "read", db: "app" } ] })
2. Not readAnyDatabase. That hands over every database on the cluster.
3. Run the server with --readOnly and set MDB_MCP_READ_ONLY=true as well.
EOF
;;
    postgres-supabase) cat <<'EOF'
1. Create a dedicated role. The GRANTs are the real boundary:
   CREATE ROLE agent_ro LOGIN PASSWORD '...';
   REVOKE ALL ON DATABASE app FROM PUBLIC;
   GRANT CONNECT ON DATABASE app TO agent_ro;
   GRANT USAGE ON SCHEMA public TO agent_ro;
   GRANT SELECT ON ALL TABLES IN SCHEMA public TO agent_ro;
   ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO agent_ro;
2. Session settings, which catch accidents but do not enforce anything:
   ALTER ROLE agent_ro SET default_transaction_read_only = on;
   ALTER ROLE agent_ro SET statement_timeout = '15s';
   ALTER ROLE agent_ro SET idle_in_transaction_session_timeout = '30s';
   default_transaction_read_only is a client default and a session can SET it
   back off, so it is not a security control.
3. On Supabase, keep read_only=true in the MCP URL.
EOF
;;
  esac
}

# ---------------------------------------------------------------------------
# Interactive setup
# ---------------------------------------------------------------------------
interactive() {
  local client key label envs answer

  sec "Interactive setup"
  if [ ! -t 0 ]; then
    echo "  stdin is not a terminal. Run ./setup.sh --check instead, or run this"
    echo "  script from a terminal."
    return 1
  fi

  check_prereqs || echo "  Fix the MISSING items above before you rely on the guard."
  ensure_workspace_files || echo "  A template is missing. Restore it from git before you continue."

  if [ ! -f .env ]; then
    cp .env.example .env
    ok "created .env from .env.example. It is gitignored. Fill it in yourself."
  else
    ok ".env already exists, left untouched."
  fi

  echo ""
  echo "Which MCP client are you configuring?"
  echo "  1) Claude Code    template: sources/mcp/claude-code.json.example"
  echo "  2) Codex          template: sources/mcp/codex.toml.example"
  echo "  3) other          template: sources/mcp/generic-mcp.json.example"
  printf 'Choice [1]: '
  read -r answer || answer=1
  case "${answer:-1}" in
    2) client="Codex, ~/.codex/config.toml, template sources/mcp/codex.toml.example" ;;
    3) client="your MCP client's config, template sources/mcp/generic-mcp.json.example" ;;
    *) client="Claude Code, .mcp.json at the repo root, template sources/mcp/claude-code.json.example" ;;
  esac

  echo ""
  echo "Now pick the sources to connect. Nothing here asks for a secret value."
  echo "You are only ever asked yes or no."

  for key in $SOURCE_KEYS; do
    label="$(label_for "$key")"
    printf '\nConnect %s? [y/N]: ' "$label"
    read -r answer || answer=n
    case "${answer:-n}" in
      y|Y|yes|YES) ;;
      *) continue ;;
    esac

    envs="$(env_names_for_label "$label")"
    mark_selected "$label" "$envs"

    sec "$label"
    echo "Env vars to fill in .env, names only:"
    echo "  $envs"
    echo ""
    echo "MCP config, paste into $client :"
    mcp_block "$key" | sed 's/^/  /'
    echo ""
    echo "Read-only credential setup:"
    credential_steps "$key" | sed 's/^/  /'
    echo ""
    echo "Full detail, including the smoke test: sources/connectors/$key.md"
  done

  next_steps
}

env_names_for_label() {
  registry_rows | awk -F'|' -v L="$1" '
    { name = $2; gsub(/^[ \t]+|[ \t]+$/, "", name) }
    name == L { e = $4; gsub(/^[ \t]+|[ \t]+$/, "", e); print e; exit }
  '
}

# ---------------------------------------------------------------------------
# Workspace files
# ---------------------------------------------------------------------------
# This repo is a public template and also the folder you analyze in. Your
# definitions, schema, reports, task.md and log.md are gitignored so a push never
# publishes them, which means a fresh clone has none. Each is copied from its
# blank template the first time. An existing file is never overwritten, so this
# is safe to run every time, and --check runs it.
ensure_workspace_files() {
  local f t fail=0
  sec "Workspace files"
  for f in $WORKSPACE_FILES; do
    t="$(dirname "$f")/_template/$(basename "$f")"
    t="${t#./}"
    if [ -f "$f" ]; then
      ok "$f"
    elif [ -f "$t" ]; then
      cp "$t" "$f"
      ok "$f created from $t"
    else
      bad "$f, and its template $t"
      fail=1
    fi
  done
  return "$fail"
}

# .gitignore does not untrack a file git already tracks. A clone made before
# workspace files were ignored, or a git add -f, leaves one tracked, and the next
# push publishes it. This is the one way the gitignore can be silently bypassed.
check_workspace_untracked() {
  local tracked
  sec "Workspace privacy"
  if ! have git || ! git rev-parse --git-dir >/dev/null 2>&1; then
    ok "not a git repository, nothing can be pushed."
    return 0
  fi
  tracked="$(git ls-files -ci --exclude-standard)"
  if [ -z "$tracked" ]; then
    ok "no gitignored file is tracked. A push carries none of your workspace."
    return 0
  fi
  bad "git still tracks these gitignored files. A push would publish them:"
  printf '%s\n' "$tracked" | sed 's/^/    /'
  echo "  Stop tracking them. Your copies stay on disk:"
  echo "    git ls-files -ci --exclude-standard -z | xargs -0 git rm --cached --"
  echo "  Then commit. If you meant to track them, use a private repo and delete"
  echo "  their lines from .gitignore."
  return 1
}

# ---------------------------------------------------------------------------
# --check
# ---------------------------------------------------------------------------
check_structure() {
  local fail=0 p key
  sec "Repo structure"
  for p in AGENTS.md CHARTER.md sources/_template/sources.md .env.example .gitignore sources/connectors sources/mcp; do
    if [ -e "$p" ]; then ok "$p"; else bad "$p"; fail=1; fi
  done
  for key in $SOURCE_KEYS; do
    if [ -f "sources/connectors/$key.md" ]; then
      ok "sources/connectors/$key.md"
    else
      bad "sources/connectors/$key.md"
      fail=1
    fi
  done
  if [ -f .env ]; then ok ".env present"; else warn ".env not found. Copy .env.example to .env."; fi
  return "$fail"
}

check_sources() {
  local rows fail=0 name envs readiness verified var missing status
  rows="$(mktemp)"
  registry_rows > "$rows"

  sec "Source readiness"
  while IFS='|' read -r _lead name _type envs _mech readiness verified _notes _rest; do
    name="$(trim "$name")"
    readiness="$(trim "$readiness")"
    verified="$(trim "$verified")"
    [ -n "$name" ] || continue

    missing=""
    for var in $(printf '%s' "$envs" | tr -d '`' | tr ',' ' '); do
      if ! env_is_set "$var"; then
        missing="$missing $var"
      fi
    done

    if [ -z "$missing" ]; then
      status="env set"
    else
      status="env missing:$missing"
    fi

    printf '  %-18s %-8s last verified: %-20s %s\n' "$name" "$readiness" "$verified" "$status"

    # A blocked source is one nobody connected yet, so unset vars are expected
    # and do not fail the check. A source claiming partial or ready must have
    # every var it named.
    if [ -n "$missing" ] && [ "$readiness" != "blocked" ]; then
      bad "$name is marked $readiness but is missing the env vars above."
      fail=1
    fi
  done < "$rows"
  rm -f "$rows"

  echo ""
  echo "  Readiness is not proven by an env var. CHARTER C-08: a source is ready"
  echo "  only after one bounded read was actually observed. Run the smoke test in"
  echo "  sources/connectors/<name>.md, then update $SOURCES_MD by hand."
  return "$fail"
}

# A smoke test, not the suite. It proves the guard is alive: it compiles, it blocks
# one forbidden write, and it allows one normal one. A guard with a syntax error lets
# every call through, which is the failure worth catching on a user's machine.
#
# The full suite, evals/test-guardrails.sh, proves every case. Users never change the
# guard, so they never need to re-prove it. CI runs the suite on every push, and a
# maintainer runs it after touching the hook.
check_guardrails() {
  local deny allow
  sec "Guardrails"
  if [ ! -f "$GUARD" ]; then
    bad "$GUARD not found. Without it, nothing stops a write to a protected file."
    return 1
  fi
  if ! python3 -m py_compile "$GUARD" 2>/dev/null; then
    bad "$GUARD does not compile. A broken guard blocks nothing."
    return 1
  fi
  deny=0; allow=0
  printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"CHARTER.md"}}' \
    | python3 "$GUARD" >/dev/null 2>&1 || deny=$?
  printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"reports/x.md"}}' \
    | python3 "$GUARD" >/dev/null 2>&1 || allow=$?
  if [ "$deny" -eq 2 ] && [ "$allow" -eq 0 ]; then
    ok "guard compiles, blocks a protected write, allows a report"
    return 0
  fi
  bad "guard smoke test failed: protected write exit $deny (want 2), report write exit $allow (want 0)"
  return 1
}

# Reports how much of the knowledge base is still unfilled.
#
# This warns, it does not fail. A fresh clone is supposed to be unfilled, so
# failing here would make the exit code meaningless on day one, the same reason
# blocked sources do not fail. The point is to make the gap visible and countable
# rather than to block the script.
#
# `TODO` marks a field you must fill. `EXAMPLE` marks a Nimbus Freight sample that
# must be deleted, and a leftover example is worse than a TODO because the agent
# reads it as a fact.
check_knowledge_base() {
  local f base todos examples entities_todo=0
  sec "Knowledge base"

  if [ ! -d knowledge-base ]; then
    bad "knowledge-base/ not found."
    return 1
  fi

  for f in knowledge-base/entities.md knowledge-base/company.md \
           knowledge-base/personas.md knowledge-base/metrics.md \
           knowledge-base/glossary.md; do
    [ -f "$f" ] || { bad "$f not found."; continue; }
    base="$(basename "$f")"
    todos="$(grep -c 'TODO' "$f" 2>/dev/null || echo 0)"
    examples="$(grep -c 'EXAMPLE' "$f" 2>/dev/null || echo 0)"
    [ "$base" = "entities.md" ] && entities_todo="$todos"
    if [ "$todos" -eq 0 ] && [ "$examples" -eq 0 ]; then
      ok "$(printf '%-14s filled' "$base")"
    else
      warn "$(printf '%-14s %s TODO, %s EXAMPLE block(s) to delete' "$base" "$todos" "$examples")"
    fi
  done

  echo ""
  if [ "$entities_todo" -gt 0 ]; then
    echo "  Analysis will RUN ON ASSUMPTIONS. entities.md still has $entities_todo TODO markers."
    echo "  Without the grain, the active definition and the exclusion rules, every"
    echo "  number is unfiltered and counted at an unknown unit. Reports will say so"
    echo "  in every answer, which is the best they can do. Filling this in is what"
    echo "  turns those assumptions into facts."
    echo "  Section 5, lifecycle edge cases, may stay TODO. Fill a row when the case"
    echo "  first happens. See knowledge-base/README.md."
  else
    echo "  entities.md has no TODO markers. Numbers rest on your definitions, not on"
    echo "  the agent's assumptions."
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Portable protection
# ---------------------------------------------------------------------------
# Claude Code enforces the write rules through .claude/hooks/guard.py. Codex sets
# sandbox_mode = "workspace-write", which fences this folder but does not protect
# any file inside it. Other harnesses have no primitive at all.
#
# chmod is the one mechanism every harness and every model sees, because it is the
# filesystem rather than a vendor API. One guard per vendor is a maintenance debt
# that grows with each API change. This does not grow.
#
# It is a speed bump, not a security boundary. Anyone, human or agent, can run
# chmod u+w. What it buys is that a naive write fails loudly and a deliberate one
# takes a separate visible step.
#
# a-w and u+w are used instead of literal 444 and 644 so group bits and execute
# bits survive. A protected setup.sh or guard.py that lost its execute bit is a
# broken repo.

# Files a normal user never edits after cloning.
core_protected() {
  local p
  for p in CHARTER.md AGENTS.md CLAUDE.md setup.sh agents/roles.md \
           .claude/settings.json .claude/hooks/guard.py .githooks/pre-commit; do
    if [ -f "$p" ]; then printf '%s\n' "$p"; fi
  done
  # SKILL.md holds the contracts, and the folder-level AGENTS.md holds the rules
  # for picking between them. Both are specification, neither is agent-writable.
  # index.md stays writable on purpose: the agent maintains the map.
  find skills -type f \( -name SKILL.md -o -name AGENTS.md \) 2>/dev/null | sort || true
  for p in evals/*.sh; do
    if [ -f "$p" ]; then printf '%s\n' "$p"; fi
  done
}

# The knowledge base ships unfilled, and the user has to write to it to finish
# setup. So it is protected only once it is filled, never on first run.
kb_protected() {
  local p
  for p in knowledge-base/*.md; do
    if [ -f "$p" ]; then printf '%s\n' "$p"; fi
  done
}

# Returns 0 when setup is unfinished: entities.md is missing, or still has TODO
# markers. A missing file is unfinished, not filled.
kb_unfilled() {
  [ -f knowledge-base/entities.md ] || return 0
  grep -q 'TODO' knowledge-base/entities.md
}

wire_git_hook() {
  if [ ! -f .githooks/pre-commit ]; then
    warn ".githooks/pre-commit not found. Nothing to wire."
    return 0
  fi
  chmod +x .githooks/pre-commit 2>/dev/null || true
  if ! have git; then
    warn "git not found. Skipped the commit hook."
    return 0
  fi
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    warn "not a git repository yet. Run git init, then ./setup.sh --protect again"
    warn "to wire the commit hook."
    return 0
  fi
  git config core.hooksPath .githooks
  ok "git core.hooksPath set to .githooks."
  echo "  A commit touching a protected path is now refused and the paths are named."
  echo "  To commit one on purpose: PAOS_ALLOW_PROTECTED=1 git commit -m \"...\""
  return 0
}

protect_repo() {
  local force="${1:-}" list f n=0
  sec "Protection"

  list="$(mktemp)"
  core_protected > "$list"

  if kb_unfilled; then
    if [ "$force" = "force" ]; then
      kb_protected >> "$list"
      warn "knowledge-base/ locked anyway, because you passed --force."
      warn "entities.md is missing or still has TODO markers. You cannot finish setup until you"
      warn "run ./setup.sh --unprotect."
    else
      warn "knowledge-base/ NOT locked. entities.md is missing or still has TODO markers."
      echo "  Locking it now would block you from finishing setup, so it was skipped."
      echo "  Fill entities.md in, then run ./setup.sh --protect again."
      echo "  To lock it unfilled anyway: ./setup.sh --protect --force"
    fi
  else
    kb_protected >> "$list"
  fi

  while IFS= read -r f; do
    [ -f "$f" ] || continue
    chmod a-w "$f"
    n=$((n + 1))
  done < "$list"
  rm -f "$list"

  ok "locked $n files read-only. Execute bits untouched."
  echo ""
  echo "  This is a speed bump, not a security boundary. chmod u+w undoes it."
  echo "  It stops a naive write on any harness, and makes a deliberate one visible."
  echo "  To edit these files yourself: ./setup.sh --unprotect"
  wire_git_hook
  return 0
}

unprotect_repo() {
  local list f n=0
  sec "Protection"
  list="$(mktemp)"
  { core_protected; kb_protected; } > "$list"
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    chmod u+w "$f"
    n=$((n + 1))
  done < "$list"
  rm -f "$list"
  ok "$n files are writable again. Execute bits untouched."
  echo ""
  echo "  Run ./setup.sh --protect when you are done editing. While the repo is"
  echo "  unprotected, an agent on any harness can rewrite your definitions and the"
  echo "  only trace is the diff."
  return 0
}

protection_status() {
  local list f locked=0 open=0
  sec "Protection status"
  list="$(mktemp)"
  { core_protected; kb_protected; } > "$list"
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    if [ -w "$f" ]; then
      printf '  writable %s\n' "$f"
      open=$((open + 1))
    else
      printf '  locked   %s\n' "$f"
      locked=$((locked + 1))
    fi
  done < "$list"
  rm -f "$list"
  echo ""
  echo "  $locked locked, $open writable."
  if kb_unfilled; then
    echo "  knowledge-base/ is expected to be writable. entities.md is missing or"
    echo "  still has TODO markers, so setup is not finished."
  fi
  return 0
}

# Warns, never fails. A fresh clone is unprotected on purpose, the same reason a
# blocked source does not fail the check.
check_protection() {
  local list f total=0 writable=0
  sec "Protection"
  list="$(mktemp)"
  { core_protected; kb_protected; } > "$list"
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    total=$((total + 1))
    if [ -w "$f" ]; then writable=$((writable + 1)); fi
  done < "$list"
  rm -f "$list"

  if [ "$total" -eq 0 ]; then
    warn "no protectable files found."
  elif [ "$writable" -eq 0 ]; then
    ok "all $total protected files are read-only."
  else
    warn "$writable of $total protected files are writable."
    echo "  Run ./setup.sh --protect to lock them. A fresh clone is unprotected, so"
    echo "  this is a warning and not a failure."
  fi
  return 0
}

run_check() {
  local fail=0
  check_prereqs   || fail=1
  check_structure || fail=1
  ensure_workspace_files || fail=1
  check_workspace_untracked || fail=1
  check_sources   || fail=1
  check_knowledge_base || fail=1
  check_protection || true
  check_guardrails || fail=1

  sec "Result"
  if [ "$fail" -eq 0 ]; then
    echo "  check passed. Nothing required is missing."
  else
    echo "  check FAILED. Fix the MISSING lines above."
  fi
  return "$fail"
}

# ---------------------------------------------------------------------------
next_steps() {
  cat <<'EOF'

== What to do next ==

1. Fill in .env for the sources you picked. Names are in .env.example. Never
   commit a value, and never paste one into a chat, a report or log.md.
2. Create the read-only credential for each source, following the steps above
   or sources/connectors/<name>.md. This script does not do it for you, on
   purpose: it never touches a credential.
3. Paste the MCP block into your client's config, then restart the client so it
   picks the server up.
4. Run the smoke test in sources/connectors/<name>.md. It is one bounded read.
5. If rows come back, edit sources/sources.md by hand: set Readiness to ready
   and put today's date in the verification column. A stored credential is not
   readiness (CHARTER C-08).
6. Run ./setup.sh --check to confirm the repo, the env vars and the guardrails
   are all in order.

EOF
}

usage() {
  cat <<'EOF'
setup.sh, source connection setup for product-analyst-os.

Usage:
  ./setup.sh           interactive first-run setup. Walks the 7 sources, asks
                       which to connect, prints the env var names, the MCP
                       config block and the read-only credential steps for each.
  ./setup.sh --check   non-interactive health check. Verifies the repo layout,
                       that every env var named in sources/sources.md is set,
                       that git tracks none of your gitignored workspace, and
                       smoke-tests the guard. Exits non-zero if
                       anything required is missing. Creates any missing
                       workspace file from its _template/ blank, and never
                       overwrites one.

  ./setup.sh --protect          chmod the rule files and the knowledge base
                                read-only, and wire .githooks/pre-commit if this
                                is a git repo. Skips knowledge-base/ while
                                entities.md still has TODO markers, so it cannot
                                lock you out of finishing setup.
  ./setup.sh --protect --force  lock knowledge-base/ even when it is unfilled.
  ./setup.sh --protect --status list every protected file and whether it is
                                currently locked or writable.
  ./setup.sh --unprotect        make them writable again.

  ./setup.sh --help    this text.

Protection is chmod, so it works on Claude Code, Codex, and any other harness.
It is a speed bump, not a security boundary: chmod u+w undoes it. It stops a
naive write and makes a deliberate one a separate visible step.

This script is network-free and install-free. It never installs a package, never
calls a data source, and never reads, prints or asks for a secret value. It asks
for env var names and non-secret handles only.

Sources in v1: PostHog, Mixpanel, Amplitude, BigQuery, Metabase, MongoDB,
Postgres/Supabase. CleverTap is deliberately excluded, see docs/connectors-research.md.
EOF
}

case "${1:-}" in
  --check) run_check ;;
  --protect)
    case "${2:-}" in
      "")       protect_repo ;;
      --force)  protect_repo force ;;
      --status) protection_status ;;
      *) echo "Unknown option: --protect $2" >&2; echo "" >&2; usage >&2; exit 64 ;;
    esac
    ;;
  --unprotect) unprotect_repo ;;
  --help|-h) usage ;;
  "") interactive ;;
  *) echo "Unknown option: $1" >&2; echo "" >&2; usage >&2; exit 64 ;;
esac
