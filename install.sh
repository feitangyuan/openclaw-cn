#!/usr/bin/env bash
set -euo pipefail

# Print a section title.
section() {
  printf '\n==> %s\n' "$1"
}

read_text() {
  local prompt="$1"
  local value=""
  read -r -p "$prompt" value </dev/tty
  printf '%s' "$value"
}

read_required_text() {
  local prompt="$1"
  local value=""
  while true; do
    value="$(read_text "$prompt")"
    if [ -n "$value" ]; then
      printf '%s' "$value"
      return
    fi
    echo "This field is required. Please try again." >&2
  done
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
echo "We need 3 values: API Key, Feishu App ID, Feishu App Secret."
echo "Tip: all inputs are visible on screen. Type and press Enter."

provider="${OPENCLAW_PROVIDER:-kimi}"
provider="$(printf '%s' "$provider" | tr -d '[:space:]')"
provider="$(printf '%s' "$provider" | tr '[:upper:]' '[:lower:]')"
case "$provider" in
  "1"|"k")
    provider="kimi"
    ;;
  "2"|"m")
    provider="minimax"
    ;;
esac

case "$provider" in
  kimi)
    model_ref="moonshot/kimi-k2.5"
    auth_choice="moonshot-api-key"
    api_key_label="Kimi API Key"
    ;;
  minimax)
    model_ref="minimax/MiniMax-M2.5"
    auth_choice="minimax-api"
    api_key_label="MiniMax API Key"
    ;;
  *)
    echo "OPENCLAW_PROVIDER value '$provider' is invalid. Using default provider: kimi."
    provider="kimi"
    model_ref="moonshot/kimi-k2.5"
    auth_choice="moonshot-api-key"
    api_key_label="Kimi API Key"
    ;;
esac

echo "Provider: $provider"
api_key="$(read_required_text "$api_key_label: ")"
feishu_app_id="$(read_required_text "Feishu App ID (starts with cli_): ")"
feishu_app_secret="$(read_required_text "Feishu App Secret: ")"

if [ -z "$api_key" ] || [ -z "$feishu_app_id" ] || [ -z "$feishu_app_secret" ]; then
  echo "All values are required."
  exit 1
fi

section "Configuring OpenClaw"
openclaw doctor --fix >/dev/null 2>&1 || true
if [ "$provider" = "minimax" ]; then
  openclaw onboard --non-interactive --accept-risk --mode local \
    --auth-choice "$auth_choice" --minimax-api-key "$api_key" \
    --skip-channels --skip-daemon --skip-skills --skip-ui --skip-health \
    --gateway-bind loopback --gateway-port 18789
else
  openclaw onboard --non-interactive --accept-risk --mode local \
    --auth-choice "$auth_choice" --moonshot-api-key "$api_key" \
    --skip-channels --skip-daemon --skip-skills --skip-ui --skip-health \
    --gateway-bind loopback --gateway-port 18789
fi

if ! openclaw plugins enable feishu >/dev/null 2>&1; then
  openclaw plugins install @openclaw/feishu
  openclaw plugins enable feishu >/dev/null 2>&1
fi

openclaw config set channels.feishu.enabled true
openclaw config set channels.feishu.accounts.main.appId "$feishu_app_id"
openclaw config set channels.feishu.accounts.main.appSecret "$feishu_app_secret"
feishu_dm_policy="${OPENCLAW_FEISHU_DM_POLICY:-open}"
openclaw config set channels.feishu.dmPolicy "$feishu_dm_policy"
if [ "$feishu_dm_policy" = "open" ]; then
  openclaw config set channels.feishu.allowFrom '["*"]' --strict-json
fi

section "Starting Gateway"
openclaw gateway install >/dev/null 2>&1 || true
openclaw gateway start >/dev/null 2>&1 || true
if ! openclaw health >/dev/null 2>&1; then
  nohup openclaw gateway run >/tmp/openclaw_gateway.log 2>&1 &
  sleep 2
fi

section "Done"
echo "Installed and configured successfully."
echo "Provider: $provider, model: $model_ref"
echo "Use: openclaw models list"
