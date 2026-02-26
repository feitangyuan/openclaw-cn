#!/usr/bin/env bash
set -euo pipefail

# Print a section title.
section() {
  printf '\n==> %s\n' "$1"
}

# Read input without echoing sensitive content.
read_secret() {
  local prompt="$1"
  local value
  read -r -s -p "$prompt" value
  echo
  printf '%s' "$value"
}

section "Checking Node.js"
if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is required (v22+). Install from https://nodejs.org and retry."
  exit 1
fi

NODE_MAJOR="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
if [ "${NODE_MAJOR}" -lt 22 ]; then
  echo "Node.js v22+ is required. Current: $(node -v)"
  exit 1
fi

section "Installing OpenClaw"
if ! command -v openclaw >/dev/null 2>&1; then
  curl -fsSL https://openclaw.ai/install.sh | bash
fi

if ! command -v openclaw >/dev/null 2>&1; then
  echo "OpenClaw installation failed."
  exit 1
fi

section "Collecting config"
echo "Choose provider:"
echo "1) Kimi (recommended)"
echo "2) MiniMax"
read -r -p "Provider [1/2, default 1]: " provider_choice
provider_choice="${provider_choice:-1}"

provider="kimi"
model="kimi-k2.5"
if [ "$provider_choice" = "2" ]; then
  provider="minimax"
  model="abab6.5s-chat"
fi

api_key="$(read_secret "${provider^} API Key: ")"
feishu_app_id="$(read -r -p "Feishu App ID (cli_...): " v; printf '%s' "$v")"
feishu_app_secret="$(read_secret "Feishu App Secret: ")"

if [ -z "$api_key" ] || [ -z "$feishu_app_id" ] || [ -z "$feishu_app_secret" ]; then
  echo "All values are required."
  exit 1
fi

section "Writing ~/.openclaw/openclaw.json"
mkdir -p "$HOME/.openclaw"
CONFIG_PATH="$HOME/.openclaw/openclaw.json"
if [ ! -f "$CONFIG_PATH" ]; then
  echo '{}' > "$CONFIG_PATH"
fi

CONFIG_PATH="$CONFIG_PATH" \
PROVIDER="$provider" \
MODEL="$model" \
API_KEY="$api_key" \
FEISHU_APP_ID="$feishu_app_id" \
FEISHU_APP_SECRET="$feishu_app_secret" \
node <<'NODE'
const fs = require('fs');

const configPath = process.env.CONFIG_PATH;
const provider = process.env.PROVIDER;
const model = process.env.MODEL;
const apiKey = process.env.API_KEY;
const appId = process.env.FEISHU_APP_ID;
const appSecret = process.env.FEISHU_APP_SECRET;

let cfg = {};
try {
  cfg = JSON.parse(fs.readFileSync(configPath, 'utf8'));
} catch {
  cfg = {};
}

cfg.providers = cfg.providers || {};
cfg.providers.kimi = cfg.providers.kimi || {};
cfg.providers.minimax = cfg.providers.minimax || {};
cfg.providers.kimi.model = cfg.providers.kimi.model || 'kimi-k2.5';
cfg.providers.minimax.model = cfg.providers.minimax.model || 'abab6.5s-chat';

if (provider === 'kimi') {
  cfg.providers.kimi.api_key = apiKey;
} else {
  cfg.providers.minimax.api_key = apiKey;
}

cfg.default_provider = provider;
cfg.default_model = model;

cfg.feishu = cfg.feishu || {};
cfg.feishu.app_id = appId;
cfg.feishu.app_secret = appSecret;

fs.writeFileSync(configPath, JSON.stringify(cfg, null, 2) + '\n');
NODE

section "Starting Gateway"
openclaw doctor || true
openclaw gateway stop >/dev/null 2>&1 || true
openclaw gateway start

section "Done"
echo "Installed and configured successfully."
echo "Use: openclaw models list"
