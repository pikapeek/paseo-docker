# Paseo + Claude Code

Pre-installed [Paseo](https://github.com/getpaseo/paseo) + [Claude Code](https://github.com/anthropics/claude-code) Docker image with custom API support.

[中文说明](README.zh-CN.md)

## Usage

```bash
# Pull
docker pull ghcr.io/pikapeek/paseo:latest

# docker run
docker run -d --name paseo \
  --restart unless-stopped \
  -p 6767:6767 \
  -e PASEO_PASSWORD="change-me" \
  -e GITHUB_TOKEN="ghp_xxx" \
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
      - PASEO_PASSWORD=change-me
      - GITHUB_TOKEN=ghp_xxx
      - ANTHROPIC_BASE_URL=https://your-api.example.com
      - ANTHROPIC_AUTH_TOKEN=your-key
      - ANTHROPIC_MODEL=your-model
    volumes:
      - /data/workspace:/workspace
      - /data/paseo:/home/paseo
```

Dashboard: `http://localhost:6767`

Enter `PASEO_PASSWORD` in the web UI to connect.

## GitHub Token

Go to [Settings → Developer settings → Personal access tokens → Fine-grained tokens](https://github.com/settings/tokens?type=beta) → Generate new token.

Set `Repository access: All repositories` and grant `Contents: Read-only`. Copy the token and pass it as `GITHUB_TOKEN`.

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PASEO_PASSWORD` | Daemon auth password | — |
| `GITHUB_TOKEN` | GitHub token for `gh` CLI | — |
| `ANTHROPIC_AUTH_TOKEN` | API Key (**required**) | — |
| `ANTHROPIC_BASE_URL` | Custom API endpoint | `https://api.anthropic.com` |
| `ANTHROPIC_MODEL` | Default model | `claude-sonnet-4-6` |
| `ANTHROPIC_OPUS_MODEL` | Opus model | `claude-opus-4-8` |
| `ANTHROPIC_SONNET_MODEL` | Sonnet model | `claude-sonnet-4-6` |
| `ANTHROPIC_HAIKU_MODEL` | Haiku model | `claude-haiku-4-5` |
| `PASEO_HOSTNAMES` | Allowed Host headers (`true` = all) | `true` |

## References

- [getpaseo/paseo](https://github.com/getpaseo/paseo) — Multi-agent orchestration CLI
- [anthropics/claude-code](https://github.com/anthropics/claude-code) — Anthropic official AI coding assistant
