#!/usr/bin/env python3
"""PreToolUse guard for product-analyst-os.

Exists because prose does not enforce anything and Claude Code's path rules do
not cover Write. Deny rules in settings.json handle Read and Edit. This handles
the three gaps those rules leave open:

  1. Write(path) rules are accepted by settings.json and never consulted, so a
     protected file is writable via Write even when Edit is denied.
  2. Bash can read a denied path (cat .env) or write one (> CHARTER.md).
  3. Bash can run a destructive statement through a database client.

Exit 2 blocks the call and shows stderr to the model. Exit 0 allows.
Blocking here happens before permission rules evaluate and overrides allow
rules, but it cannot override a deny.
"""

import json
import re
import sys

# Paths the agent may never write, whatever tool it reaches for.
PROTECTED = (
    "CHARTER.md",
    "AGENTS.md",
    "CLAUDE.md",
    "setup.sh",
    ".claude/",
    ".codex/",
    "knowledge-base/",
    "evals/",
)

SECRETS = (".env", "secrets/", "id_rsa", ".pem", "credentials.json")

# Destructive SQL, but only when aimed at an actual data client. Matching these
# words alone would block "create a report" and every mkdir in the repo.
DB_CLIENT = re.compile(
    r"\b(psql|mysql|mongosh|mongo|bq|bigquery|supabase|metabase|clickhouse-client)\b"
)
DESTRUCTIVE = re.compile(
    r"\b(INSERT|UPDATE|DELETE|DROP|TRUNCATE|ALTER|CREATE|GRANT|REVOKE|MERGE|COPY)\s",
    re.IGNORECASE,
)

# Reading a secret through the shell, bypassing the Read deny rules.
READ_SECRET = re.compile(
    r"\b(cat|less|more|head|tail|bat|xxd|od|strings|grep|rg|awk|sed|source|\.)\b[^|;&]*"
    r"(\.env|secrets/|\.pem|id_rsa|credentials\.json)"
)


def block(reason: str) -> None:
    print(f"BLOCKED by .claude/hooks/guard.py\n\n{reason}", file=sys.stderr)
    sys.exit(2)


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        # Fail closed. A guard that cannot read its input has no idea what it is
        # letting through.
        block("Could not parse hook input. Refusing the call rather than guessing.")

    tool = payload.get("tool_name", "")
    args = payload.get("tool_input", {}) or {}

    if tool in ("Write", "Edit", "NotebookEdit"):
        path = str(args.get("file_path", ""))
        for prot in PROTECTED:
            if prot in path:
                block(
                    f"{path} is protected. It defines the rules you operate under, "
                    f"so an analysis task never edits it.\n"
                    f"Writable without asking: reports/, schema/, task.md, log.md, index.md.\n"
                    f"For knowledge-base/, show the user the exact diff and wait."
                )
        for sec in SECRETS:
            if sec in path:
                block(f"{path} holds credentials. Never write or read secret files.")

    elif tool == "Bash":
        cmd = str(args.get("command", ""))

        if READ_SECRET.search(cmd):
            block(
                "This reads a credentials file. Refer to secrets by environment-"
                "variable name only, never by value (CHARTER C-09)."
            )

        # Shell redirection into a protected path.
        for prot in PROTECTED:
            if re.search(r"(>>?|tee)\s+\.?/?" + re.escape(prot), cmd):
                block(f"This writes to the protected path {prot} through the shell.")

        if DB_CLIENT.search(cmd) and DESTRUCTIVE.search(cmd):
            block(
                "This runs a write statement against a data source. Every query is "
                "a read (CHARTER C-02). If the user genuinely wants a write, they "
                "run it themselves. Do not offer a workaround."
            )

    sys.exit(0)


if __name__ == "__main__":
    main()
