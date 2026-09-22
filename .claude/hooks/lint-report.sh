#!/usr/bin/env bash
# PostToolUse hook: lints a report right after it lands.
# Runs evals/check-output.sh on any Write or Edit into reports/*.md, other than
# reports/_template/, and hands FAIL/WARN findings back to the model as
# additionalContext. Success is silent, findings are verbose. This is a lint,
# not a gate: the write already happened, so it always exits 0.
set -uo pipefail

input="$(cat)"
parsed="$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print(d.get("tool_name", ""))
print((d.get("tool_input") or {}).get("file_path", ""))
')"
tool_name="$(printf '%s\n' "$parsed" | sed -n '1p')"
file="$(printf '%s\n' "$parsed" | sed -n '2p')"

[ "$tool_name" = "Write" ] || [ "$tool_name" = "Edit" ] || exit 0
case "$file" in
  *reports/_template/*) exit 0 ;;
esac
case "$file" in
  *reports/*.md) : ;;
  *) exit 0 ;;
esac

if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  root="$CLAUDE_PROJECT_DIR"
else
  root="$(cd "$(dirname "$0")/../.." && pwd)"
fi
case "$file" in
  /*) target="$file" ;;
  *) target="$root/$file" ;;
esac

output="$("$root/evals/check-output.sh" "$target" 2>/dev/null)"
printf '%s\n' "$output" | grep -qE '^(FAIL|WARN)  ' || exit 0

printf '%s' "$output" | python3 -c '
import json, sys
lint = sys.stdin.read()
file_path = sys.argv[1]
prefix = ("evals/check-output.sh findings for " + file_path +
          ". It is a lint, not a gate. Read and decide.")
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": prefix + "\n\n" + lint,
}}))
' "$file"
exit 0
