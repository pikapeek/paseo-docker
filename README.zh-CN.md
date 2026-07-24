# Paseo + Claude Code

预装 [Paseo](https://github.com/getpaseo/paseo) + [Claude Code](https://github.com/anthropics/claude-code) + [OpenSpec](https://github.com/Fission-AI/OpenSpec) 的 Docker 镜像，支持自定义 API。

[English](README.md)

## 用法

```bash
# 拉取
docker pull ghcr.io/pikapeek/paseo:latest

# docker run
docker run -d --name paseo \
  --restart unless-stopped \
  -p 6767:6767 \
  -e PASEO_PASSWORD="change-me" \
  -e GITHUB_TOKEN="ghp_xxx" \
  -e ANTHROPIC_BASE_URL="https://your-api.example.com" \
  -e ANTHROPIC_AUTH_TOKEN="your-key" \
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
      - GITHUB_TOKEN=ghp_xxx
      - ANTHROPIC_BASE_URL=https://your-api.example.com
      - ANTHROPIC_AUTH_TOKEN=your-key
    volumes:
      - /data/paseo:/home/paseo
```

Dashboard: `http://localhost:6767`

Web UI 连接时输入 `PASEO_PASSWORD`。

## GitHub Token

前往 [Settings → Developer settings → Personal access tokens → Fine-grained tokens](https://github.com/settings/tokens?type=beta) → Generate new token。

选择 `Repository access: All repositories`，授予 `Contents: Read-only` 权限。生成后把 token 填入 `GITHUB_TOKEN`。

## 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `PASEO_PASSWORD` | Daemon 鉴权密码 | — |
| `GITHUB_TOKEN` | GitHub Token（`gh` CLI 鉴权） | — |
| `ANTHROPIC_BASE_URL` | 自定义 API 端点 | `https://api.anthropic.com` |
| `ANTHROPIC_AUTH_TOKEN` | API Key（**必需**） | — |
| `PASEO_HOSTNAMES` | 允许的 Host header（`true` = 全部放行） | `true` |

## OpenSpec

[OpenSpec](https://github.com/Fission-AI/OpenSpec) 已预装。在项目中使用它实现 Spec 驱动的 AI 开发：

```bash
# 在项目目录初始化
openspec init

# 然后在 Claude Code 中使用 slash 命令：
# /opsx:explore     — 探索分析，先规划再写代码
# /opsx:propose     — 提出变更方案
# /opsx:apply       — 执行计划任务
# /opsx:archive     — 归档已完成变更
```

## 引用

- [getpaseo/paseo](https://github.com/getpaseo/paseo) — 多 Agent 编排 CLI
- [anthropics/claude-code](https://github.com/anthropics/claude-code) — Anthropic 官方 AI 编程助手
- [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec) — AI 原生 Spec 驱动开发
