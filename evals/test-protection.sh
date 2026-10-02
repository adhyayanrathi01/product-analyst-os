#!/usr/bin/env bash
# Self-check for the portable protection layer: setup.sh --protect / --unprotect,
# .githooks/pre-commit, and the .gitignore that keeps the user's workspace out of
# git.
#
# Protection is chmod plus a commit hook, so it works on Claude Code, Codex and
# any other harness. A protection layer nobody tests is one that silently stopped
# protecting.
#
# Everything runs inside a temp directory built from copies. This script never
# chmods the real repo, never runs git in it, and never leaves it in a locked or
# half-locked state.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
REPO="$PWD"

pass=0
fail=0

check() { # name, expected, got
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $1 (expected $2, got $3)"
  fi
}

# chmod does not stop root, so as root every one of these would pass for the
# wrong reason. Refuse rather than report a lie.
if [ "$(id -u)" = "0" ]; then
  echo "Running as root. chmod does not restrict root, so these tests would pass"
  echo "without proving anything. Run as a normal user."
  exit 2
fi

SANDBOX="$(mktemp -d)"
trap 'chmod -R u+w "$SANDBOX" >/dev/null 2>&1; rm -rf "$SANDBOX"' EXIT

# ---------------------------------------------------------------------------
# A miniature repo with the same shape setup.sh looks for.
# ---------------------------------------------------------------------------
S="$SANDBOX/repo"
mkdir -p "$S/.claude/hooks" "$S/.githooks" "$S/knowledge-base" \
         "$S/skills/demo/do-thing" "$S/evals"
cp -p "$REPO/setup.sh" "$S/setup.sh"
cp -p "$REPO/.githooks/pre-commit" "$S/.githooks/pre-commit"
printf 'charter\n'                    > "$S/CHARTER.md"
printf 'agents\n'                     > "$S/AGENTS.md"
printf 'claude\n'                     > "$S/CLAUDE.md"
printf '{}\n'                         > "$S/.claude/settings.json"
printf '#!/usr/bin/env python3\n'     > "$S/.claude/hooks/guard.py"
printf 'skill\n'                      > "$S/skills/demo/do-thing/SKILL.md"
printf '#!/usr/bin/env bash\ntrue\n'  > "$S/evals/test-demo.sh"
printf '# entities\n\nTODO grain\n'   > "$S/knowledge-base/entities.md"
printf 'company\n'                    > "$S/knowledge-base/company.md"
chmod +x "$S/.claude/hooks/guard.py" "$S/evals/test-demo.sh"

writable() { if [ -w "$1" ]; then echo yes; else echo no; fi; }
executable() { if [ -x "$1" ]; then echo yes; else echo no; fi; }

# ---------------------------------------------------------------------------
# Protect, with an unfilled knowledge base.
# ---------------------------------------------------------------------------
out="$(bash "$S/setup.sh" --protect 2>&1)"

check "protect locks CHARTER.md"        no  "$(writable "$S/CHARTER.md")"
check "protect locks a SKILL.md"        no  "$(writable "$S/skills/demo/do-thing/SKILL.md")"
check "protect locks guard.py"          no  "$(writable "$S/.claude/hooks/guard.py")"
check "protect locks an evals script"   no  "$(writable "$S/evals/test-demo.sh")"
check "protect locks setup.sh"          no  "$(writable "$S/setup.sh")"

# The write has to actually fail. A read-only bit that the shell ignores is not
# protection.
# The subshell is so the shell's own redirection error goes to /dev/null too.
if ( printf 'appended\n' >> "$S/CHARTER.md" ) 2>/dev/null; then
  got=wrote
else
  got=refused
fi
check "a write to a locked file fails"  refused "$got"

# Execute bits survive the lock.
check "setup.sh stays executable"       yes "$(executable "$S/setup.sh")"
check "guard.py stays executable"       yes "$(executable "$S/.claude/hooks/guard.py")"
check "evals script stays executable"   yes "$(executable "$S/evals/test-demo.sh")"

# An unfilled knowledge base is left writable, with a warning.
check "unfilled kb stays writable"      yes "$(writable "$S/knowledge-base/entities.md")"
case "$out" in
  *"NOT locked"*) got=warned ;;
  *)              got=silent ;;
esac
check "unfilled kb is warned about"     warned "$got"

# ---------------------------------------------------------------------------
# --force locks it anyway.
# ---------------------------------------------------------------------------
bash "$S/setup.sh" --protect --force >/dev/null 2>&1
check "--force locks unfilled kb"       no  "$(writable "$S/knowledge-base/entities.md")"

# ---------------------------------------------------------------------------
# Status reports both states.
# ---------------------------------------------------------------------------
bash "$S/setup.sh" --unprotect >/dev/null 2>&1
chmod a-w "$S/CHARTER.md"
out="$(bash "$S/setup.sh" --protect --status 2>&1)"
case "$out" in *"locked   CHARTER.md"*) got=yes ;; *) got=no ;; esac
check "status names a locked file"      yes "$got"
case "$out" in *"writable AGENTS.md"*) got=yes ;; *) got=no ;; esac
check "status names a writable file"    yes "$got"

# ---------------------------------------------------------------------------
# Unprotect.
# ---------------------------------------------------------------------------
bash "$S/setup.sh" --protect --force >/dev/null 2>&1
bash "$S/setup.sh" --unprotect >/dev/null 2>&1

check "unprotect frees CHARTER.md"      yes "$(writable "$S/CHARTER.md")"
check "unprotect frees the kb"          yes "$(writable "$S/knowledge-base/entities.md")"
check "unprotect frees a SKILL.md"      yes "$(writable "$S/skills/demo/do-thing/SKILL.md")"
if ( printf 'appended\n' >> "$S/CHARTER.md" ) 2>/dev/null; then got=wrote; else got=refused; fi
check "a write after unprotect works"   wrote "$got"
check "setup.sh still executable"       yes "$(executable "$S/setup.sh")"
check "guard.py still executable"       yes "$(executable "$S/.claude/hooks/guard.py")"

# ---------------------------------------------------------------------------
# A fresh clone has no entities.md until setup copies the template. Missing is
# unfinished, so --protect must not lock the kb and must say so.
# ---------------------------------------------------------------------------
rm -f "$S/knowledge-base/entities.md"
out="$(bash "$S/setup.sh" --protect 2>&1)"
case "$out" in
  *"NOT locked"*) got=warned ;;
  *)              got=silent ;;
esac
check "missing entities.md is unfinished" warned "$got"
check "missing entities.md leaves kb open" yes "$(writable "$S/knowledge-base/company.md")"
bash "$S/setup.sh" --unprotect >/dev/null 2>&1

# ---------------------------------------------------------------------------
# The commit hook, in its own throwaway git repo.
# ---------------------------------------------------------------------------
if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git not found, the pre-commit hook cases did not run."
else
  G="$SANDBOX/gitrepo"
  mkdir -p "$G/.githooks" "$G/knowledge-base" "$G/reports"
  cp -p "$REPO/.githooks/pre-commit" "$G/.githooks/pre-commit"
  chmod +x "$G/.githooks/pre-commit"
  git init -q "$G"
  git -C "$G" config user.email "test@example.invalid"
  git -C "$G" config user.name "protection test"
  git -C "$G" config commit.gpgsign false
  git -C "$G" config core.hooksPath .githooks

  printf 'definitions\n' > "$G/knowledge-base/entities.md"
  printf 'a report\n'    > "$G/reports/r.md"
  git -C "$G" add -A >/dev/null 2>&1

  out="$(git -C "$G" commit -m "touches the kb" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then got=allowed; else got=refused; fi
  check "hook refuses a protected path"  refused "$got"
  case "$out" in
    *"knowledge-base/entities.md"*) got=named ;;
    *)                              got=unnamed ;;
  esac
  check "hook names the touched file"    named "$got"

  out="$(PAOS_ALLOW_PROTECTED=1 git -C "$G" commit -m "deliberate kb edit" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then got=allowed; else got=refused; fi
  check "PAOS_ALLOW_PROTECTED=1 allows"  allowed "$got"

  # An unprotected path commits with nothing set, on a repo that now has a HEAD.
  printf 'a second report\n' >> "$G/reports/r.md"
  git -C "$G" add -A >/dev/null 2>&1
  out="$(git -C "$G" commit -m "report only" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then got=allowed; else got=refused; fi
  check "hook allows an unprotected path" allowed "$got"

  # The blank templates are tracked, and still under knowledge-base/.
  mkdir -p "$G/knowledge-base/_template"
  printf 'blank\n' > "$G/knowledge-base/_template/entities.md"
  git -C "$G" add -A >/dev/null 2>&1
  out="$(git -C "$G" commit -m "template edit" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then got=allowed; else got=refused; fi
  check "hook refuses a kb template edit"  refused "$got"

  # -------------------------------------------------------------------------
  # The workspace stays out of git. Uses the repo's real .gitignore and
  # setup.sh, so this proves the shipped files, not a copy of the rules.
  # -------------------------------------------------------------------------
  L="$SANDBOX/workspace"
  mkdir -p "$L/knowledge-base/_template" "$L/reports/_template" \
           "$L/schema/_template" "$L/_template"
  cp -p "$REPO/.gitignore" "$L/.gitignore"
  cp -p "$REPO/setup.sh" "$L/setup.sh"
  for f in entities company personas metrics glossary; do
    printf '# %s\n\nTODO\n' "$f" > "$L/knowledge-base/_template/$f.md"
  done
  printf 'readme\n'  > "$L/knowledge-base/README.md"
  printf 'readme\n'  > "$L/reports/README.md"
  printf 'shape\n'   > "$L/reports/_template/report.md"
  printf 'readme\n'  > "$L/schema/README.md"
  printf 'format\n'  > "$L/schema/_template/schema.md"
  printf '# Current task\n' > "$L/_template/task.md"
  printf '# Log\n'          > "$L/_template/log.md"
  git init -q "$L"
  git -C "$L" config user.email "test@example.invalid"
  git -C "$L" config user.name "protection test"
  git -C "$L" config commit.gpgsign false
  git -C "$L" add -A >/dev/null 2>&1
  git -C "$L" commit -qm "template" >/dev/null 2>&1

  n="$(git -C "$L" ls-files | grep -c '_template/' || true)"
  check "all 9 templates are tracked"       9 "$n"

  # setup copies every missing workspace file from its template.
  bash "$L/setup.sh" --check >/dev/null 2>&1
  for f in knowledge-base/entities.md knowledge-base/glossary.md task.md log.md; do
    if [ -f "$L/$f" ]; then got=created; else got=absent; fi
    check "setup creates $f"            created "$got"
  done

  # A filled file at every workspace path. None may reach git.
  printf 'grain: account\nexclude: @internal.example\n' > "$L/knowledge-base/entities.md"
  for f in company personas metrics glossary; do
    printf 'filled\n' > "$L/knowledge-base/$f.md"
  done
  printf 'filled\n' > "$L/knowledge-base/entities.md.bak"
  mkdir -p "$L/schema/warehouse"
  printf '| orders | id | int |\n' > "$L/schema/warehouse/schema.md"
  printf 'abc\n'                   > "$L/schema/warehouse/schema.sha256"
  printf '412 active accounts\n'   > "$L/reports/2026-10-03-active-accounts.md"
  printf 'draft\n'                 > "$L/reports/2026-10-03-entities.md.proposed"
  printf 'state\n'                 > "$L/task.md"
  printf 'history\n'               > "$L/log.md"
  out="$(git -C "$L" status --porcelain --untracked-files=all)"
  check "no workspace file shows in git status" "" "$out"

  # setup never overwrites a filled file.
  bash "$L/setup.sh" --check >/dev/null 2>&1
  case "$(cat "$L/knowledge-base/entities.md")" in
    *"@internal.example"*) got=kept ;;
    *)                     got=overwritten ;;
  esac
  check "setup keeps a filled entities.md"  kept "$got"

  # A force-added workspace file is caught by --check, and named.
  git -C "$L" add -f knowledge-base/entities.md >/dev/null 2>&1
  out="$(bash "$L/setup.sh" --check 2>&1)"
  case "$out" in
    *"git still tracks"*"knowledge-base/entities.md"*) got=caught ;;
    *)                                                 got=missed ;;
  esac
  check "--check names a tracked workspace file" caught "$got"
  git -C "$L" rm -q --cached knowledge-base/entities.md >/dev/null 2>&1
  out="$(bash "$L/setup.sh" --check 2>&1)"
  case "$out" in
    *"no gitignored file is tracked"*) got=clean ;;
    *)                                 got=flagged ;;
  esac
  check "--check is clean once untracked"   clean "$got"
  if [ -f "$L/knowledge-base/entities.md" ]; then got=kept; else got=lost; fi
  check "untracking keeps the file on disk" kept "$got"
fi

echo "---"
echo "protection: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
