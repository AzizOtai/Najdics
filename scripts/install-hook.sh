#!/usr/bin/env bash
# Wire preflight.sh into git so it runs automatically on every commit.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .git/hooks
cat > .git/hooks/pre-commit << 'HOOK'
#!/usr/bin/env bash
exec ./scripts/preflight.sh
HOOK
chmod +x .git/hooks/pre-commit
echo "==> pre-commit hook installed"
echo "    bypass in an emergency with: git commit --no-verify"
