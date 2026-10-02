#!/usr/bin/env python3
"""PreToolUse guard for product-analyst-os.

Exists because prose does not enforce anything and Claude Code's path rules do
not cover Write. Deny rules in settings.json handle Read and Edit. This handles
the three gaps those rules leave open:

  1. Write(path) rules are accepted by settings.json and never consulted, so a
     protected file is writable via Write even when Edit is denied.
  2. Bash can read a denied path (cat .env) or write one (> CHARTER.md).
  3. Bash can run a destructive statement through a database client.
  4. MCP tools (mcp__<server>__<tool>) never matched the old hook matcher, so a
     destructive statement sent through an MCP SQL tool was never inspected.

MCP calls are checked only when the tool input carries a SQL-shaped argument.
The MCP spec's readOnlyHint and destructiveHint are untrusted (AGENTS.md) and
are never read here.

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
)

# CHARTER C-12 lets an agent author scenarios, fixtures and results under
# evals/. It may not edit a check, so only the test scripts are protected. This
# matches setup.sh, which protects evals/*.sh. Case-insensitive because the
# default macOS filesystem is.
EVAL_SCRIPT = re.compile(r"(^|/)evals/.*\.sh$", re.IGNORECASE)
EVAL_SCRIPT_REDIRECT = re.compile(r"(>>?|tee)\s+\S*evals/\S*\.sh", re.IGNORECASE)

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

# --- MCP SQL inspection -----------------------------------------------------
# Keys that always hold SQL: the value must be a bounded read, full stop.
SQL_STRONG = ("sql", "sql_query", "native_query")
# Keys that hold SQL on some tools and a natural-language question, a search
# string or a metric name on others. Checked only when the value is SQL-shaped.
SQL_WEAK = ("query", "q", "statement")

_STMT = r"(?:^|[;()])\s*"
# Statement keywords at statement position (start, or after ; ( ) so a DELETE
# buried in a CTE is seen). A column called update or created_at is not at
# statement position. INSERT( and TRUNCATE( are functions in MySQL and others.
BARE_WRITE = re.compile(
    _STMT + r"((?:INSERT|TRUNCATE)\b(?!\s*\()|UPDATE|DELETE|DROP|ALTER|CREATE|GRANT|REVOKE|MERGE|COPY)\b",
    re.IGNORECASE,
)
# Unambiguous two-word write forms, matched anywhere, so a statement run on
# without a semicolon (SQL Server style) is still seen.
_NOUNS = (r"TABLE|VIEW|SCHEMA|DATABASE|INDEX|FUNCTION|PROCEDURE|SEQUENCE|TYPE|ROLE|USER"
          r"|TRIGGER|EXTENSION|MODEL|SNAPSHOT")
_NOUN = "(?:" + _NOUNS + ")"
_WF = (
    r"INSERT\s+(?:INTO|OVERWRITE)\b|UPDATE\s+\S+\s+SET\b|DELETE\s+FROM\b"
    r"|DROP\s+(?:(?:TEMP\w*|MATERIALIZED|EXTERNAL)\s+)?" + _NOUN + r"\b"
    r"|TRUNCATE\s+TABLE\b|ALTER\s+(?:" + _NOUNS + r"|SYSTEM|MATERIALIZED)\b"
    r"|CREATE\s+(?:OR\s+REPLACE\s+)?(?:(?:TEMP\w*|UNIQUE|MATERIALIZED|EXTERNAL|RECURSIVE)\s+)*" + _NOUN + r"\b"
)
WRITE_FORM = re.compile(r"\b(?:" + _WF + r")", re.IGNORECASE)
# Decides whether a weak-key value is SQL at all. A natural-language question
# that merely contains the word update or delete is not.
SQL_SHAPE = re.compile(
    r"^[\s(]*select\b"
    r"|^[\s(]*with\s+(?:recursive\s+)?\S+\s*(?:\([^)]*\)\s*)?as\s*(?:not\s+)?(?:materialized\s*)?\("
    + r"|" + _STMT + r"(?:" + _WF + r"|TRUNCATE\s+(?:TABLE\s+)?[\w.\"`']+(?=\s*(?:;|$))|GRANT\s[\s\S]+?\s(?:ON|TO)\s"
    r"|REVOKE\s[\s\S]+?\s(?:ON|FROM)\s|MERGE\s+(?:INTO\s+)?\S+\s+(?:AS\s+\w+\s+)?USING\b"
    r"|COPY\s+(?:\(|\S+\s+(?:\([^)]*\)\s+)?(?:FROM|TO)\b))",
    re.IGNORECASE,
)


def _strip(sql: str, backslash_escapes: bool) -> str:
    """Drop comments, blank out string literals and quoted identifiers.

    Backslash is an escape in MySQL and BigQuery and not in Postgres. The caller
    runs both readings and blocks if either one finds a problem, so neither
    dialect can hide a second statement behind a quote. A # is NOT a comment
    here (it is a Postgres operator), so a # line is read as code. /*! ... */
    runs in MySQL, so it is read as code too.
    """
    out, i, n = [], 0, len(sql)
    while i < n:
        c = sql[i]
        if sql.startswith("--", i):
            j = sql.find("\n", i)
            i = n if j < 0 else j
            out.append(" ")
        elif sql.startswith("/*", i) and not sql.startswith("/*!", i):
            j = sql.find("*/", i + 2)
            i = n if j < 0 else j + 2
            out.append(" ")
        elif c in "'\"`":
            i += 1
            while i < n and sql[i] != c:
                i += 2 if (backslash_escapes and sql[i] == "\\") else 1
            i += 1
            out.append(c + c)
        else:
            out.append(c)
            i += 1
    return "".join(out)


def sql_problem(sql: str, strong: bool):
    """Return why this is not a bounded read, or None. Weak keys that do not
    look like SQL return None."""
    for backslash_escapes in (False, True):
        c = _strip(sql, backslash_escapes)
        if not strong and not SQL_SHAPE.search(c):
            continue
        body = re.sub(r"[;\s]+$", "", c).lstrip()
        if not body:
            continue
        if ";" in body:
            return "it holds more than one statement. One statement per call."
        if not re.match(r"[\s(]*(select|with)\b", body, re.IGNORECASE):
            return "it does not start with SELECT or WITH."
        m = BARE_WRITE.search(body) or WRITE_FORM.search(body)
        if m:
            word = re.search("[A-Za-z]+", m.group(0)).group(0).upper()
            return f"it contains a write statement ({word})."
        if re.search(r"\binto\b", body, re.IGNORECASE):
            return "it contains INTO, which writes a table or a file."
    # A missing LIMIT is deliberately NOT blocked here. It is a spend and
    # latency concern, not a destruction one, and the controls that actually
    # bound it are maximum_bytes_billed, the role's statement_timeout and the
    # read-only grant. Blocking it would also refuse the schema introspection
    # in sources/connectors/, and would teach the agent to bolt a LIMIT onto
    # an INFORMATION_SCHEMA scan, which truncates a schema capture silently.
    # AGENTS.md still asks for a LIMIT. This guard just is not the enforcer.
    return None


def sql_values(obj, strong=False, key=""):
    """Yield (key, string, strong) for every SQL-bearing argument, at any depth."""
    if isinstance(obj, dict):
        for k, v in obj.items():
            lk = str(k).lower()
            yield from sql_values(v, strong or lk in SQL_STRONG, lk)
    elif isinstance(obj, list):
        for v in obj:
            yield from sql_values(v, strong, key)
    elif isinstance(obj, str) and (strong or key in SQL_WEAK):
        yield key, obj, strong


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

    if not isinstance(payload, dict):
        block("Hook input is not a JSON object. Refusing the call rather than guessing.")

    tool = str(payload.get("tool_name", ""))
    args = payload.get("tool_input", {}) or {}
    if not isinstance(args, dict):
        args = {}

    if tool in ("Write", "Edit", "NotebookEdit"):
        # NotebookEdit names its target notebook_path, not file_path.
        path = str(args.get("file_path") or args.get("notebook_path") or "")
        if EVAL_SCRIPT.search(path):
            block(
                f"{path} is a check. C-12 lets you author scenarios, fixtures and "
                f"results under evals/, never edit a check to make it pass.\n"
                f"If the check is wrong, tell the user. That is a spec change they ask for."
            )
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
        if EVAL_SCRIPT_REDIRECT.search(cmd):
            block("This writes to an evals/ check script through the shell (CHARTER C-12).")

        if DB_CLIENT.search(cmd) and DESTRUCTIVE.search(cmd):
            block(
                "This runs a write statement against a data source. Every query is "
                "a read (CHARTER C-02). If the user genuinely wants a write, they "
                "run it themselves. Do not offer a workaround."
            )

    elif tool.startswith("mcp__"):
        # Deliberately ignores readOnlyHint and destructiveHint. The MCP spec
        # calls tool annotations untrusted, so the statement is what gets read.
        for key, value, strong in sql_values(args):
            why = sql_problem(value, strong)
            if why:
                block(
                    f"{tool} was sent SQL in `{key}` and {why}\n"
                    f"Every query is a bounded read: one statement, SELECT or WITH, "
                    f"no write keyword anywhere (CHARTER C-02). If the user "
                    f"genuinely wants a write, they run it themselves. Do not offer "
                    f"a workaround."
                )

    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:  # fail closed: an uncaught crash exits 1, which allows
        block(f"Guard crashed ({type(exc).__name__}). Refusing the call rather than guessing.")
