#!/usr/bin/env bash
# Run before every commit. Catches the mistakes that are painful to undo.
set -uo pipefail
cd "$(dirname "$0")/.."
FAIL=0

echo "==> preflight"

if git diff --cached --name-only | grep -qiE '\.(wav|mp3|m4a|flac)$'; then
  echo "  FAIL: audio staged for commit"; FAIL=1
else echo "  ok  : no audio staged"; fi

if git diff --cached --name-only | grep -qx '.env'; then
  echo "  FAIL: .env staged"; FAIL=1
else echo "  ok  : .env not staged"; fi

if git diff --cached | grep -qE '(sk-[A-Za-z0-9_-]{20,}|AIza[A-Za-z0-9_-]{20,})'; then
  echo "  FAIL: possible API key in staged diff"; FAIL=1
else echo "  ok  : no key pattern in diff"; fi

if git diff --cached --name-only | grep -qiE 'consent|participant.*name|_pii'; then
  echo "  FAIL: possible PII filename staged"; FAIL=1
else echo "  ok  : no PII filenames staged"; fi

case "$PWD" in
  *Google*Drive*|*Dropbox*|*OneDrive*|*iCloud*)
    echo "  FAIL: repo inside a cloud-synced folder"; FAIL=1 ;;
  *) echo "  ok  : repo outside synced folders" ;;
esac

if compgen -G "corpus/transcripts/*.jsonl" >/dev/null 2>&1; then
  if python3 tools/validate.py corpus/transcripts/*.jsonl >/dev/null 2>&1; then
    echo "  ok  : transcripts validate"
  else
    echo "  WARN: validate.py reported issues (not blocking)"
  fi
fi

if [[ $FAIL -eq 0 ]]; then echo "==> pass"; else echo "==> FAILED - fix before committing"; exit 1; fi
