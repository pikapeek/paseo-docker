# Paseo + Claude Code

预装 [Paseo](https://github.com/getpaseo/paseo) + [Claude Code](https://github.com/anthropics/claude-code) 的 Docker 镜像，支持自定义 API。

[English](README.md)

## 用法

```bash
# 拉取
docker pull ghcr.io/pikapeek/paseo:latest

# docker run
docker run -d --name paseo \
  --restart unless-stopped \
  -p 6767:6767 \
  -e ANTHROPIC_BASE_URL="https://your-api.example.com" \
  -e ANTHROPIC_AUTH_TOKEN="your-key" \
  -e ANTHROPIC_MODEL="your-model" \
  -v /data/workspace:/workspace \
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
      - ANTHROPIC_BASE_URL=https://your-api.example.com
      - ANTHROPIC_AUTH_TOKEN=your-key
      - ANTHROPIC_MODEL=your-model
    volumes:
      - /data/workspace:/workspace
      - /data/paseo:/home/paseo
```

Dashboard: `http://localhost:6767`

## 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `ANTHROPIC_AUTH_TOKEN` | API Key（**必需**） | — |
| `ANTHROPIC_BASE_URL` | 自定义 API 端点 | `https://api.anthropic.com` |
| `ANTHROPIC_MODEL` | 默认模型 | `claude-sonnet-4-6` |
| `ANTHROPIC_OPUS_MODEL` | Opus 模型 | `claude-opus-4-8` |
| `ANTHROPIC_SONNET_MODEL` | Sonnet 模型 | `claude-sonnet-4-6` |
| `ANTHROPIC_HAIKU_MODEL` | Haiku 模型 | `claude-haiku-4-5` |

## 引用

- [getpaseo/paseo](https://github.com/getpaseo/paseo) — 多 Agent 编排 CLI
- [anthropics/claude-code](https://github.com/anthropics/claude-code) — Anthropic 官方 AI 编程助手
