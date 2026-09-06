#!/usr/bin/env bash
# Bootstrap the NajdiCS workspace. Runs identically on macOS and WSL2/Ubuntu.
# Usage:  ./scripts/bootstrap.sh mac    |    ./scripts/bootstrap.sh gpu
set -euo pipefail

ROLE="${1:-}"
if [[ "$ROLE" != "mac" && "$ROLE" != "gpu" ]]; then
  echo "usage: $0 [mac|gpu]" >&2; exit 1
fi

REPO="$HOME/najdics"
DATA="$HOME/najdics-data"

echo "==> role: $ROLE"

# --- guard: repo must not live inside a cloud-synced folder ---
case "$REPO" in
  *Google*Drive*|*Dropbox*|*OneDrive*|*iCloud*)
    echo "FATAL: repo is inside a cloud-synced folder. Move it." >&2; exit 1 ;;
esac

# --- bulk data tree, outside the repo ---
echo "==> creating data tree at $DATA"
mkdir -p "$DATA/tierA/raw" "$DATA/tierA/work"
mkdir -p "$DATA/tierB/raw" "$DATA/tierB/work"
mkdir -p "$DATA/drafts" "$DATA/checkpoints"

# --- symlink data into the repo (gitignored) ---
if [[ ! -e "$REPO/data" ]]; then
  ln -s "$DATA" "$REPO/data"
  echo "==> linked $REPO/data -> $DATA"
fi

# --- python env ---
cd "$REPO"
if [[ ! -d .venv ]]; then
  python3 -m venv .venv
  echo "==> created .venv"
fi
source .venv/bin/activate
pip install --quiet --upgrade pip

pip install --quiet -r requirements.txt
if [[ "$ROLE" == "mac" ]]; then
  pip install --quiet -r requirements-mac.txt
else
  pip install --quiet -r requirements-gpu.txt
fi
echo "==> python deps installed"

# --- .env ---
if [[ ! -f .env ]]; then
  cp .env.example .env
  python3 - "$DATA" "$ROLE" <<'PY'
import sys, pathlib
data, role = sys.argv[1], sys.argv[2]
p = pathlib.Path(".env"); t = p.read_text()
t = t.replace("NAJDICS_DATA_ROOT=", f"NAJDICS_DATA_ROOT={data}")
t = t.replace("MACHINE_ROLE=", f"MACHINE_ROLE={role}")
p.write_text(t)
PY
  echo "==> wrote .env (fill in API keys manually)"
fi

# --- verification ---
echo
echo "==> verification"
python3 -c "import sys; print('  python  ', sys.version.split()[0])"
if [[ "$ROLE" == "gpu" ]]; then
  python3 -c "import torch; print('  cuda    ', torch.cuda.is_available())" 2>/dev/null \
    || echo "  cuda     NOT AVAILABLE - check Windows NVIDIA driver; do NOT install a Linux driver inside WSL"
else
  python3 -c "import mlx.core" 2>/dev/null && echo "  mlx      ok" || echo "  mlx      not installed"
fi
command -v rclone >/dev/null && echo "  rclone   ok" || echo "  rclone   MISSING - brew install rclone / sudo apt install rclone"
command -v git >/dev/null && echo "  git      ok"
echo
echo "Done. Next: fill API keys in .env, then run 'rclone config' if not set up."
