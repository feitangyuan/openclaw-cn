# openclaw-cn

OpenClaw 国内简化安装版，主打可视化安装体验。

和官方向导相比，这一版不是让用户在终端里一步步输入配置，
而是启动后自动打开本地网页配置页面。
用户只需要按页面提示填写模型 Key、飞书信息并勾选常用 Skills，即可完成安装、配置和启动，更适合中文用户和小白用户快速上手。

## 用法

### 方式 1：一行命令（在线安装）

```bash
curl -fsSL https://raw.githubusercontent.com/feitangyuan/openclaw-cn/main/install.sh | bash
```

运行后会自动打开本地网页配置页。
你先填写基础配置，再勾选想要的 Skills：

1. **模型厂商**（Kimi Code / Moonshot / MiniMax）
2. **模型 API Key** — 去对应平台官网获取
3. **飞书 App ID** — 格式以 `cli_` 开头
4. **飞书 App Secret** — 和 App ID 在同一个页面
5. **必装 Skills**（可勾选）

当前网页里可勾选的 Skills：

- `web-search`：网页搜索
- `autonomy`：自主执行（启用内置能力）
- `summarize`：网页总结与链接提取
- `nano-pdf`：PDF 处理
- `openai-whisper`：音频转文字
- `github`：GitHub 开发能力

默认会预选：

- `web-search`
- `autonomy`
- `summarize`

提交后终端会继续自动配置并启动 Gateway。
安装阶段会优先使用国内 npm 镜像，失败后自动回退官方安装方式。
默认开启飞书配对模式（首次消息需批准，更安全）。
安装后会自动注入运行时安全策略（仅扩权/高风险动作需要确认，普通聊天不打断）。
安全策略见：[SECURITY_POLICY.md](./SECURITY_POLICY.md)。

如果当前环境没有图形界面，脚本会自动回退到终端输入模式。

### 方式 2：双击启动（本地安装包）

仓库内已提供启动器：

- macOS：`launch.command`
- Linux：`launch.sh`
- Windows：`launch.bat`

把 `install.sh` 和对应启动器放在同一目录即可。
启动器会优先执行同目录的本地 `install.sh`；如果本地没有，再回退到 GitHub 下载最新版本。

默认使用 **Kimi Code**（适配 `kimi.com/code/console` 的 key）。

如果你要用 Moonshot Open Platform key：

```bash
OPENCLAW_PROVIDER=moonshot curl -fsSL https://raw.githubusercontent.com/feitangyuan/openclaw-cn/main/install.sh | bash
```

如果你用 MiniMax：

```bash
OPENCLAW_PROVIDER=minimax curl -fsSL https://raw.githubusercontent.com/feitangyuan/openclaw-cn/main/install.sh | bash
```

如需免配对（首次可直接聊天）：

```bash
OPENCLAW_FEISHU_DM_POLICY=open curl -fsSL https://raw.githubusercontent.com/feitangyuan/openclaw-cn/main/install.sh | bash
```

## 首次配对（默认模式）

1. 先在飞书里给机器人发 `hi`
2. 机器人会回一个 `Pairing code`
3. 在终端执行：`openclaw pairing approve feishu <PAIRING_CODE>`

说明：

- 如果你安装时把 `OPENCLAW_FEISHU_DM_POLICY` 设成了 `open`，则不需要配对
- `web-search` 勾选后不一定等于“直接可搜”
- `Moonshot` 可直接复用同一个 API Key 开启搜索
- `Kimi Code / MiniMax` 如果没有额外搜索 key，脚本会自动跳过直连搜索，不会让安装失败

---

## 前置条件

**本地环境**

- 脚本会自动安装 Node.js v22+ 和 OpenClaw
- Windows 用户需先安装可用的 `bash`（推荐 WSL，也可用 Git Bash）

**飞书机器人**（需提前创建）

1. 去 [open.feishu.cn](https://open.feishu.cn) 创建企业自建应用
2. 添加「机器人」能力
3. 权限管理里勾上 `im:message`（私聊 + 群消息）
4. 事件订阅里添加 `im.message.receive_v1`，接收方式选「长连接」
5. 发布内部测试版
6. 在「凭证与基础信息」里复制 App ID 和 App Secret

---

## 支持的 AI 提供商

| 提供商 | 模型 | 充值方式 |
|--------|------|----------|
| Kimi Code（默认）| k2p5 | 支付宝 |
| Moonshot | kimi-k2.5 | 支付宝 |
| MiniMax | MiniMax-M2.5 | 支付宝 |

---

## 常用命令

```bash
openclaw gateway start   # 启动
openclaw gateway stop    # 停止
openclaw doctor          # 自检修复
openclaw models list     # 查看已配置的模型
```
