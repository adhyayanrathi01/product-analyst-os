#!/usr/bin/env bash
# Self-check for the PostToolUse report lint hook, lint-report.sh.
#
# Proves the hook stays silent on a clean report or an out-of-scope call, and
# speaks up with additionalContext carrying a FAIL/WARN line on a bad one. Run
# this after any edit to .claude/hooks/lint-report.sh. setup.sh --check runs it.
set -uo pipefail

HOOK="${LINT_HOOK:-.claude/hooks/lint-report.sh}"

pass=0
fail=0

dir="$(mktemp -d)" || { echo "cannot make a temp dir"; exit 1; }
trap 'rm -rf "$dir"' EXIT
mkdir -p "$dir/reports/_template"

cat > "$dir/reports/clean.md" <<'CLEAN'
# How many accounts signed up in August 2026?

## Question
New accounts created in August 2026. Grain: account, accounts.id.

## Facts
August 2026 signups: **842 accounts**. Row count: 1. Window 2026-08-01 to 2026-08-31.

```sql
SELECT COUNT(*) AS accounts FROM accounts
WHERE created_at >= TIMESTAMP '2026-08-01 00:00:00+00'
  AND created_at <  TIMESTAMP '2026-09-01 00:00:00+00'
  AND is_internal IS NOT TRUE
  AND account_type <> 'demo'
LIMIT 10;
```

## Exclusions applied
E-3 internal flag and E-4 demo accounts, applied directly in the query above. E-1
and E-2 are user-grain rules and remove nothing from this account-grain count.

## Interpretation
842 sits inside the normal range for the last three months. No notable change.
CLEAN

cat > "$dir/reports/bad.md" <<'BAD'
# Draft report

## Question
Something to check later, not filled in yet.
BAD

cat > "$dir/reports/_template/report.md" <<'TPL'
# <one-line question>

## Question
Guidance text, not a real report.
TPL

json() { # tool_name, file_path
  python3 -c 'import json,sys; print(json.dumps({"tool_name": sys.argv[1], "tool_input": {"file_path": sys.argv[2]}}))' "$1" "$2"
}

check() { # name, stdin, want_exit, want_mode(empty|nonempty), want_substrings...
  local name="$1" input="$2" want_exit="$3" want_mode="$4"
  shift 4
  local out got_exit ok=1 term
  out="$(printf '%s' "$input" | "$HOOK" 2>/dev/null)"
  got_exit=$?
  [ "$got_exit" = "$want_exit" ] || ok=0
  if [ "$want_mode" = "empty" ]; then
    [ -z "$out" ] || ok=0
  else
    [ -n "$out" ] || ok=0
    for term in "$@"; do
      printf '%s' "$out" | grep -q "$term" || ok=0
    done
  fi
  if [ "$ok" = 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $name (exit $got_exit, output: ${out:0:200})"
  fi
}

check "a. write to report with findings" "$(json Write "$dir/reports/bad.md")" \
  0 nonempty "additionalContext" "FAIL"
check "b. write to clean report" "$(json Write "$dir/reports/clean.md")" \
  0 empty
check "c. write to reports/_template/report.md" \
  "$(json Write "$dir/reports/_template/report.md")" 0 empty
check "d. write to schema/posthog/schema.md" \
  "$(json Write "schema/posthog/schema.md")" 0 empty
check "e. a Bash tool call" \
  '{"tool_name":"Bash","tool_input":{"command":"ls"}}' 0 empty
check "f. garbage stdin" "not json at all" 0 empty
check "g. report path that does not exist on disk" \
  "$(json Write "$dir/reports/ghost.md")" 0 empty

echo "---"
echo "lint-hook: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
