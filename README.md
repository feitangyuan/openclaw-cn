# openclaw-cn

OpenClaw 国内极简安装脚本，跳过官方向导，一行命令完成安装并直连飞书。

## 用法

```bash
curl -fsSL https://raw.githubusercontent.com/feitangyuan/openclaw-cn/main/install.sh | bash
```

脚本会自动安装 OpenClaw，然后提示你依次填入三个值：

1. **模型 API Key**（Kimi 或 MiniMax）— 去对应平台官网获取
2. **飞书 App ID** — 格式以 `cli_` 开头
3. **飞书 App Secret** — 和 App ID 在同一个页面

填完自动配置，自动启动 Gateway。
安装阶段会优先使用国内 npm 镜像，失败后自动回退官方安装方式。
模型选择为单键交互：按 `K` 选 Kimi，按 `M` 选 MiniMax（默认 Kimi）。

默认使用 Kimi；如果你用 MiniMax，可在安装命令前加：

```bash
OPENCLAW_PROVIDER=minimax curl -fsSL https://raw.githubusercontent.com/feitangyuan/openclaw-cn/main/install.sh | bash
```

---

## 前置条件

**本地环境**

- 脚本会自动安装 Node.js v22+ 和 OpenClaw
- Windows 用户需先开启 WSL

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
| Kimi（推荐）| kimi-k2.5 | 支付宝 |
| MiniMax | abab6.5s-chat | 支付宝 |

---

## 常用命令

```bash
openclaw gateway start   # 启动
openclaw gateway stop    # 停止
openclaw doctor          # 自检修复
openclaw models list     # 查看已配置的模型
```
