#!/usr/bin/env bash
# Self-check that the PreToolUse guard fails when it should.
#
# A guard nobody tests is a guard that silently stopped working. Run this after
# any edit to .claude/hooks/guard.py. setup.sh --check runs it.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

GUARD=.claude/hooks/guard.py
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

# Must allow: the actual job.
check "Write a report"           '{"tool_name":"Write","tool_input":{"file_path":"reports/2026-09-08-activation.md"}}' 0
check "Write a schema file"      '{"tool_name":"Write","tool_input":{"file_path":"schema/posthog/schema.md"}}' 0
check "Append to log.md"         '{"tool_name":"Edit","tool_input":{"file_path":"log.md"}}' 0
check "psql SELECT"              '{"tool_name":"Bash","tool_input":{"command":"psql -c \"SELECT count(*) FROM users LIMIT 10\""}}' 0
check "the word create in prose" '{"tool_name":"Bash","tool_input":{"command":"mkdir -p reports && echo create a report"}}' 0

# Must fail closed on garbage input.
check "unparseable input"        'not json at all' 2

echo "---"
echo "guardrails: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
