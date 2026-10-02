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
  5. A connector already attached to the user's client or account runs as the
     user, often with an admin role, and exposes write tools (Create-Dashboard,
     update_question, send_message) next to the read ones. No scoped credential
     stands behind it, so the tool name is the only thing left to check.

MCP calls are checked twice. The tool name is split into words and blocked
when any word is a write or send verb. Then any SQL-shaped argument must be a
bounded read. Names are matched only to BLOCK, never to allow, so a server
that names a write tool innocently gets through: the credential's grants are
the real control, and this is the backstop for when there are none. The MCP
spec's readOnlyHint and destructiveHint are untrusted (AGENTS.md) and are never
read here.

Sends are hard-blocked too, not returned as an "ask". A hook "ask" is not on
Claude Code's list of prompts that bypassPermissions still shows, so it can
pass silently in that mode. Exit 2 holds in every mode.

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

# --- MCP write and send tools, by name ----------------------------------------
# Whole words only, after splitting on - _ . and camelCase, so Get-Events,
# read_resource, Run-Query and execute_sql pass, and update inside updated_at
# never matches. ANY word counts, not just the first, so a vendor prefix
# (chat_send_message) cannot hide the verb. That blocks a few reads whose names
# carry a verb as a noun (Find-Duplicate-Groups, Run-Experiment-Pre-Launch-
# Checks). Blocking more is the safe direction. Add a verb, never remove one to
# let a tool through: the user can run that tool outside this workspace.
# ponytail: a name blocklist fails open on a write tool named with a verb not
# listed here. The upgrade is a server-side read-only role, which C-08 asks for.
WRITE_VERBS = frozenset("""
    add alter append apply approve archive assign bulk cancel clear close commit
    connect copy create del delete deploy destroy disable dismiss drop duplicate
    edit enable erase fill forward grant import insert install invite label launch
    mark merge modify move mutate patch pause post publish purge push put reject
    remove rename replace reply reset restore resume revert revoke rm rollback
    save schedule send set share start stop submit sync toggle transition trash
    truncate unarchive uninstall unlabel unmark untrash update upload upsert write
""".split())


def tool_words(tool: str):
    """Words of the tool part of mcp__<server>__<tool>. A server name that
    itself holds __ pushes more words into the tool part, which only blocks
    more."""
    rest = tool[len("mcp__"):]
    name = rest.split("__", 1)[1] if "__" in rest else rest
    name = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1 \2", name)  # BIUpdate -> BI Update
    name = re.sub(r"([a-z0-9])([A-Z])", r"\1 \2", name)  # createIssue -> create Issue
    return [w.lower() for w in re.split(r"[^A-Za-z0-9]+", name) if w]


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
        # calls tool annotations untrusted, so the name and the statement are
        # what get read.
        verbs = sorted(set(tool_words(tool)) & WRITE_VERBS)
        if verbs:
            block(
                f"{tool} looks like a write or a send (`{verbs[0]}` in its name).\n"
                f"This workspace only reads. A dashboard, metric, cohort, flag or "
                f"event edit, and any message or post, needs the user's separate "
                f"explicit approval per action (CHARTER C-02), and a client "
                f"connector usually runs with the user's full role, so nothing "
                f"server-side stops it. Do not retry through another tool. If the "
                f"user wants it, they do it in that tool themselves. For a "
                f"message, draft the text in reports/ and hand it over.\n"
                f"If this tool only reads, say so to the user. The guard blocks by "
                f"name, so it is safe to be wrong in this direction."
            )
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
