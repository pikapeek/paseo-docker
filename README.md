# Paseo + Optional Tools

[Paseo](https://github.com/getpaseo/paseo) with optional tools (Claude Code / Codex / OpenCode AI agents, plus OpenSpec / Go / Flutter / GitHub CLI). Starts with just Paseo; install a tool at container startup via an environment variable. AI agents get their API keys and models configured automatically.

[中文说明](README.zh-CN.md)

## Quick start

```bash
docker run -d --name paseo \
  --restart unless-stopped \
  -p 6767:6767 \
  -e PASEO_PASSWORD="change-me" \
  -v /data/paseo:/home/paseo \
  ghcr.io/pikapeek/paseo:latest
```

Open `http://localhost:6767`, enter `PASEO_PASSWORD`. For compose, a full pre-commented template: [`docker-compose.yml`](docker-compose.yml).

## Optional tools

Every tool is off by default. Add its `-e` variables to the run command.

### AI coding agents

| Tool | Enable | API key | Model | Version |
|------|--------|---------|-------|---------|
| Claude Code | `INSTALL_CLAUDE=true` | `CLAUDE_API_KEY` | `CLAUDE_MODEL` (+ `CLAUDE_OPUS_MODEL`/`CLAUDE_SONNET_MODEL`/`CLAUDE_HAIKU_MODEL`) | `CLAUDE_VERSION` |
| Codex | `INSTALL_CODEX=true` | `CODEX_API_KEY` | `CODEX_MODEL` (+ `CODEX_REVIEW_MODEL`) | `CODEX_VERSION` |
| OpenCode | `INSTALL_OPENCODE=true` | `OPENCODE_API_KEY` | `OPENCODE_MODEL` (+ `OPENCODE_SMALL_MODEL`) | `OPENCODE_VERSION` |

Endpoints default to the official APIs — override with `CLAUDE_BASE_URL` / `CODEX_BASE_URL` / `OPENCODE_BASE_URL`. OpenCode models use `provider/model` format (`OPENCODE_MODEL=deepseek/deepseek-chat`); set `OPENCODE_PROVIDER=anthropic` for Anthropic-compatible endpoints.

### Development tooling

| Tool | Enable | Credential | Version |
|------|--------|-----------|---------|
| OpenSpec | `INSTALL_OPENSPEC=true` | — | `OPENSPEC_VERSION` |
| Go | `INSTALL_GO=true` | — | `GO_VERSION` |
| Flutter | `INSTALL_FLUTTER=true` | — | `FLUTTER_VERSION` |
| gh (GitHub CLI) | `INSTALL_GH=true` | `GITHUB_TOKEN` | — |

Unspecified version = latest.

## Network permissions (optional)

For agents that build VPNs, change network interfaces, or run `ping`/`tcpdump`. Disabled by default:

- `cap_add: [NET_ADMIN, NET_RAW]` — manage routes/firewall, raw sockets
- `devices: [/dev/net/tun]` — VPN tunnels (WireGuard / OpenVPN)
- `sysctls: [net.ipv6.conf.*.disable_ipv6=0]` — enable IPv6

Full syntax in [`docker-compose.yml`](docker-compose.yml). ⚠️ Weakens container isolation — enable only when needed.

## GitHub Token

For cloning repositories. Create at [GitHub → Settings → Developer settings → Fine-grained tokens](https://github.com/settings/tokens?type=beta): `Repository access: All repositories` + `Contents: Read-only`. Set `GITHUB_TOKEN` (with `INSTALL_GH=true`).

## OpenSpec

Spec-driven development. `INSTALL_OPENSPEC=true`, run `openspec init`, then use `/opsx:explore`, `/opsx:propose`, `/opsx:apply`, `/opsx:archive` in Claude Code.

## Other environment variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PASEO_PASSWORD` | Connection password (**required**) | — |
| `PASEO_HOSTNAMES` | Host header allowlist (`true` = allow any; ⚠️ set specific domains instead of `true` for public deployments) | `true` |

## References

- [getpaseo/paseo](https://github.com/getpaseo/paseo) — Multi-agent orchestration CLI
- [anthropics/claude-code](https://github.com/anthropics/claude-code) — Claude Code
- [openai/codex](https://github.com/openai/codex) — OpenAI Codex
- [sst/opencode](https://github.com/sst/opencode) — OpenCode
- [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec) — Spec-driven development
- [go.dev](https://go.dev) — Go
- [flutter.dev](https://flutter.dev) — Flutter
