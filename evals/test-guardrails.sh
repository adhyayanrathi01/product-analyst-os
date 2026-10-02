#!/usr/bin/env bash
# Self-check that the PreToolUse guard fails when it should.
#
# A guard nobody tests is a guard that silently stopped working. Run this after
# any edit to .claude/hooks/guard.py. setup.sh --check runs it.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

GUARD="${GUARD_BIN:-.claude/hooks/guard.py}"
pass=0
fail=0

check() { # name, stdin json, expected exit code
  echo "$2" | "$GUARD" >/dev/null 2>&1
  local got=$?
  if [ "$got" = "$3" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $1 (expected exit $3, got $got)"
  fi
}

# Must block: protected paths via Write, which settings.json cannot cover.
check "Write to CHARTER.md"      '{"tool_name":"Write","tool_input":{"file_path":"CHARTER.md"}}' 2
check "Write to AGENTS.md"       '{"tool_name":"Write","tool_input":{"file_path":"AGENTS.md"}}' 2
check "Write to knowledge-base"  '{"tool_name":"Write","tool_input":{"file_path":"knowledge-base/entities.md"}}' 2
check "Write to .claude"         '{"tool_name":"Write","tool_input":{"file_path":".claude/settings.json"}}' 2
check "Write to setup.sh"        '{"tool_name":"Edit","tool_input":{"file_path":"setup.sh"}}' 2
check "Write to a .env file"     '{"tool_name":"Write","tool_input":{"file_path":".env"}}' 2

# Must block: shell paths around the deny rules.
check "cat .env"                 '{"tool_name":"Bash","tool_input":{"command":"cat .env"}}' 2
check "grep a secret"            '{"tool_name":"Bash","tool_input":{"command":"grep KEY .env.local"}}' 2
check "redirect into CHARTER"    '{"tool_name":"Bash","tool_input":{"command":"echo x > CHARTER.md"}}' 2
check "tee into knowledge-base"  '{"tool_name":"Bash","tool_input":{"command":"echo x | tee knowledge-base/company.md"}}' 2

# Must block: writes aimed at a data source.
check "psql DROP"                '{"tool_name":"Bash","tool_input":{"command":"psql -c \"DROP TABLE users\""}}' 2
check "bq DELETE"                '{"tool_name":"Bash","tool_input":{"command":"bq query \"DELETE FROM t WHERE 1=1\""}}' 2
check "mongosh insert"           '{"tool_name":"Bash","tool_input":{"command":"mongosh --eval \"db.t.INSERT ({})\""}}' 2

# Must block: evals/ check scripts stay protected (CHARTER C-12).
check "Write to test-guardrails" '{"tool_name":"Write","tool_input":{"file_path":"evals/test-guardrails.sh"}}' 2
check "Write to check-output"    '{"tool_name":"Write","tool_input":{"file_path":"evals/check-output.sh"}}' 2

# Must block: SQL sent through an MCP tool, which the old matcher never saw.
check "mcp DROP"                 '{"tool_name":"mcp__postgres__execute_sql","tool_input":{"sql":"DROP TABLE users"}}' 2
check "mcp DELETE in a CTE"      '{"tool_name":"mcp__supabase__execute_sql","tool_input":{"query":"WITH d AS (DELETE FROM users RETURNING *) SELECT * FROM d LIMIT 5"}}' 2
check "mcp two statements"       '{"tool_name":"mcp__postgres__execute_sql","tool_input":{"sql":"SELECT 1 LIMIT 1; SELECT 2 LIMIT 1"}}' 2
check "mcp UPDATE"               '{"tool_name":"mcp__bigquery__execute_sql","tool_input":{"sql":"UPDATE t SET a = 1 WHERE b = 2"}}' 2
check "mcp SELECT, no LIMIT"     '{"tool_name":"mcp__postgres__execute_sql","tool_input":{"sql":"SELECT * FROM users"}}' 0
check "mcp introspection query"  '{"tool_name":"mcp__postgres__execute_sql","tool_input":{"sql":"SELECT table_name, column_name FROM information_schema.columns WHERE table_schema = '\''public'\''"}}' 0

# Must allow: the actual job.
check "Write a report"           '{"tool_name":"Write","tool_input":{"file_path":"reports/2026-09-08-activation.md"}}' 0
check "Write a schema file"      '{"tool_name":"Write","tool_input":{"file_path":"schema/posthog/schema.md"}}' 0
check "Append to log.md"         '{"tool_name":"Edit","tool_input":{"file_path":"log.md"}}' 0
check "psql SELECT"              '{"tool_name":"Bash","tool_input":{"command":"psql -c \"SELECT count(*) FROM users LIMIT 10\""}}' 0
check "the word create in prose" '{"tool_name":"Bash","tool_input":{"command":"mkdir -p reports && echo create a report"}}' 0

# Must allow: bounded reads, and MCP calls that carry no SQL at all.
check "Write an eval scenario"   '{"tool_name":"Write","tool_input":{"file_path":"evals/scenarios/S-4-new.md"}}' 0
check "mcp bounded SELECT"       '{"tool_name":"mcp__postgres__execute_sql","tool_input":{"sql":"SELECT count(*) FROM users LIMIT 10"}}' 0
check "mcp read-only WITH"       '{"tool_name":"mcp__supabase__execute_sql","tool_input":{"query":"WITH a AS (SELECT id FROM users) SELECT count(*) FROM a LIMIT 1"}}' 0
check "mcp natural language"     '{"tool_name":"mcp__amplitude__query_chart","tool_input":{"query":"how many users did we update on last week? delete from the roadmap"}}' 0
check "mcp metric lookup"        '{"tool_name":"mcp__mixpanel__get_metric","tool_input":{"metric":"weekly_active_users","days":30}}' 0
check "mcp update in a name"     '{"tool_name":"mcp__postgres__execute_sql","tool_input":{"sql":"SELECT last_update, updated_at FROM t WHERE note = '\''update'\'' LIMIT 5"}}' 0

# Must fail closed on garbage input.
check "unparseable input"        'not json at all' 2

echo "---"
echo "guardrails: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
