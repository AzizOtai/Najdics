#!/usr/bin/env bash
# Pull bulk data DOWN from Drive onto this machine (first setup on a new box).
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
: "${NAJDICS_DATA_ROOT:?set NAJDICS_DATA_ROOT in .env}"

REMOTE="gdrive:NajdiCS/00-audio-archive"

echo "==> $REMOTE  ->  $NAJDICS_DATA_ROOT"
rclone copy "$REMOTE" "$NAJDICS_DATA_ROOT" --checksum --progress --transfers 4
echo "==> done"
