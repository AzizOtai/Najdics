#!/usr/bin/env bash
# Mirror local bulk data UP to Google Drive. Never deletes anything local.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
: "${NAJDICS_DATA_ROOT:?set NAJDICS_DATA_ROOT in .env}"

REMOTE="gdrive:NajdiCS/00-audio-archive"

echo "==> $NAJDICS_DATA_ROOT  ->  $REMOTE"
# copy (not sync): never deletes on the remote, so a local mistake can't
# destroy the archive. --checksum avoids re-uploads from mtime drift between
# machines. Checkpoints excluded: large and reproducible.
rclone copy "$NAJDICS_DATA_ROOT" "$REMOTE" \
  --checksum \
  --exclude "checkpoints/**" \
  --exclude ".DS_Store" \
  --progress \
  --transfers 4
echo "==> done"
