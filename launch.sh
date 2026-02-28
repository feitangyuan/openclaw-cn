#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL_INSTALL_SH="$SCRIPT_DIR/install.sh"
SCRIPT_URL="https://raw.githubusercontent.com/feitangyuan/openclaw-cn/main/install.sh"

if [ -f "$LOCAL_INSTALL_SH" ]; then
  bash "$LOCAL_INSTALL_SH"
  exit 0
fi

TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/openclaw-install.XXXXXX.sh")"
trap 'rm -f "$TMP_FILE"' EXIT
curl -fsSL "$SCRIPT_URL" -o "$TMP_FILE"
bash "$TMP_FILE"
