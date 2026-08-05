# Paseo + Optional Tools

[Paseo](https://github.com/getpaseo/paseo) Docker image (over the official base) that starts minimal and lets you install [Claude Code](https://github.com/anthropics/claude-code), [OpenSpec](https://github.com/Fission-AI/OpenSpec), [Codex](https://github.com/openai/codex), [OpenCode](https://github.com/sst/opencode), [Go](https://go.dev), [Flutter](https://flutter.dev), and [gh](https://cli.github.com) at **container startup** via environment variables. Installed AI tools get their API credentials and model selection written into their config files automatically.

[中文说明](README.zh-CN.md)

## Usage

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

Dashboard: `http://localhost:6767` — enter `PASEO_PASSWORD` in the web UI to connect.

Install a tool by adding its `INSTALL_*` flag (and API/model vars) as extra `-e` / `environment` entries — see the table below.

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
| Flutter | `INSTALL_FLUTTER=true` | `FLUTTER_VERSION` (`latest`) | flutter.dev tar.xz → `/usr/local/flutter` |
| gh (GitHub CLI) | `INSTALL_GH=true` | — | `apt-get install gh` |

**Node.js** is provided by the base image (`node:22`) and is always present —
paseo's daemon requires it, so it is not separately selectable.

### API credentials

Each AI tool is configured **independently** with its own key + base URL
(no shared variables). When a tool is installed, its credentials are written
into the tool's config file (owned by the `paseo` user), so the agent works
immediately:

| Tool | Config file | Key var | Base URL var |
|------|------------|---------|--------------|
| Claude Code | `~/.claude/settings.json` | `CLAUDE_API_KEY` | `CLAUDE_BASE_URL` |
| Codex | `~/.codex/config.toml` | `CODEX_API_KEY` | `CODEX_BASE_URL` |
| OpenCode | `~/.local/share/opencode/auth.json` | `OPENCODE_API_KEY` | `OPENCODE_BASE_URL` |

Each AI tool can also pin its **model(s)** via environment variables. Claude Code
has four model slots (main + opus/sonnet/haiku aliases), Codex has two (main +
`/review`), OpenCode has two (main + small model):

| Tool | Model var(s) |
|------|-------------|
| Claude Code | `CLAUDE_MODEL`, `CLAUDE_OPUS_MODEL`, `CLAUDE_SONNET_MODEL`, `CLAUDE_HAIKU_MODEL` |
| Codex | `CODEX_MODEL`, `CODEX_REVIEW_MODEL` |
| OpenCode | `OPENCODE_MODEL`, `OPENCODE_SMALL_MODEL` (format `provider/model`, e.g. `deepseek/deepseek-chat`) |

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
| `INSTALL_FLUTTER` | Install Flutter at startup | off |
| `INSTALL_GH` | Install GitHub CLI at startup | off |
| `CLAUDE_VERSION` | Version pin for Claude Code | `latest` |
| `OPENSPEC_VERSION` | Version pin for OpenSpec | `latest` |
| `CODEX_VERSION` | Version pin for Codex | `latest` |
| `OPENCODE_VERSION` | Version pin for OpenCode | `latest` |
| `GO_VERSION` | Version pin for Go (e.g. `1.26.5`) | `1.26.5` |
| `FLUTTER_VERSION` | Version pin for Flutter (e.g. `3.44.8`) | `latest` |
| `CLAUDE_API_KEY` | Claude Code API key (independent) | — |
| `CLAUDE_BASE_URL` | Claude Code API endpoint | `https://api.anthropic.com` |
| `CLAUDE_MODEL` | Claude Code main model | — |
| `CLAUDE_OPUS_MODEL` | Claude Code `opus` alias model | — |
| `CLAUDE_SONNET_MODEL` | Claude Code `sonnet` alias model | — |
| `CLAUDE_HAIKU_MODEL` | Claude Code `haiku` alias model | — |
| `CODEX_API_KEY` | Codex API key (independent) | — |
| `CODEX_BASE_URL` | Codex API endpoint | — |
| `CODEX_MODEL` | Codex main model | — |
| `CODEX_REVIEW_MODEL` | Codex `/review` model | — |
| `OPENCODE_API_KEY` | OpenCode API key (independent) | — |
| `OPENCODE_BASE_URL` | OpenCode API endpoint | — |
| `OPENCODE_MODEL` | OpenCode main model (`provider/model`) | — |
| `OPENCODE_SMALL_MODEL` | OpenCode small model (`provider/model`) | — |
| `OPENCODE_PROVIDER` | OpenCode provider id (`openai` or `anthropic`) | `openai` |
| `GITHUB_TOKEN` | GitHub token for `gh` CLI | — |
| `PASEO_HOSTNAMES` | Allowed Host headers (`true` = all) | `true` |

## References

- [getpaseo/paseo](https://github.com/getpaseo/paseo) — Multi-agent orchestration CLI
- [anthropics/claude-code](https://github.com/anthropics/claude-code) — Anthropic official AI coding assistant
- [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec) — AI-native spec-driven development
- [openai/codex](https://github.com/openai/codex) — OpenAI coding agent
- [sst/opencode](https://github.com/sst/opencode) — Open source AI coding agent
- [go.dev](https://go.dev) — Go toolchain
- [flutter.dev](https://flutter.dev) — Flutter SDK