#!/usr/bin/env bash
# This is a lint, not a gate.
#
# It reads a report and prints what it noticed. By default it exits 0 even when it
# finds something, because you decide whether a finding matters for your question.
# Pass --strict to make findings exit 1, which is what you want in CI.
#
# It checks structure against reports/_template/report.md and the charter clauses that
# can be checked without judgment: C-05 absolute dates and a query per number, C-09 no
# secrets and no raw email addresses, C-10 exclusions stated and, when rule ids are
# cited, at least one fenced query that filters. It cannot match an id to its predicate.
#
# It cannot tell you whether the analysis is sound. A clean run here means the shape is
# right. It says nothing about whether the number is right.
#
# Usage:
#   ./evals/check-output.sh <artifact-path>
#   ./evals/check-output.sh --strict <artifact-path>
#   ./evals/check-output.sh --self-test
#
# Exit 0 normally, even with findings. Exit 1 only with --strict and at least one
# finding. Exit 2 when the file cannot be read or the usage is wrong.
# Dependencies: bash, grep, awk, sed, mktemp. Nothing else.
set -uo pipefail

STRICT=0
pass_count=0
fail_count=0
warn_count=0

ok()   { printf 'PASS  %s\n' "$1"; pass_count=$((pass_count + 1)); }
bad()  { printf 'FAIL  %s\n' "$1"; fail_count=$((fail_count + 1)); }
warn() { printf 'WARN  %s\n' "$1"; warn_count=$((warn_count + 1)); }
note() { printf 'NOTE  %s\n' "$1"; }

# Short form. Required in both report shapes.
CORE_SECTIONS='Question
Facts
Exclusions applied
Interpretation'

# Full form adds these. Absent means short form, which is fine for a single-source
# question. See reports/_template/report.md.
FULL_SECTIONS='Sources
Time range
Filters
Confidence and gaps
Recommended next check'

# Body of a markdown section: everything after the heading, up to the next heading.
section_body() { # $1 heading text, $2 file
  awk -v h="$1" '
    !inb && $0 ~ "^#+[ \t]+" h "[ \t]*$" { inb = 1; next }
    inb && /^#+[ \t]/ { exit }
    inb { print }
  ' "$2"
}

has_heading() { # $1 heading text, $2 file
  grep -Eq "^#{1,6}[[:space:]]+$1[[:space:]]*$" "$2"
}

# Text inside fenced code blocks, fence lines excluded. A fence opens on a line that
# starts with three or more backticks and closes on a line of at least as many
# backticks and nothing else, so a four-backtick block can hold a three-backtick one.
fenced_text() { # $1 file
  awk '
    function ticks(s,   n) { sub(/^[ \t]*/, "", s); n = 0
      while (substr(s, n + 1, 1) == "`") n++; return n }
    function rest(s,   n) { sub(/^[ \t]*/, "", s); n = ticks(s); return substr(s, n + 1) }
    !inf && ticks($0) >= 3 { inf = 1; fl = ticks($0); next }
    inf && ticks($0) >= fl && rest($0) ~ /^[ \t]*$/ { inf = 0; next }
    inf { print }
  ' "$1"
}

check_artifact() {
  local file="$1"

  # --- 1. Sections present as headings --------------------------------------
  local missing="" absent="" s
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    has_heading "$s" "$file" || missing="$missing, $s"
  done <<EOF
$CORE_SECTIONS
EOF
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    has_heading "$s" "$file" || absent="$absent, $s"
  done <<EOF
$FULL_SECTIONS
EOF

  if [ -n "$missing" ]; then
    bad "missing short-form section(s):${missing#,}. Both shapes need these four."
  elif [ -z "$absent" ]; then
    ok "full form, all 9 sections present"
  else
    ok "short form, all 4 required sections present"
    note "full-form sections not present:${absent#,}"
    note "that is fine for a single-source question. Ask for the full form when it"
    note "crosses sources, spans time periods, or feeds a decision that matters."
  fi

  # --- 2. Exclusions stated, and not a bare "none" (C-10) -------------------
  if has_heading "Exclusions applied" "$file"; then
    local excl squashed words
    excl="$(section_body "Exclusions applied" "$file")"
    # Strip markdown noise and collapse whitespace so "**None.**" reads as "none".
    squashed="$(printf '%s' "$excl" \
      | tr 'A-Z' 'a-z' \
      | tr -d '*_`>#|' \
      | tr -s '[:space:]' ' ' \
      | sed 's/^ *//; s/ *$//')"
    words="$(printf '%s' "$squashed" | wc -w | tr -d ' ')"
    if [ -z "$squashed" ]; then
      bad "Exclusions applied is empty (C-10 requires the exclusions to be stated)"
    elif printf '%s' "$squashed" | grep -Eq '^(none|n/a|na|nil|no exclusions|none applied|no exclusions applied|not applicable)[.!]?$'; then
      bad "Exclusions applied says only \"$squashed\" with no reason (C-10)"
    elif printf '%s' "$squashed" | grep -Eq '\b(none|no exclusions)\b' && [ "$words" -lt 8 ]; then
      bad "Exclusions applied claims none without stating why (C-10)"
    else
      ok "Exclusions applied is stated with content"
    fi
  else
    bad "Exclusions applied section absent, so exclusions cannot be checked (C-10)"
  fi

  # --- 3. No unresolved relative dates in Time range (C-05) -----------------
  if has_heading "Time range" "$file"; then
    local tr hits mon
    mon='(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?,?[[:space:]]+'
    # Lowercase, then drop "the last day of August 2026" and similar. A phrase that
    # carries its own explicit year (and month, if given) is absolute, not relative.
    tr="$(section_body "Time range" "$file" | tr 'A-Z' 'a-z' | sed -E \
      "s/(last|past)[[:space:]]+([0-9]+[[:space:]]+)?(day|week|month|quarter|year)s?[[:space:]]+of[[:space:]]+(the[[:space:]]+year[[:space:]]+)?(${mon})?[0-9]{4}//g")"
    hits="$(printf '%s\n' "$tr" | grep -Eio \
      -e 'last[[:space:]]+[0-9]+[[:space:]]+(day|week|month|quarter|year)s?' \
      -e 'past[[:space:]]+[0-9]+[[:space:]]+(day|week|month|quarter|year)s?' \
      -e 'trailing[[:space:]]+[0-9]+[[:space:]]+(day|week|month|quarter|year)s?' \
      -e 'last[[:space:]]+(day|week|month|quarter|year)' \
      -e 'past[[:space:]]+(day|week|month|quarter|year)' \
      -e 'recently' \
      -e 'year[[:space:]-]to[[:space:]-]date' \
      -e 'ytd' \
      | sort -u | tr '\n' ' ' | sed 's/ *$//')"
    if [ -z "$hits" ]; then
      ok "Time range carries no unresolved relative dates"
    else
      bad "Time range contains relative date(s): $hits (C-05 requires absolute dates)"
    fi
  else
    note "no Time range section, so dates were not checked. Short form does not"
    note "require one, but any date inside Facts still has to be absolute (C-05)."
  fi

  # --- 4. Numbers in Facts must have a query somewhere in the file (C-05) ----
  # File-wide, not per number: this cannot tell which query produced which number.
  # It does catch the report with a number and no query at all.
  local queries
  queries="$(fenced_text "$file")"
  if has_heading "Facts" "$file"; then
    local facts
    facts="$(section_body "Facts" "$file")"
    if printf '%s' "$facts" | grep -q '[0-9]'; then
      if printf '%s' "$queries" | grep -q '[^[:space:]]'; then
        ok "Facts contains numbers and the file carries at least one fenced query"
      else
        bad "Facts contains numbers but the file has no fenced query block. Every number carries its query (C-05)."
      fi
    else
      ok "Facts contains no numbers, nothing to attach a query to"
    fi
  fi

  # --- 5. Cited exclusion ids need a filtering query (C-10) -------------------
  # Prose that names E-1..E-7 is not application. If ids are cited, at least one
  # fenced block must carry a WHERE or filter clause. This does not match which id
  # maps to which predicate. That is beyond a grep and would false-positive.
  if has_heading "Exclusions applied" "$file"; then
    local ids
    ids="$(section_body "Exclusions applied" "$file" | grep -Eo '\bE-[0-9]+\b' \
      | sort -t- -k2,2n -u | tr '\n' ' ' | sed 's/ *$//')"
    if [ -n "$ids" ]; then
      if printf '%s' "$queries" | grep -Eiq '\b(where|having|filter)\b|\$match|\.find\('; then
        ok "Exclusions applied cites $ids and a fenced query carries a filter clause"
      else
        bad "Exclusions applied cites $ids but no fenced query has a WHERE or filter clause. Naming a rule is not applying it (C-10)."
      fi
    fi
  fi

  # --- 6. No secrets (C-09) -------------------------------------------------
  local secrets
  secrets="$(grep -Eno \
    -e '[a-zA-Z][a-zA-Z0-9+.-]*://[^/[:space:]:@]+:[^[:space:]@]+@' \
    -e 'Bearer[[:space:]]+[A-Za-z0-9._~+/=-]{12,}' \
    -e '(^|[^A-Za-z0-9_])phx_[A-Za-z0-9_-]{8,}' \
    -e '(^|[^A-Za-z0-9_])sk-[A-Za-z0-9_-]{12,}' \
    -e '(api[_-]?key|apikey|access[_-]?token|secret[_-]?key)[[:space:]]*=[[:space:]]*[^[:space:]"'"'"'&]+' \
    "$file" | head -5)"
  if [ -z "$secrets" ]; then
    ok "no credential pattern found"
  else
    bad "credential pattern found, this must never ship (C-09). First matches:"
    printf '%s\n' "$secrets" | sed 's/^/        line /'
    printf '      This is the one finding not to wave through. Rotate the credential if\n'
    printf '      it was ever committed, and refer to it by env var name instead.\n'
  fi

  # --- 7. No raw email addresses (C-09) -------------------------------------
  # The local part must start with a letter or digit, so a SQL pattern such as
  # '%@nimbusfreight.example' (what E-1 looks like in a query) is not an address.
  # Line numbers only: printing the match would copy the personal data again.
  local emails
  emails="$(grep -nE '[A-Za-z0-9][A-Za-z0-9._+-]*@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}' \
    "$file" | cut -d: -f1 | head -5 | tr '\n' ' ' | sed 's/ *$//')"
  if [ -z "$emails" ]; then
    ok "no raw email address found"
  else
    bad "raw email address found on line(s): $emails. Aggregate or use an opaque id (C-09)."
  fi
}

# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------

write_good() { # $1 path
  cat > "$1" <<'GOOD'
# Did signups fall in January 2026?

## Question
Did new account signups fall in January 2026 versus December 2025?

## Sources
Postgres read replica, public.accounts. Ready.

## Time range
2025-12-01 00:00:00 UTC to 2026-01-31 23:59:59 UTC, inclusive.

## Filters
Grain: account. No plan filter.

## Exclusions applied
E-1 internal domains, E-2 internal account ids, E-4 demo accounts. E-6 not applied
because it is unconfirmed.

## Facts
December 2025 signups: 1204. Row count: 1.

```sql
SELECT COUNT(*) FROM accounts WHERE created_at >= '2025-12-01' LIMIT 10;
```

## Interpretation
A 6.1% fall, inside the 2025 month-to-month spread.

## Confidence and gaps
Medium. created_at is insert time, not submit time.

## Recommended next check
Split by signup_source over the same two months.
GOOD
}

self_test() {
  local dir rc sp sf
  dir="$(mktemp -d)" || { echo "cannot make a temp dir"; exit 2; }
  # shellcheck disable=SC2064
  trap "rm -rf '$dir'" EXIT

  sp=0
  sf=0
  assert() { # $1 label, $2 file, $3 expected default exit, $4 expected --strict exit
    local got
    "$0" "$2" >/dev/null 2>&1
    got=$?
    if [ "$got" = "$3" ]; then
      sp=$((sp + 1))
    else
      sf=$((sf + 1))
      printf 'SELF-TEST FAIL: %s, default run (expected exit %s, got %s)\n' "$1" "$3" "$got"
    fi
    "$0" --strict "$2" >/dev/null 2>&1
    got=$?
    if [ "$got" = "$4" ]; then
      sp=$((sp + 1))
    else
      sf=$((sf + 1))
      printf 'SELF-TEST FAIL: %s, --strict run (expected exit %s, got %s)\n' "$1" "$4" "$got"
    fi
  }

  has_line() { # $1 file, $2 pattern. Capture first: grep -q would SIGPIPE the script.
    local out
    out="$("$0" "$1" 2>&1)"
    printf '%s\n' "$out" | grep -q "$2"
  }

  # Every case below asserts twice: the default advisory run, then --strict. A finding
  # exits 0 by default and 1 under --strict. That difference is the whole point of the
  # flag, so each case states both.

  # Good artifact passes both ways.
  write_good "$dir/good.md"
  assert "good artifact passes" "$dir/good.md" 0 0

  # A full-form section missing is short form, not a finding, in either mode.
  grep -v '^## Confidence and gaps$' "$dir/good.md" > "$dir/short-form.md"
  assert "missing full-form section is not a finding" "$dir/short-form.md" 0 0

  # A short-form section missing is a finding in both shapes.
  grep -v '^## Facts$' "$dir/good.md" > "$dir/bad-missing-core.md"
  assert "missing core section is a finding" "$dir/bad-missing-core.md" 0 1

  # Exclusions says only "None."
  sed 's/^E-1 internal domains.*/None./; /^because it is unconfirmed\.$/d' \
    "$dir/good.md" > "$dir/bad-exclusions-none.md"
  assert "bare \"None.\" in exclusions" "$dir/bad-exclusions-none.md" 0 1

  # Exclusions section empty.
  awk '/^## Exclusions applied$/{print; skip=1; next} skip && /^## /{skip=0} !skip' \
    "$dir/good.md" > "$dir/bad-exclusions-empty.md"
  assert "empty exclusions" "$dir/bad-exclusions-empty.md" 0 1

  # Relative date left in Time range.
  sed 's/^2025-12-01 00:00:00 UTC.*/Last 30 days./' \
    "$dir/good.md" > "$dir/bad-relative-date.md"
  assert "relative date in Time range" "$dir/bad-relative-date.md" 0 1

  # Another relative phrase.
  sed 's/^2025-12-01 00:00:00 UTC.*/Recently, and YTD./' \
    "$dir/good.md" > "$dir/bad-relative-ytd.md"
  assert "recently and YTD in Time range" "$dir/bad-relative-ytd.md" 0 1

  # Secrets. Built at runtime so no literal credential sits in this file.
  local u p
  u='postgres://analyst'
  p='hunter2@db.internal:5432/prod'
  write_good "$dir/bad-secret-dsn.md"
  printf '\nConnection used: %s:%s\n' "$u" "$p" >> "$dir/bad-secret-dsn.md"
  assert "connection string" "$dir/bad-secret-dsn.md" 0 1

  write_good "$dir/bad-secret-bearer.md"
  printf '\nAuth header: Bearer %s\n' "abcdEFGH1234ijklMNOP5678" \
    >> "$dir/bad-secret-bearer.md"
  assert "bearer token" "$dir/bad-secret-bearer.md" 0 1

  write_good "$dir/bad-secret-phx.md"
  printf '\nKey: %s%s\n' 'phx_' 'A1b2C3d4E5f6G7h8' >> "$dir/bad-secret-phx.md"
  assert "phx_ key" "$dir/bad-secret-phx.md" 0 1

  write_good "$dir/bad-secret-sk.md"
  printf '\nKey: %s%s\n' 'sk-' 'proj0123456789abcdef' >> "$dir/bad-secret-sk.md"
  assert "sk- key" "$dir/bad-secret-sk.md" 0 1

  write_good "$dir/bad-secret-apikey.md"
  printf '\nCalled with %s%s\n' 'api_key=' 'ZmFrZTEyMzQ1' >> "$dir/bad-secret-apikey.md"
  assert "api_key with a value" "$dir/bad-secret-apikey.md" 0 1

  # A number in Facts with no fenced query anywhere is a finding, not a warning. The
  # exclusions prose here names no ids, so only the C-05 check can fire.
  grep -v '^```' "$dir/good.md" | grep -v '^SELECT COUNT' \
    | sed 's/^E-1 internal domains.*/Internal and demo accounts removed./; /^because it is unconfirmed\.$/d' \
    > "$dir/bad-no-query.md"
  assert "number with no fenced query anywhere" "$dir/bad-no-query.md" 0 1
  has_line "$dir/bad-no-query.md" '^FAIL  Facts contains numbers' \
    && sp=$((sp + 1)) || { sf=$((sf + 1)); echo "SELF-TEST FAIL: no-query case is not a FAIL line"; }

  # Facts with no number needs no query, so the empty file is fine.
  sed 's/^December 2025 signups: 1204\. Row count: 1\./Signups fell./; /^```/,/^```/d; s/^E-1 internal domains.*/Internal and demo accounts removed./; /^because it is unconfirmed\.$/d' \
    "$dir/good.md" > "$dir/good-no-numbers.md"
  assert "no numbers in Facts needs no query" "$dir/good-no-numbers.md" 0 0

  # Exclusion ids cited, and the only query filters nothing.
  sed "s/^SELECT COUNT.*/SELECT COUNT(*) FROM accounts LIMIT 10;/" \
    "$dir/good.md" > "$dir/bad-ids-no-filter.md"
  assert "ids cited, query has no WHERE" "$dir/bad-ids-no-filter.md" 0 1
  has_line "$dir/bad-ids-no-filter.md" '^FAIL  Exclusions applied cites' \
    && sp=$((sp + 1)) || { sf=$((sf + 1)); echo "SELF-TEST FAIL: ids-no-filter case is not a FAIL line"; }

  # Exclusion ids cited, and the query carries a filter in a non-SQL block.
  sed 's/^```sql$/```js/; s/^SELECT COUNT.*/db.accounts.aggregate([{ $match: { is_internal: { $ne: true } } }])/' \
    "$dir/good.md" > "$dir/good-ids-match.md"
  assert "ids cited, query has a \$match" "$dir/good-ids-match.md" 0 0

  # No ids cited, prose reason given, unfiltered query: nothing to cross-check.
  sed "s/^E-1 internal domains.*/No exclusion rules applied, because this is a raw table count used to size a backfill./; /^because it is unconfirmed\.\$/d; s/^SELECT COUNT.*/SELECT COUNT(*) FROM accounts LIMIT 10;/" \
    "$dir/good.md" > "$dir/good-no-ids.md"
  assert "no ids cited, unfiltered query" "$dir/good-no-ids.md" 0 0

  # Relative-date fix. A phrase with its own month and year is absolute.
  sed 's/^2025-12-01 00:00:00 UTC.*/2026-08-01 00:00:00 UTC to the last day of August 2026, inclusive./' \
    "$dir/good.md" > "$dir/good-last-day-of-august.md"
  assert "last day of August 2026 is not relative" "$dir/good-last-day-of-august.md" 0 0

  # The same phrase next to a real relative one must still be caught.
  sed 's/^2025-12-01 00:00:00 UTC.*/The last day of August 2026, then the last 30 days./' \
    "$dir/good.md" > "$dir/bad-last-day-plus-relative.md"
  assert "real relative date beside an absolute one" "$dir/bad-last-day-plus-relative.md" 0 1

  # A bare "last day" with no year is still relative.
  sed 's/^2025-12-01 00:00:00 UTC.*/Through the last day of the month./' \
    "$dir/good.md" > "$dir/bad-last-day-bare.md"
  assert "last day with no year is still relative" "$dir/bad-last-day-bare.md" 0 1

  # Raw email address, anywhere in the file.
  write_good "$dir/bad-email.md"
  printf '\nTop account owner: jane.doe@acme-freight.com\n' >> "$dir/bad-email.md"
  assert "raw email address" "$dir/bad-email.md" 0 1

  # The E-1 predicate is not an email address, in prose or inside a query.
  write_good "$dir/good-e1-pattern.md"
  printf "\nE-1 clause: users.email NOT ILIKE '%%@nimbusfreight.example'\n" \
    >> "$dir/good-e1-pattern.md"
  assert "E-1 style pattern is not an email" "$dir/good-e1-pattern.md" 0 0

  # Words that only look like secrets must not trip the check.
  write_good "$dir/good-lookalike.md"
  printf '\nThis task-scoped, risk-free run had no api_key set.\n' \
    >> "$dir/good-lookalike.md"
  assert "secret lookalikes are not findings" "$dir/good-lookalike.md" 0 0

  # An unreadable file exits 2 whatever the mode. This is the only hard failure left.
  assert "missing file exits 2" "$dir/does-not-exist.md" 2 2

  echo "---"
  printf 'self-test: %s passed, %s failed\n' "$sp" "$sf"
  [ "$sf" -eq 0 ] || return 1
  return 0
}

# ---------------------------------------------------------------------------
# Entry
# ---------------------------------------------------------------------------

usage() {
  echo "Usage: $0 [--strict] <artifact-path>"
  echo "       $0 --self-test"
  echo
  echo "This is a lint, not a gate. Without --strict it exits 0 even with findings."
}

ARTIFACT=""
for arg in "$@"; do
  case "$arg" in
    --self-test) self_test; exit $? ;;
    --strict)    STRICT=1 ;;
    -h|--help)   usage; exit 2 ;;
    -*)          echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
    *)           ARTIFACT="$arg" ;;
  esac
done

if [ -z "$ARTIFACT" ]; then
  usage >&2
  exit 2
fi
if [ ! -f "$ARTIFACT" ] || [ ! -r "$ARTIFACT" ]; then
  echo "Cannot read file: $ARTIFACT" >&2
  exit 2
fi

echo "Checking $ARTIFACT"
echo "---"
check_artifact "$ARTIFACT"
echo "---"
printf '%s passed, %s finding(s), %s warnings\n' "$pass_count" "$fail_count" "$warn_count"
if [ "$fail_count" -gt 0 ]; then
  if [ "$STRICT" -eq 1 ]; then
    echo "--strict: exiting 1 on the findings above."
    exit 1
  fi
  echo "Advisory run. Findings above are yours to judge, so exiting 0. Use --strict in CI."
fi
exit 0
