# Paseo + 可选工具

基于官方 base 的 [Paseo](https://github.com/getpaseo/paseo) Docker 镜像，默认最小化，可在**容器启动时**通过环境变量安装 [Claude Code](https://github.com/anthropics/claude-code)、[OpenSpec](https://github.com/Fission-AI/OpenSpec)、[Codex](https://github.com/openai/codex)、[OpenCode](https://github.com/sst/opencode)、[Go](https://go.dev)、[Flutter](https://flutter.dev) 和 [gh](https://cli.github.com)。安装后的 AI 工具会自动把 API 凭据和模型选择写入各自的配置文件。

[English](README.md)

## 用法

```bash
docker pull ghcr.io/pikapeek/paseo:latest

docker run -d --name paseo \
  --restart unless-stopped \
  -p 6767:6767 \
  -e PASEO_PASSWORD="change-me" \
  -v /data/paseo:/home/paseo \
  ghcr.io/pikapeek/paseo:latest
```

```yaml
# docker compose
services:
  paseo:
    image: ghcr.io/pikapeek/paseo:latest
    container_name: paseo
    restart: unless-stopped
    ports:
      - "6767:6767"
    environment:
      - PASEO_PASSWORD=change-me
    volumes:
      - /data/paseo:/home/paseo
```

Dashboard: `http://localhost:6767` — Web UI 连接时输入 `PASEO_PASSWORD`。

要安装工具，只要在下表对应的 `-e` / `environment` 项加上 `INSTALL_*` 标志（及 API / 模型变量）即可。

## 可选工具

工具**默认都不安装**，按需开启。每个工具用 `INSTALL_*` 变量启用，可用对应的版本变量锁定版本（不指定则用最新版）。安装在**容器启动时、以 root 身份**执行，之后 daemon 会降权到 `paseo` 用户。安装是幂等的：已安装的工具在后续重启时会跳过。某个工具安装失败只会打日志跳过，不影响 daemon 启动。

| 工具 | 启用方式 | 版本变量（默认） | 安装方式 |
|------|---------|----------------|---------|
| Claude Code | `INSTALL_CLAUDE=true` | `CLAUDE_VERSION`（`latest`） | `npm i -g @anthropic-ai/claude-code` |
| OpenSpec | `INSTALL_OPENSPEC=true` | `OPENSPEC_VERSION`（`latest`） | `npm i -g @fission-ai/openspec` |
| Codex | `INSTALL_CODEX=true` | `CODEX_VERSION`（`latest`） | `npm i -g @openai/codex` |
| OpenCode | `INSTALL_OPENCODE=true` | `OPENCODE_VERSION`（`latest`） | `npm i -g opencode-ai` |
| Go | `INSTALL_GO=true` | `GO_VERSION`（`1.26.5`） | go.dev 官方包 → `/usr/local/go` |
| Flutter | `INSTALL_FLUTTER=true` | `FLUTTER_VERSION`（`latest`） | flutter.dev 官方包 → `/usr/local/flutter` |
| gh（GitHub CLI） | `INSTALL_GH=true` | — | `apt-get install gh` |

**Node.js** 由 base 镜像提供（`node:22`），始终存在 —— paseo 的 daemon 依赖它，因此不可单独选择。

### API 凭据

每个 AI 工具**独立配置**，各自有独立的 key + base URL（无共享变量）。
安装时自动将凭据写入该工具的配置文件（属主为 `paseo` 用户），agent 开箱即用：

| 工具 | 配置文件 | Key 变量 | Base URL 变量 |
|------|---------|---------|--------------|
| Claude Code | `~/.claude/settings.json` | `CLAUDE_API_KEY` | `CLAUDE_BASE_URL` |
| Codex | `~/.codex/config.toml` | `CODEX_API_KEY` | `CODEX_BASE_URL` |
| OpenCode | `~/.local/share/opencode/auth.json` | `OPENCODE_API_KEY` | `OPENCODE_BASE_URL` |

每个 AI 工具还能用环境变量**锁定模型**。Claude Code 有四个模型槽位（主模型 + opus/sonnet/haiku 别名），Codex 有两个（主模型 + `/review`），OpenCode 有两个（主模型 + small 模型）：

| 工具 | 模型变量 |
|------|---------|
| Claude Code | `CLAUDE_MODEL`、`CLAUDE_OPUS_MODEL`、`CLAUDE_SONNET_MODEL`、`CLAUDE_HAIKU_MODEL` |
| Codex | `CODEX_MODEL`、`CODEX_REVIEW_MODEL` |
| OpenCode | `OPENCODE_MODEL`、`OPENCODE_SMALL_MODEL`（格式 `provider/model`，如 `deepseek/deepseek-chat`） |

如果工具安装了但没设 API key，工具仍会装上，只是暂时未配置；设好变量并重启容器后即生效。

## GitHub Token

前往 [Settings → Developer settings → Personal access tokens → Fine-grained tokens](https://github.com/settings/tokens?type=beta) → Generate new token。

选择 `Repository access: All repositories`，授予 `Contents: Read-only` 权限。生成后把 token 填入 `GITHUB_TOKEN`。需要 `INSTALL_GH=true` 安装 gh 后，才会用它配置 git 凭据。

## OpenSpec

[OpenSpec](https://github.com/Fission-AI/OpenSpec) 用于实现 Spec 驱动的 AI 开发。用 `INSTALL_OPENSPEC=true` 开启后，在项目中使用：

```bash
# 在项目目录初始化
openspec init

# 然后在 Claude Code 中使用 slash 命令：
# /opsx:explore     — 探索分析，先规划再写代码
# /opsx:propose     — 提出变更方案
# /opsx:apply       — 执行计划任务
# /opsx:archive     — 归档已完成变更
```

## 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `PASEO_PASSWORD` | Daemon 鉴权密码 | — |
| `INSTALL_CLAUDE` | 启动时安装 Claude Code（`true`/`1`） | 关 |
| `INSTALL_OPENSPEC` | 启动时安装 OpenSpec | 关 |
| `INSTALL_CODEX` | 启动时安装 Codex | 关 |
| `INSTALL_OPENCODE` | 启动时安装 OpenCode | 关 |
| `INSTALL_GO` | 启动时安装 Go | 关 |
| `INSTALL_FLUTTER` | 启动时安装 Flutter | 关 |
| `INSTALL_GH` | 启动时安装 GitHub CLI | 关 |
| `CLAUDE_VERSION` | Claude Code 版本锁定 | `latest` |
| `OPENSPEC_VERSION` | OpenSpec 版本锁定 | `latest` |
| `CODEX_VERSION` | Codex 版本锁定 | `latest` |
| `OPENCODE_VERSION` | OpenCode 版本锁定 | `latest` |
| `GO_VERSION` | Go 版本锁定（如 `1.26.5`） | `1.26.5` |
| `FLUTTER_VERSION` | Flutter 版本锁定（如 `3.44.8`） | `latest` |
| `CLAUDE_API_KEY` | Claude Code API key（独立） | — |
| `CLAUDE_BASE_URL` | Claude Code API 端点 | `https://api.anthropic.com` |
| `CLAUDE_MODEL` | Claude Code 主模型 | — |
| `CLAUDE_OPUS_MODEL` | Claude Code `opus` 别名模型 | — |
| `CLAUDE_SONNET_MODEL` | Claude Code `sonnet` 别名模型 | — |
| `CLAUDE_HAIKU_MODEL` | Claude Code `haiku` 别名模型 | — |
| `CODEX_API_KEY` | Codex API key（独立） | — |
| `CODEX_BASE_URL` | Codex API 端点 | — |
| `CODEX_MODEL` | Codex 主模型 | — |
| `CODEX_REVIEW_MODEL` | Codex `/review` 模型 | — |
| `OPENCODE_API_KEY` | OpenCode API key（独立） | — |
| `OPENCODE_BASE_URL` | OpenCode API 端点 | — |
| `OPENCODE_MODEL` | OpenCode 主模型（`provider/model`） | — |
| `OPENCODE_SMALL_MODEL` | OpenCode small 模型（`provider/model`） | — |
| `OPENCODE_PROVIDER` | OpenCode provider id（`openai` 或 `anthropic`） | `openai` |
| `GITHUB_TOKEN` | GitHub Token（`gh` CLI 鉴权） | — |
| `PASEO_HOSTNAMES` | 允许的 Host header（`true` = 全部放行） | `true` |

## 引用

- [getpaseo/paseo](https://github.com/getpaseo/paseo) — 多 Agent 编排 CLI
- [anthropics/claude-code](https://github.com/anthropics/claude-code) — Anthropic 官方 AI 编程助手
- [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec) — AI 原生 Spec 驱动开发
- [openai/codex](https://github.com/openai/codex) — OpenAI 编程 Agent
- [sst/opencode](https://github.com/sst/opencode) — 开源 AI 编程 Agent
- [go.dev](https://go.dev) — Go 工具链
- [flutter.dev](https://flutter.dev) — Flutter SDK