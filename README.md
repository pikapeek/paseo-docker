# Paseo + Optional Tools

[Paseo](https://github.com/getpaseo/paseo) Docker image (over the official base) that starts minimal and lets you install [Claude Code](https://github.com/anthropics/claude-code), [OpenSpec](https://github.com/Fission-AI/OpenSpec), [Codex](https://github.com/openai/codex), [OpenCode](https://github.com/sst/opencode), [Go](https://go.dev), and [gh](https://cli.github.com) at **container startup** via environment variables. Installed tools get their API credentials written into their config files automatically.

[中文说明](README.zh-CN.md)

## Usage

```bash
# Pull
docker pull ghcr.io/pikapeek/paseo:latest

# docker run — minimal (only paseo)
docker run -d --name paseo \
  --restart unless-stopped \
  -p 6767:6767 \
  -e PASEO_PASSWORD="change-me" \
  -v /data/paseo:/home/paseo \
  ghcr.io/pikapeek/paseo:latest

# docker run — with Claude Code + Go
docker run -d --name paseo \
  --restart unless-stopped \
  -p 6767:6767 \
  -e PASEO_PASSWORD="change-me" \
  -e INSTALL_CLAUDE=true \
  -e ANTHROPIC_AUTH_TOKEN="your-key" \
  -e ANTHROPIC_BASE_URL="https://your-api.example.com" \
  -e INSTALL_GO=true \
  -e GO_VERSION="1.26.5" \
  -v /data/paseo:/home/paseo \
  ghcr.io/pikapeek/paseo:latest
```

```yaml
# docker compose — full-featured
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
      - INSTALL_CLAUDE=true
      - INSTALL_OPENSPEC=true
      - INSTALL_CODEX=true
      - INSTALL_OPENCODE=true
      - INSTALL_GO=true
      - INSTALL_GH=true
      - ANTHROPIC_AUTH_TOKEN=your-key
      - ANTHROPIC_BASE_URL=https://your-api.example.com
      - OPENAI_API_KEY=sk-xxx
      - OPENAI_BASE_URL=https://your-api.example.com/v1
    volumes:
      - /data/paseo:/home/paseo
```

Dashboard: `http://localhost:6767`

Enter `PASEO_PASSWORD` in the web UI to connect.

## Optional Tools

Tools are **off by default** — install only what you need. Each is enabled by
its `INSTALL_*` flag, optionally pinned with a version (unspecified = latest).
Installation happens **at container startup, as root**, before the daemon
drops to the `paseo` user. Installs are idempotent: already-installed tools
are skipped on later restarts. A tool that fails to install is logged and
skipped — the daemon always starts.

| Tool | Enable with | Version var (default) | Install |
|------|------------|----------------------|---------|
| Claude Code | `INSTALL_CLAUDE=true` | `CLAUDE_VERSION` (`latest`) | `npm i -g @anthropic-ai/claude-code` |
| OpenSpec | `INSTALL_OPENSPEC=true` | `OPENSPEC_VERSION` (`latest`) | `npm i -g @fission-ai/openspec` |
| Codex | `INSTALL_CODEX=true` | `CODEX_VERSION` (`latest`) | `npm i -g @openai/codex` |
| OpenCode | `INSTALL_OPENCODE=true` | `OPENCODE_VERSION` (`latest`) | `npm i -g opencode-ai` |
| Go | `INSTALL_GO=true` | `GO_VERSION` (`1.26.5`) | go.dev tarball → `/usr/local/go` |
| gh (GitHub CLI) | `INSTALL_GH=true` | — | `apt-get install gh` |

**Node.js** is provided by the base image (`node:22`) and is always present —
paseo's daemon requires it, so it is not separately selectable.

### API credentials

When a tool that needs an API key is installed, its credentials are read from
standard environment variables and written into the tool's config file (owned
by the `paseo` user), so the agent works immediately:

| Tool | Config file | Key var(s) | Base URL var |
|------|------------|------------|--------------|
| Claude Code | `~/.claude/settings.json` | `ANTHROPIC_AUTH_TOKEN` (or `ANTHROPIC_API_KEY`) | `ANTHROPIC_BASE_URL` |
| Codex | `~/.codex/config.toml` | `OPENAI_API_KEY` | `OPENAI_BASE_URL` |
| OpenCode | `~/.local/share/opencode/auth.json` | `OPENAI_API_KEY` / `ANTHROPIC_AUTH_TOKEN` | `OPENAI_BASE_URL` / `ANTHROPIC_BASE_URL` |

If a tool is installed without its API key, it still installs; it simply isn't
configured until you set the variable and restart.

## GitHub Token

Go to [Settings → Developer settings → Personal access tokens → Fine-grained tokens](https://github.com/settings/tokens?type=beta) → Generate new token.

Set `Repository access: All repositories` and grant `Contents: Read-only`. Copy the token and pass it as `GITHUB_TOKEN`. `gh` must be enabled (`INSTALL_GH=true`) for the credential helper to be configured from the token.

## OpenSpec

[OpenSpec](https://github.com/Fission-AI/OpenSpec) enables spec-driven development with AI assistants. Enable it with `INSTALL_OPENSPEC=true`, then in your project:

```bash
# Initialize in your project directory
openspec init

# Then use slash commands in Claude Code:
# /opsx:explore     — explore and plan before writing code
# /opsx:propose     — propose a structured change
# /opsx:apply       — implement planned tasks
# /opsx:archive     — archive completed changes
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PASEO_PASSWORD` | Daemon auth password | — |
| `INSTALL_CLAUDE` | Install Claude Code at startup (`true`/`1`) | off |
| `INSTALL_OPENSPEC` | Install OpenSpec at startup | off |
| `INSTALL_CODEX` | Install Codex at startup | off |
| `INSTALL_OPENCODE` | Install OpenCode at startup | off |
| `INSTALL_GO` | Install Go at startup | off |
| `INSTALL_GH` | Install GitHub CLI at startup | off |
| `CLAUDE_VERSION` | Version pin for Claude Code | `latest` |
| `OPENSPEC_VERSION` | Version pin for OpenSpec | `latest` |
| `CODEX_VERSION` | Version pin for Codex | `latest` |
| `OPENCODE_VERSION` | Version pin for OpenCode | `latest` |
| `GO_VERSION` | Version pin for Go (e.g. `1.26.5`) | `1.26.5` |
| `ANTHROPIC_AUTH_TOKEN` | Claude Code API key | — |
| `ANTHROPIC_API_KEY` | Alternative Claude Code API key | — |
| `ANTHROPIC_BASE_URL` | Claude Code API endpoint | `https://api.anthropic.com` |
| `OPENAI_API_KEY` | Codex / OpenCode API key | — |
| `OPENAI_BASE_URL` | Codex / OpenCode API endpoint | — |
| `GITHUB_TOKEN` | GitHub token for `gh` CLI | — |
| `PASEO_HOSTNAMES` | Allowed Host headers (`true` = all) | `true` |

## References

- [getpaseo/paseo](https://github.com/getpaseo/paseo) — Multi-agent orchestration CLI
- [anthropics/claude-code](https://github.com/anthropics/claude-code) — Anthropic official AI coding assistant
- [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec) — AI-native spec-driven development
- [openai/codex](https://github.com/openai/codex) — OpenAI coding agent
- [sst/opencode](https://github.com/sst/opencode) — Open source AI coding agent