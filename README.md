# Paseo + Optional Tools

[Paseo](https://github.com/getpaseo/paseo) with several AI coding tools pre-integrated. The image starts minimal — just Paseo — and installs whichever tool you need at container startup via an environment variable. Claude Code, Codex, and OpenCode get their API keys and model selection written into their configs automatically, so they work immediately after install.

[中文说明](README.zh-CN.md)

## Quick start

```bash
docker pull ghcr.io/pikapeek/paseo:latest

docker run -d --name paseo \
  --restart unless-stopped \
  -p 6767:6767 \
  -e PASEO_PASSWORD="change-me" \
  -v /data/paseo:/home/paseo \
  ghcr.io/pikapeek/paseo:latest
```

Open `http://localhost:6767` and enter `PASEO_PASSWORD` to connect.

> For compose, a full template (every option pre-commented) is at [`docker-compose.yml`](docker-compose.yml).

## Enable AI tools

Add `-e VARIABLE=value` to your run command. Each tool is off by default; set the matching `INSTALL_*` flag and provide its API key.

| Tool | Enable | Key | Model (optional) | Version (optional) |
|------|--------|-----|------------------|--------------------|
| Claude Code | `INSTALL_CLAUDE=true` | `CLAUDE_API_KEY` | `CLAUDE_MODEL` main; `CLAUDE_OPUS_MODEL`/`CLAUDE_SONNET_MODEL`/`CLAUDE_HAIKU_MODEL` sub-slots | `CLAUDE_VERSION` |
| Codex | `INSTALL_CODEX=true` | `CODEX_API_KEY` | `CODEX_MODEL` main; `CODEX_REVIEW_MODEL` review | `CODEX_VERSION` |
| OpenCode | `INSTALL_OPENCODE=true` | `OPENCODE_API_KEY` | `OPENCODE_MODEL` main; `OPENCODE_SMALL_MODEL` light | `OPENCODE_VERSION` |
| OpenSpec | `INSTALL_OPENSPEC=true` | — | — | `OPENSPEC_VERSION` |
| Go | `INSTALL_GO=true` | — | — | `GO_VERSION` |
| Flutter | `INSTALL_FLUTTER=true` | — | — | `FLUTTER_VERSION` |
| gh (GitHub CLI) | `INSTALL_GH=true` | `GITHUB_TOKEN` | — | — |

Unspecified version = latest.

**Custom API endpoint** — Claude Code: `CLAUDE_BASE_URL`, Codex: `CODEX_BASE_URL`, OpenCode: `OPENCODE_BASE_URL`. Defaults to the official APIs.

**OpenCode model format** — `provider/model`, e.g. DeepSeek: `OPENCODE_MODEL=deepseek/deepseek-chat`. For an Anthropic-compatible endpoint set `OPENCODE_PROVIDER=anthropic`.

**Example** — Claude Code + Go:

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

## Network permissions (optional)

Agents occasionally need to build VPNs, change network interfaces, or run `ping`/`tcpdump` inside the container. These need extra privileges, disabled by default:

- `cap_add: [NET_ADMIN, NET_RAW]` — manage routes/firewall, raw sockets
- `devices: [/dev/net/tun]` — VPN tunnels (WireGuard / OpenVPN)
- `sysctls: [net.ipv6.conf.*.disable_ipv6=0]` — enable IPv6 in the container

Full syntax is in [`docker-compose.yml`](docker-compose.yml). ⚠️ These privileges weaken container isolation — enable only when needed.

## GitHub Token

Paseo uses this to clone repositories. Create one at [GitHub → Settings → Developer settings → Fine-grained tokens](https://github.com/settings/tokens?type=beta) with `Repository access: All repositories` + `Contents: Read-only`, and set `GITHUB_TOKEN` (with `INSTALL_GH=true`).

## OpenSpec

Spec-driven development. Enable with `INSTALL_OPENSPEC=true`, run `openspec init` in your project, then use `/opsx:explore`, `/opsx:propose`, `/opsx:apply`, `/opsx:archive` in Claude Code for the plan → propose → implement → archive workflow.

## Other environment variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PASEO_PASSWORD` | Connection password (**required**) | — |
| `PASEO_HOSTNAMES` | Allowed Host headers | `true` |

## References

- [getpaseo/paseo](https://github.com/getpaseo/paseo) — Multi-agent orchestration CLI
- [anthropics/claude-code](https://github.com/anthropics/claude-code) — Claude Code
- [openai/codex](https://github.com/openai/codex) — OpenAI Codex
- [sst/opencode](https://github.com/sst/opencode) — OpenCode
- [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec) — Spec-driven development
- [go.dev](https://go.dev) — Go
- [flutter.dev](https://flutter.dev) — Flutter
