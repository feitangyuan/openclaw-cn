#!/usr/bin/env bash
set -euo pipefail

# Print a section title.
section() {
  printf '\n==> %s\n' "$1"
}

inject_runtime_safety_policy() {
  section "Applying runtime safety policy"

  local workspace_dir
  workspace_dir="$(openclaw config get agents.defaults.workspace 2>/dev/null || true)"
  workspace_dir="$(printf '%s' "$workspace_dir" | tr -d '\r')"
  if [ -z "$workspace_dir" ]; then
    workspace_dir="$HOME/.openclaw/workspace"
  fi
  mkdir -p "$workspace_dir"

  local agents_file="$workspace_dir/AGENTS.md"
  local tmp_file="$agents_file.tmp.$$"
  local start_marker="<!-- openclaw-cn:safety:start -->"
  local end_marker="<!-- openclaw-cn:safety:end -->"
  local policy_block

  policy_block="$(cat <<'EOF'
<!-- openclaw-cn:safety:start -->
## OpenClaw-CN Safety Policy

Follow these rules in Feishu conversations:

- Do not ask for confirmation for normal chat, Q&A, summarization, or read-only checks.
- Ask for explicit user confirmation before high-risk or permission-changing actions.

High-risk actions that require confirmation:

- Changing access controls (`dmPolicy`, `allowFrom`, `groupAllowFrom`, open access).
- Enabling/disabling plugins or skills, or installing dependencies.
- Setting/rotating external API keys or third-party credentials.
- Granting/requesting new Feishu app scopes/permissions.
- Bulk send/delete/share operations, or irreversible operations.

Admin-only actions:

- Any Feishu scope authorization change must be completed by an admin.
- If admin action is needed, explain what is missing and provide exact steps.

When confirmation is required:

- Explain why, show exact command/action, then wait for clear "同意/确认".
- Without confirmation, provide guidance only and do not execute.
<!-- openclaw-cn:safety:end -->
EOF
)"

  if [ -f "$agents_file" ]; then
    awk -v s="$start_marker" -v e="$end_marker" '
      BEGIN { skip = 0 }
      $0 == s { skip = 1; next }
      $0 == e { skip = 0; next }
      skip == 0 { print }
    ' "$agents_file" >"$tmp_file"
  else
    printf '# AGENTS.md\n' >"$tmp_file"
  fi

  printf '\n%s\n' "$policy_block" >>"$tmp_file"
  mv "$tmp_file" "$agents_file"
  echo "Runtime safety policy synced: $agents_file"
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

normalize_provider() {
  local value="${1:-kimi-code}"
  value="$(printf '%s' "$value" | tr -d '[:space:]')"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    ""|"1"|"k"|"kimi"|"kimi-code"|"kimicode")
      printf 'kimi-code'
      ;;
    "2"|"m"|"minimax")
      printf 'minimax'
      ;;
    "3"|"moonshot"|"moon")
      printf 'moonshot'
      ;;
    *)
      printf '%s' "$value"
      ;;
  esac
}

apply_provider_settings() {
  local requested="${1:-kimi-code}"
  provider="$(normalize_provider "$requested")"
  case "$provider" in
    kimi-code)
      model_ref="kimi-coding/k2p5"
      auth_choice="kimi-code-api-key"
      api_key_label="Kimi Code API Key"
      ;;
    moonshot)
      model_ref="moonshot/kimi-k2.5"
      auth_choice="moonshot-api-key"
      api_key_label="Moonshot API Key"
      ;;
    minimax)
      model_ref="minimax/MiniMax-M2.5"
      auth_choice="minimax-api"
      api_key_label="MiniMax API Key"
      ;;
    *)
      echo "OPENCLAW_PROVIDER value '$requested' is invalid. Using default provider: kimi-code."
      provider="kimi-code"
      model_ref="kimi-coding/k2p5"
      auth_choice="kimi-code-api-key"
      api_key_label="Kimi Code API Key"
      ;;
  esac
}

open_url() {
  local url="$1"
  local os
  os="$(uname -s)"

  if [ "$os" = "Darwin" ] && command_exists open; then
    open "$url" >/dev/null 2>&1
    return
  fi

  if command_exists cmd.exe; then
    cmd.exe /c start "" "$url" >/dev/null 2>&1
    return
  fi

  if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
    if command_exists xdg-open; then
      xdg-open "$url" >/dev/null 2>&1
      return
    fi
    if command_exists python3; then
      python3 -m webbrowser "$url" >/dev/null 2>&1
      return
    fi
  fi

  return 1
}

can_use_web_config() {
  local mode="${OPENCLAW_CONFIG_MODE:-web}"
  case "$mode" in
    tty)
      return 1
      ;;
    web|"")
      ;;
    *)
      ;;
  esac

  local os
  os="$(uname -s)"
  if [ "$os" = "Darwin" ] && command_exists open; then
    return 0
  fi
  if command_exists cmd.exe; then
    return 0
  fi
  if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
    if command_exists xdg-open || command_exists python3; then
      return 0
    fi
  fi
  return 1
}

read_json_value() {
  local file_path="$1"
  local field_name="$2"
  node -e '
    const fs = require("fs");
    const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const value = data[process.argv[2]];
    process.stdout.write(typeof value === "string" ? value : "");
  ' "$file_path" "$field_name"
}

collect_config_via_web() {
  if ! can_use_web_config; then
    return 1
  fi

  section "Collecting config"
  echo "Opening local setup page in your browser..."

  local default_provider
  default_provider="$(normalize_provider "${OPENCLAW_PROVIDER:-kimi-code}")"
  case "$default_provider" in
    kimi-code|moonshot|minimax)
      ;;
    *)
      default_provider="kimi-code"
      ;;
  esac

  local tmp_dir
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/openclaw-web.XXXXXX")"
  local server_js="$tmp_dir/server.js"
  local result_file="$tmp_dir/config.json"
  local port_file="$tmp_dir/port.txt"
  local server_pid=""

  cat >"$server_js" <<'EOF'
const fs = require("fs");
const http = require("http");

const resultFile = process.env.OPENCLAW_WEB_RESULT_FILE;
const portFile = process.env.OPENCLAW_WEB_PORT_FILE;
const allowedProviders = new Set(["kimi-code", "moonshot", "minimax"]);
const requestedProvider = String(process.env.OPENCLAW_WEB_DEFAULT_PROVIDER || "kimi-code").toLowerCase();
const defaultProvider = allowedProviders.has(requestedProvider) ? requestedProvider : "kimi-code";

function page(errorMessage) {
  const errorHtml = errorMessage
    ? `<div class="error">${escapeHtml(errorMessage)}</div>`
    : "";

  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>OpenClaw 安装配置</title>
  <style>
    :root {
      color-scheme: light;
      --bg1: #f7f3ea;
      --bg2: #f2e7d2;
      --card: rgba(255, 252, 246, 0.96);
      --text: #2d2418;
      --muted: #695744;
      --line: #d8c7ab;
      --accent: #0f766e;
      --accent-2: #134e4a;
      --error: #b42318;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: "PingFang SC", "Noto Sans SC", "Microsoft YaHei", sans-serif;
      background:
        radial-gradient(circle at top left, rgba(255,255,255,0.75), transparent 38%),
        linear-gradient(135deg, var(--bg1), var(--bg2));
      color: var(--text);
      display: grid;
      place-items: center;
      padding: 24px;
    }
    .card {
      width: min(680px, 100%);
      background: var(--card);
      border: 1px solid rgba(216, 199, 171, 0.9);
      border-radius: 20px;
      padding: 28px;
      box-shadow: 0 24px 60px rgba(45, 36, 24, 0.10);
      backdrop-filter: blur(8px);
    }
    h1 {
      margin: 0 0 10px;
      font-size: clamp(28px, 4vw, 40px);
      line-height: 1.08;
      letter-spacing: -0.02em;
    }
    p {
      margin: 0;
      color: var(--muted);
      line-height: 1.6;
    }
    .note {
      margin-top: 14px;
      padding: 12px 14px;
      border-radius: 12px;
      background: rgba(15, 118, 110, 0.08);
      color: var(--accent-2);
      font-size: 14px;
    }
    .error {
      margin-top: 14px;
      padding: 12px 14px;
      border-radius: 12px;
      background: rgba(180, 35, 24, 0.08);
      color: var(--error);
      font-size: 14px;
    }
    form {
      margin-top: 22px;
      display: grid;
      gap: 16px;
    }
    label {
      display: grid;
      gap: 8px;
      font-size: 14px;
      color: var(--text);
    }
    .field-title {
      font-weight: 600;
    }
    select,
    input {
      width: 100%;
      border: 1px solid var(--line);
      border-radius: 12px;
      padding: 14px 15px;
      font: inherit;
      color: var(--text);
      background: #fffdf8;
      outline: none;
    }
    select:focus,
    input:focus {
      border-color: var(--accent);
      box-shadow: 0 0 0 4px rgba(15, 118, 110, 0.10);
    }
    button {
      margin-top: 4px;
      border: 0;
      border-radius: 999px;
      padding: 14px 18px;
      font: inherit;
      font-weight: 700;
      color: #ffffff;
      background: linear-gradient(135deg, var(--accent), var(--accent-2));
      cursor: pointer;
    }
    .footer {
      margin-top: 14px;
      font-size: 13px;
      color: var(--muted);
    }
  </style>
</head>
<body>
  <main class="card">
    <h1>OpenClaw 一键安装</h1>
    <p>只需要填写 4 项，点一下就开始。终端会在后台继续安装，你不用再手动输入命令。</p>
    <div class="note">输入框内容默认可见，避免看不见自己输到了哪里。提交后此页面会提示“已开始安装”。</div>
    ${errorHtml}
    <form method="post" action="/submit">
      <label>
        <span class="field-title">模型厂商</span>
        <select id="provider" name="provider">
          <option value="kimi-code">Kimi Code（推荐）</option>
          <option value="moonshot">Moonshot（月之暗面）</option>
          <option value="minimax">MiniMax</option>
        </select>
      </label>
      <label>
        <span class="field-title" id="api-key-label">Kimi Code API Key</span>
        <input id="apiKey" name="apiKey" type="text" autocomplete="off" required>
      </label>
      <label>
        <span class="field-title">飞书 App ID</span>
        <input id="feishuAppId" name="feishuAppId" type="text" autocomplete="off" placeholder="cli_xxx" required>
      </label>
      <label>
        <span class="field-title">飞书 App Secret</span>
        <input id="feishuAppSecret" name="feishuAppSecret" type="text" autocomplete="off" required>
      </label>
      <button type="submit">开始安装</button>
    </form>
    <div class="footer">提交后如果浏览器保持打开是正常的，安装结果请看终端窗口。</div>
  </main>
  <script>
    const defaultProvider = ${JSON.stringify(defaultProvider)};
    const labels = {
      "kimi-code": "Kimi Code API Key",
      "moonshot": "Moonshot API Key",
      "minimax": "MiniMax API Key"
    };
    const providerEl = document.getElementById("provider");
    const labelEl = document.getElementById("api-key-label");
    providerEl.value = defaultProvider;
    function updateApiLabel() {
      labelEl.textContent = labels[providerEl.value] || "API Key";
    }
    providerEl.addEventListener("change", updateApiLabel);
    updateApiLabel();
  </script>
</body>
</html>`;
}

function escapeHtml(input) {
  return String(input)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function sendHtml(res, statusCode, html) {
  res.writeHead(statusCode, {
    "Content-Type": "text/html; charset=utf-8",
    "Cache-Control": "no-store"
  });
  res.end(html);
}

function normalizeProvider(value) {
  const normalized = String(value || "")
    .trim()
    .toLowerCase();
  if (normalized === "1" || normalized === "k" || normalized === "kimi" || normalized === "kimicode") {
    return "kimi-code";
  }
  if (normalized === "2" || normalized === "m") {
    return "minimax";
  }
  if (normalized === "3" || normalized === "moon") {
    return "moonshot";
  }
  return allowedProviders.has(normalized) ? normalized : "";
}

const server = http.createServer((req, res) => {
  if (req.method === "GET" && req.url === "/") {
    sendHtml(res, 200, page(""));
    return;
  }

  if (req.method === "POST" && req.url === "/submit") {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
      if (body.length > 32 * 1024) {
        req.destroy();
      }
    });

    req.on("end", () => {
      const form = new URLSearchParams(body);
      const provider = normalizeProvider(form.get("provider"));
      const apiKey = String(form.get("apiKey") || "").trim();
      const feishuAppId = String(form.get("feishuAppId") || "").trim();
      const feishuAppSecret = String(form.get("feishuAppSecret") || "").trim();

      if (!provider) {
        sendHtml(res, 400, page("请选择一个有效的模型厂商。"));
        return;
      }
      if (!apiKey || !feishuAppId || !feishuAppSecret) {
        sendHtml(res, 400, page("4 个字段都必须填写。"));
        return;
      }

      fs.writeFileSync(
        resultFile,
        JSON.stringify({ provider, apiKey, feishuAppId, feishuAppSecret }),
        { mode: 0o600 }
      );

      sendHtml(
        res,
        200,
        `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>OpenClaw 安装中</title>
  <style>
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      background: linear-gradient(135deg, #f7f3ea, #f2e7d2);
      color: #2d2418;
      font-family: "PingFang SC", "Noto Sans SC", "Microsoft YaHei", sans-serif;
      padding: 24px;
    }
    .panel {
      width: min(560px, 100%);
      background: rgba(255, 252, 246, 0.96);
      border: 1px solid rgba(216, 199, 171, 0.9);
      border-radius: 20px;
      padding: 28px;
      box-shadow: 0 24px 60px rgba(45, 36, 24, 0.10);
    }
    h1 { margin: 0 0 10px; font-size: 30px; }
    p { margin: 0; line-height: 1.7; color: #695744; }
  </style>
</head>
<body>
  <main class="panel">
    <h1>已开始安装</h1>
    <p>配置已经收到，终端正在继续执行安装。这个页面可以直接关掉，最终结果请看终端窗口。</p>
  </main>
</body>
</html>`
      );

      setTimeout(() => {
        server.close(() => process.exit(0));
      }, 200);
    });

    req.on("error", () => {
      sendHtml(res, 500, page("读取表单失败，请重新提交。"));
    });
    return;
  }

  sendHtml(res, 404, page("页面不存在。"));
});

server.listen(0, "127.0.0.1", () => {
  const address = server.address();
  fs.writeFileSync(portFile, String(address.port), { mode: 0o600 });
});
EOF

  OPENCLAW_WEB_RESULT_FILE="$result_file" \
  OPENCLAW_WEB_PORT_FILE="$port_file" \
  OPENCLAW_WEB_DEFAULT_PROVIDER="$default_provider" \
  node "$server_js" >/dev/null 2>&1 &
  server_pid=$!

  local waited=0
  while [ ! -s "$port_file" ]; do
    if ! kill -0 "$server_pid" 2>/dev/null; then
      rm -rf "$tmp_dir"
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
    if [ "$waited" -ge 15 ]; then
      kill "$server_pid" >/dev/null 2>&1 || true
      rm -rf "$tmp_dir"
      return 1
    fi
  done

  local port
  port="$(cat "$port_file")"
  local url="http://127.0.0.1:$port/"
  if ! open_url "$url"; then
    echo "Open this URL in your browser: $url"
  fi

  echo "Waiting for submission..."
  while [ ! -s "$result_file" ]; do
    if ! kill -0 "$server_pid" 2>/dev/null; then
      rm -rf "$tmp_dir"
      return 1
    fi
    sleep 1
  done

  provider="$(read_json_value "$result_file" "provider")"
  api_key="$(read_json_value "$result_file" "apiKey")"
  feishu_app_id="$(read_json_value "$result_file" "feishuAppId")"
  feishu_app_secret="$(read_json_value "$result_file" "feishuAppSecret")"

  wait "$server_pid" >/dev/null 2>&1 || true
  rm -rf "$tmp_dir"
  return 0
}

collect_config_via_tty() {
  if [ ! -r /dev/tty ]; then
    echo "Interactive setup is unavailable."
    echo "Set OPENCLAW_API_KEY, OPENCLAW_FEISHU_APP_ID, and OPENCLAW_FEISHU_APP_SECRET, then rerun."
    exit 1
  fi

  section "Collecting config"
  echo "We need 4 values: provider, API Key, Feishu App ID, Feishu App Secret."
  echo "Tip: all inputs are visible on screen. Type and press Enter."

  local provider_input="${OPENCLAW_PROVIDER:-}"
  if [ -z "$provider_input" ]; then
    echo "Choose provider:"
    echo "1) Kimi Code (default, recommended)"
    echo "2) Moonshot"
    echo "3) MiniMax"
    provider_input="$(read_text "Enter 1, 2, or 3 (default 1): ")"
    if [ -z "$provider_input" ]; then
      provider_input="1"
    fi
  fi

  apply_provider_settings "$provider_input"
  echo "Provider: $provider"

  api_key="${OPENCLAW_API_KEY:-}"
  if [ -z "$api_key" ]; then
    api_key="$(read_required_text "$api_key_label: ")"
  fi

  feishu_app_id="${OPENCLAW_FEISHU_APP_ID:-}"
  if [ -z "$feishu_app_id" ]; then
    feishu_app_id="$(read_required_text "Feishu App ID (starts with cli_): ")"
  fi

  feishu_app_secret="${OPENCLAW_FEISHU_APP_SECRET:-}"
  if [ -z "$feishu_app_secret" ]; then
    feishu_app_secret="$(read_required_text "Feishu App Secret: ")"
  fi
}

collect_config() {
  provider=""
  api_key="${OPENCLAW_API_KEY:-}"
  feishu_app_id="${OPENCLAW_FEISHU_APP_ID:-}"
  feishu_app_secret="${OPENCLAW_FEISHU_APP_SECRET:-}"

  if [ -n "$api_key" ] && [ -n "$feishu_app_id" ] && [ -n "$feishu_app_secret" ]; then
    section "Collecting config"
    provider="${OPENCLAW_PROVIDER:-kimi-code}"
    apply_provider_settings "$provider"
    echo "Using config from environment variables."
    return
  fi

  if collect_config_via_web; then
    apply_provider_settings "$provider"
    return
  fi

  collect_config_via_tty
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

collect_config

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
elif [ "$provider" = "moonshot" ]; then
  openclaw onboard --non-interactive --accept-risk --mode local \
    --auth-choice "$auth_choice" --moonshot-api-key "$api_key" \
    --skip-channels --skip-daemon --skip-skills --skip-ui --skip-health \
    --gateway-bind loopback --gateway-port 18789
else
  openclaw onboard --non-interactive --accept-risk --mode local \
    --auth-choice "$auth_choice" --kimi-code-api-key "$api_key" \
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
feishu_dm_policy="${OPENCLAW_FEISHU_DM_POLICY:-pairing}"
openclaw config set channels.feishu.dmPolicy "$feishu_dm_policy"
if [ "$feishu_dm_policy" = "open" ]; then
  openclaw config set channels.feishu.allowFrom '["*"]' --strict-json
else
  openclaw config unset channels.feishu.allowFrom >/dev/null 2>&1 || true
fi

section "Starting Gateway"
openclaw gateway install >/dev/null 2>&1 || true
openclaw gateway start >/dev/null 2>&1 || true
if ! openclaw health >/dev/null 2>&1; then
  nohup openclaw gateway run >/tmp/openclaw_gateway.log 2>&1 &
  sleep 2
fi

inject_runtime_safety_policy

section "Done"
echo "Installed and configured successfully."
echo "Provider: $provider, model: $model_ref"
echo "Use: openclaw models list"
if [ "$feishu_dm_policy" = "pairing" ]; then
  echo "Pairing mode enabled."
  echo "1) Send 'hi' to your Feishu bot."
  echo "2) Copy pairing code from bot reply."
  echo "3) Run: openclaw pairing approve feishu <PAIRING_CODE>"
fi
