#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ALLOWED_DISTRICT="TEST-XX"
ALLOWED_SESSION="00000000-0000-0000-0000-000000000000"

VIOLATIONS=0

# Collect files from git index + untracked non-ignored files (or fallback to find before git init)
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  FILES=()
  while IFS= read -r -d '' f; do
    [[ -f "$f" ]] && FILES+=("$f")
  done < <(git ls-files -z --cached --others --exclude-standard)
else
  FILES=()
  while IFS= read -r -d '' f; do
    FILES+=("${f#./}")
  done < <(find . -type f -not -path './.git/*' -not -path './.build/*' -not -path './.swiftpm/*' -not -name '.DS_Store' -print0)
fi

for file in "${FILES[@]}"; do
  # 1. Forbid committed local persistence state or raw HTML dumps
  case "$file" in
    *state.json|*saved-link.json|*GetReport*.html|*GetReport*.cfm*|*.env|*.pem|*.key)
      echo "[FAIL] Forbidden state or secret file tracked: $file" >&2
      VIOLATIONS=$((VIOLATIONS + 1))
      ;;
  esac

  # 2. Check for non-anonymized District query parameters
  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    val="${match#*=}"
    if [[ "$val" != "$ALLOWED_DISTRICT" ]]; then
      echo "[FAIL] $file contains non-anonymized District parameter: $val" >&2
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
  done < <(grep -Eio 'District[=][A-Za-z0-9-]+' "$file" 2>/dev/null || true)

  # 3. Check for non-anonymized SessionID hex tokens
  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    val="${match#*=}"
    if [[ "$val" != "$ALLOWED_SESSION" ]]; then
      echo "[FAIL] $file contains non-anonymized SessionID token" >&2
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
  done < <(grep -Eio 'SessionID[=][A-Fa-f0-9-]{8,}' "$file" 2>/dev/null || true)

  # 4. Check for live client subdomains (*.client.factsmgt.com) other than synthetic fixtures
  while IFS= read -r host; do
    [[ -z "$host" ]] && continue
    lower_host="$(echo "$host" | tr '[:upper:]' '[:lower:]')"
    if [[ "$lower_host" != "test-xx.client.factsmgt.com" && "$lower_host" != "example.client.factsmgt.com" ]]; then
      echo "[FAIL] $file contains non-fixture FACTS client host: $host" >&2
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
  done < <(grep -Eio '[A-Za-z0-9-]+[.][Cc]lient[.]factsmgt[.]com' "$file" 2>/dev/null || true)

  # 5. Check for standard credential leaks (GitHub tokens, AWS keys, private keys)
  if grep -Eq '(BEGIN [A-Z ]*PRIVATE KEY|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16})' "$file" 2>/dev/null; then
    echo "[FAIL] $file contains a credential or private key pattern" >&2
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
done

if [[ "$VIOLATIONS" -gt 0 ]]; then
  echo "[ERROR] Secret audit failed with $VIOLATIONS violation(s)." >&2
  exit 1
fi

echo "[OK] Secret audit passed (${#FILES[@]} files scanned, zero live tokens or PII)."
