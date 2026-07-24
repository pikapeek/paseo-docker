# Paseo + Claude Code

Pre-installed [Paseo](https://github.com/getpaseo/paseo) + [Claude Code](https://github.com/anthropics/claude-code) + [OpenSpec](https://github.com/Fission-AI/OpenSpec) Docker image with custom API support.

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

Enter `PASEO_PASSWORD` in the web UI to connect.

## GitHub Token

Go to [Settings → Developer settings → Personal access tokens → Fine-grained tokens](https://github.com/settings/tokens?type=beta) → Generate new token.

Set `Repository access: All repositories` and grant `Contents: Read-only`. Copy the token and pass it as `GITHUB_TOKEN`.

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PASEO_PASSWORD` | Daemon auth password | — |
| `GITHUB_TOKEN` | GitHub token for `gh` CLI | — |
| `ANTHROPIC_BASE_URL` | Custom API endpoint | `https://api.anthropic.com` |
| `ANTHROPIC_AUTH_TOKEN` | API Key (**required**) | — |
| `PASEO_HOSTNAMES` | Allowed Host headers (`true` = all) | `true` |

## OpenSpec

[OpenSpec](https://github.com/Fission-AI/OpenSpec) is pre-installed. Use it in your project to enable spec-driven development with AI assistants.

```bash
# Initialize in your project directory
openspec init

# Then use slash commands in Claude Code:
# /opsx:explore     — explore and plan before writing code
# /opsx:propose     — propose a structured change
# /opsx:apply       — implement planned tasks
# /opsx:archive     — archive completed changes
```

## References

- [getpaseo/paseo](https://github.com/getpaseo/paseo) — Multi-agent orchestration CLI
- [anthropics/claude-code](https://github.com/anthropics/claude-code) — Anthropic official AI coding assistant
- [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec) — AI-native spec-driven development
