# Paseo + 可选工具

[Paseo](https://github.com/getpaseo/paseo) 预置多款 AI 编程工具。默认只跑 Paseo 本体；需要哪个工具，启动时加环境变量就自动装好。Claude Code、Codex、OpenCode 的 API key 和模型会自动写入配置，装完即用。

[English](README.md)

## 快速开始

```bash
docker run -d --name paseo \
  --restart unless-stopped \
  -p 6767:6767 \
  -e PASEO_PASSWORD="change-me" \
  -v /data/paseo:/home/paseo \
  ghcr.io/pikapeek/paseo:latest
```

打开 `http://localhost:6767`，输入 `PASEO_PASSWORD`。compose 全功能模板（可选项已注释）见 [`docker-compose.yml`](docker-compose.yml)。

## 可选工具

每个工具默认关闭，在启动命令加对应的 `-e` 变量即可。

### AI 编程 Agent

| 工具 | 启用 | API key | 模型 | 版本 |
|------|------|---------|------|------|
| Claude Code | `INSTALL_CLAUDE=true` | `CLAUDE_API_KEY` | `CLAUDE_MODEL`（+ `CLAUDE_OPUS_MODEL`/`CLAUDE_SONNET_MODEL`/`CLAUDE_HAIKU_MODEL`） | `CLAUDE_VERSION` |
| Codex | `INSTALL_CODEX=true` | `CODEX_API_KEY` | `CODEX_MODEL`（+ `CODEX_REVIEW_MODEL`） | `CODEX_VERSION` |
| OpenCode | `INSTALL_OPENCODE=true` | `OPENCODE_API_KEY` | `OPENCODE_MODEL`（+ `OPENCODE_SMALL_MODEL`） | `OPENCODE_VERSION` |

默认连官方 API，自定义端点用 `CLAUDE_BASE_URL`/`CODEX_BASE_URL`/`OPENCODE_BASE_URL`。OpenCode 模型用 `provider/model` 格式（`OPENCODE_MODEL=deepseek/deepseek-chat`）；Anthropic 兼容端点设 `OPENCODE_PROVIDER=anthropic`。

### 开发工具

| 工具 | 启用 | 需要的凭据 | 版本 |
|------|------|-----------|------|
| OpenSpec | `INSTALL_OPENSPEC=true` | — | `OPENSPEC_VERSION` |
| Go | `INSTALL_GO=true` | — | `GO_VERSION` |
| Flutter | `INSTALL_FLUTTER=true` | — | `FLUTTER_VERSION` |
| gh（GitHub CLI） | `INSTALL_GH=true` | `GITHUB_TOKEN` | — |

不填版本 = 用最新版。

## 网络权限（可选）

Agent 搭 VPN、改网络接口或跑 `ping`/`tcpdump` 时需要的权限，默认关闭：

- `cap_add: [NET_ADMIN, NET_RAW]` — 管理路由/防火墙、原始套接字
- `devices: [/dev/net/tun]` — VPN 隧道（WireGuard / OpenVPN）
- `sysctls: [net.ipv6.conf.*.disable_ipv6=0]` — 启用 IPv6

完整写法见 [`docker-compose.yml`](docker-compose.yml)。⚠️ 会削弱容器隔离，仅在需要时开启。

## GitHub Token

Paseo 克隆仓库用。在 [GitHub → Settings → Developer settings → Fine-grained tokens](https://github.com/settings/tokens?type=beta) 生成：`Repository access: All repositories` + `Contents: Read-only`。填入 `GITHUB_TOKEN`（配 `INSTALL_GH=true`）。

## OpenSpec

Spec 驱动开发。`INSTALL_OPENSPEC=true`，在项目里 `openspec init`，然后在 Claude Code 里用 `/opsx:explore`、`/opsx:propose`、`/opsx:apply`、`/opsx:archive`。

## 其他环境变量

| 变量 | 说明 | 默认 |
|------|------|------|
| `PASEO_PASSWORD` | 连接密码（**必填**） | — |
| `PASEO_HOSTNAMES` | 允许的 Host header | `true` |

## 引用

- [getpaseo/paseo](https://github.com/getpaseo/paseo) — 多 Agent 编排 CLI
- [anthropics/claude-code](https://github.com/anthropics/claude-code) — Claude Code
- [openai/codex](https://github.com/openai/codex) — OpenAI Codex
- [sst/opencode](https://github.com/sst/opencode) — OpenCode
- [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec) — Spec 驱动开发
- [go.dev](https://go.dev) — Go
- [flutter.dev](https://flutter.dev) — Flutter
