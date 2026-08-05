# Paseo + 可选工具

在 [Paseo](https://github.com/getpaseo/paseo) 上预置了多款 AI 编程工具，默认只跑 Paseo 本体；需要哪个工具，启动时加一个环境变量就自动装好。Claude Code、Codex、OpenCode 的 API key 和模型会自动写入各自的配置，装完即用。

[English](README.md)

## 快速开始

```bash
docker pull ghcr.io/pikapeek/paseo:latest

docker run -d --name paseo \
  --restart unless-stopped \
  -p 6767:6767 \
  -e PASEO_PASSWORD="change-me" \
  -v /data/paseo:/home/paseo \
  ghcr.io/pikapeek/paseo:latest
```

打开 `http://localhost:6767`，输入 `PASEO_PASSWORD` 连接。

> 用 compose 的话，完整模板见 [`docker-compose.yml`](docker-compose.yml)（所有可选项都已注释）。

## 启用 AI 工具

在启动命令里加 `-e 变量=值` 即可。每个工具默认关闭，加 `INSTALL_*` 启用，同时配上它的 API key 就能用。

| 工具 | 启用 | 需要的 Key | 模型（可选） |
|------|------|-----------|-------------|
| Claude Code | `INSTALL_CLAUDE=true` | `CLAUDE_API_KEY` | `CLAUDE_MODEL` 主模型；`CLAUDE_OPUS_MODEL`/`CLAUDE_SONNET_MODEL`/`CLAUDE_HAIKU_MODEL` 三个子槽位 |
| Codex | `INSTALL_CODEX=true` | `CODEX_API_KEY` | `CODEX_MODEL` 主模型；`CODEX_REVIEW_MODEL` 审查模型 |
| OpenCode | `INSTALL_OPENCODE=true` | `OPENCODE_API_KEY` | `OPENCODE_MODEL` 主模型；`OPENCODE_SMALL_MODEL` 轻量模型 |
| OpenSpec | `INSTALL_OPENSPEC=true` | — | — |
| Go | `INSTALL_GO=true` | — | `GO_VERSION` |
| Flutter | `INSTALL_FLUTTER=true` | — | `FLUTTER_VERSION` |
| gh（GitHub CLI） | `INSTALL_GH=true` | `GITHUB_TOKEN` | — |

**自定义 API 端点**：Claude Code 用 `CLAUDE_BASE_URL`，Codex 用 `CODEX_BASE_URL`，OpenCode 用 `OPENCODE_BASE_URL`。默认连官方 API。

**OpenCode 模型格式**：`provider/model`，例如连 DeepSeek 写 `OPENCODE_MODEL=deepseek/deepseek-chat`。用 Anthropic 兼容端点时设 `OPENCODE_PROVIDER=anthropic`。

**例子** — 装 Claude Code + Go：

```bash
docker run -d --name paseo \
  --restart unless-stopped \
  -p 6767:6767 \
  -e PASEO_PASSWORD="change-me" \
  -e INSTALL_CLAUDE=true \
  -e CLAUDE_API_KEY="sk-ant-..." \
  -e INSTALL_GO=true \
  -v /data/paseo:/home/paseo \
  ghcr.io/pikapeek/paseo:latest
```

## 网络权限（可选）

Agent 有时要搭 VPN、改网络接口或跑 `ping`/`tcpdump`，需要额外给容器开权限。默认关闭，按需开启：

- `cap_add: [NET_ADMIN, NET_RAW]` — 管理路由/防火墙、原始套接字
- `devices: [/dev/net/tun]` — 建 VPN 隧道（WireGuard / OpenVPN）
- `sysctls: [net.ipv6.conf.*.disable_ipv6=0]` — 容器内启用 IPv6

完整写法见 [`docker-compose.yml`](docker-compose.yml)。⚠️ 这些权限会削弱容器隔离，只在确实需要时开启。

## GitHub Token

Paseo 克隆仓库要用。在 [GitHub → Settings → Developer settings → Fine-grained tokens](https://github.com/settings/tokens?type=beta) 生成，`Repository access: All repositories` + `Contents: Read-only`，填入 `GITHUB_TOKEN`（需同时 `INSTALL_GH=true`）。

## OpenSpec

Spec 驱动开发，`INSTALL_OPENSPEC=true` 启用后，在项目里 `openspec init`，然后在 Claude Code 里用 `/opsx:explore`、`/opsx:propose`、`/opsx:apply`、`/opsx:archive` 走「规划 → 提方案 → 实现 → 归档」流程。

## 全部环境变量

| 变量 | 说明 | 默认 |
|------|------|------|
| `PASEO_PASSWORD` | 连接密码（**必填**） | — |
| `INSTALL_*` | 安装对应工具（见上表） | 关 |
| `*_VERSION` | 工具版本锁定（不填用最新版） | `latest` |
| `CLAUDE_API_KEY` / `CLAUDE_BASE_URL` | Claude Code 凭据 | — / `https://api.anthropic.com` |
| `CLAUDE_MODEL` / `CLAUDE_OPUS_MODEL` / `CLAUDE_SONNET_MODEL` / `CLAUDE_HAIKU_MODEL` | Claude Code 模型 | — |
| `CODEX_API_KEY` / `CODEX_BASE_URL` | Codex 凭据 | — |
| `CODEX_MODEL` / `CODEX_REVIEW_MODEL` | Codex 模型 | — |
| `OPENCODE_API_KEY` / `OPENCODE_BASE_URL` | OpenCode 凭据 | — |
| `OPENCODE_MODEL` / `OPENCODE_SMALL_MODEL` | OpenCode 模型 | — |
| `OPENCODE_PROVIDER` | OpenCode 提供者 | `openai` |
| `GITHUB_TOKEN` | GitHub 凭据（配 `INSTALL_GH`） | — |
| `PASEO_HOSTNAMES` | 允许的 Host header | `true` |

## 引用

- [getpaseo/paseo](https://github.com/getpaseo/paseo) — 多 Agent 编排 CLI
- [anthropics/claude-code](https://github.com/anthropics/claude-code) — Claude Code
- [openai/codex](https://github.com/openai/codex) — OpenAI Codex
- [sst/opencode](https://github.com/sst/opencode) — OpenCode
- [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec) — Spec 驱动开发
- [go.dev](https://go.dev) — Go
- [flutter.dev](https://flutter.dev) — Flutter
