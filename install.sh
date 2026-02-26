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

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

run_privileged() {
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    "$@"
  elif command_exists sudo; then
    sudo "$@"
  else
    echo "Need root privileges but sudo is not available."
    exit 1
  fi
}

ensure_node22() {
  if command_exists node; then
    local current_major
    current_major="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
    if [ "${current_major}" -ge 22 ]; then
      return
    fi
  fi

  section "Installing Node.js v22+"
  local os
  os="$(uname -s)"

  if [ "$os" = "Darwin" ]; then
    if ! command_exists brew; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      elif [ -x /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
      fi
    fi
    brew install node@22 || brew upgrade node@22 || true
    if [ -x "$(brew --prefix node@22)/bin/node" ]; then
      export PATH="$(brew --prefix node@22)/bin:$PATH"
    fi
  elif command_exists apt-get; then
    run_privileged apt-get update -y
    run_privileged apt-get install -y ca-certificates curl gnupg
    curl -fsSL https://deb.nodesource.com/setup_22.x | run_privileged bash -
    run_privileged apt-get install -y nodejs
  elif command_exists dnf; then
    curl -fsSL https://rpm.nodesource.com/setup_22.x | run_privileged bash -
    run_privileged dnf install -y nodejs
  elif command_exists yum; then
    curl -fsSL https://rpm.nodesource.com/setup_22.x | run_privileged bash -
    run_privileged yum install -y nodejs
  else
    echo "Unable to auto-install Node.js. Please install Node.js v22+ manually from https://nodejs.org"
    exit 1
  fi

  if ! command_exists node; then
    echo "Node.js installation failed."
    exit 1
  fi
  local installed_major
  installed_major="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
  if [ "${installed_major}" -lt 22 ]; then
    echo "Node.js v22+ is required. Current: $(node -v)"
    exit 1
  fi
}

ensure_openclaw() {
  if command_exists openclaw; then
    return
  fi

  section "Installing OpenClaw"
  if command_exists npm; then
    npm config set progress false >/dev/null 2>&1 || true
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
      npm install -g openclaw --registry https://registry.npmmirror.com --loglevel=error || true
    elif [ -w /opt/homebrew/lib/node_modules ] || [ -w /usr/local/lib/node_modules ]; then
      npm install -g openclaw --registry https://registry.npmmirror.com --loglevel=error || true
    elif command_exists sudo; then
      run_privileged npm install -g openclaw --registry https://registry.npmmirror.com --loglevel=error || true
    else
      npm install -g openclaw --registry https://registry.npmmirror.com --loglevel=error || true
    fi
  fi

  if ! command_exists openclaw; then
    curl -fsSL https://openclaw.ai/install.sh | bash
  fi

  if ! command_exists openclaw; then
    echo "OpenClaw installation failed."
    exit 1
  fi
}

section "Preparing environment"
ensure_node22
ensure_openclaw

section "Collecting config"
provider="${OPENCLAW_PROVIDER:-kimi}"
case "$provider" in
  kimi)
    model="kimi-k2.5"
    ;;
  minimax)
    model="abab6.5s-chat"
    ;;
  *)
    echo "OPENCLAW_PROVIDER must be 'kimi' or 'minimax'."
    exit 1
    ;;
esac

api_key="$(read_secret "Model API Key: ")"
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
echo "Provider: $provider, model: $model"
echo "Use: openclaw models list"
