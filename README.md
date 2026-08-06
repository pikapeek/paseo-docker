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

> Custom port: with host networking (`--network host`), set `-e PASEO_LISTEN=0.0.0.0:8080` to listen on your own port — no `-p` mapping needed.

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
| Python | `INSTALL_PYTHON=true` | — | — |
| Go | `INSTALL_GO=true` | — | `GO_VERSION` |
| Flutter | `INSTALL_FLUTTER=true` | — | `FLUTTER_VERSION` |
| gh (GitHub CLI) | `INSTALL_GH=true` | `GITHUB_TOKEN` | — |

Unspecified version = latest.

## Mirror / Proxy

Override download sources for restricted networks:

| Variable | Description | Default |
|----------|-------------|---------|
| `NPM_REGISTRY` | npm registry URL | `https://registry.npmjs.org` |
| `GO_MIRROR_URL` | Go download base (e.g. `https://mirrors.ustc.edu.cn/golang`) | `https://go.dev/dl` |
| `FLUTTER_MIRROR` | Flutter download base (e.g. `https://storage.flutter-io.cn`) | `https://storage.googleapis.com` |
| `GH_MIRROR_URL` | gh .deb download base (e.g. `https://mirror.ghproxy.com/https://github.com`) | `https://github.com` |
| `DOWNLOAD_PROXY` | curl download proxy, supports HTTP/SOCKS5 (e.g. `socks5://127.0.0.1:1080`) | — |

## Network permissions (optional)

For agents that build VPNs, change network interfaces, or run `ping`/`tcpdump`. Disabled by default:

- `cap_add: [NET_ADMIN, NET_RAW]` — manage routes/firewall, raw sockets
- `devices: [/dev/net/tun]` — VPN tunnels (WireGuard / OpenVPN)
- `sysctls: [net.ipv6.conf.*.disable_ipv6=0]` — enable IPv6

> ⚠️ **IPv6 sysctls conflict with host networking**: When using `network_mode: host`, Docker applies sysctls to the **host** kernel. If the host has IPv6 disabled (`disable_ipv6=1`), the container's `sysctls: [net.ipv6.conf.*.disable_ipv6=0]` WILL cause the container to fail. Solutions:
> 1. Use `cap_add: NET_ADMIN` instead of `network_mode: host`
> 2. Enable IPv6 on the host first, then uncomment the sysctls
> 3. Leave IPv6 sysctls off (Paseo doesn't require IPv6)

Full syntax in [`docker-compose.yml`](docker-compose.yml). ⚠️ Weakens container isolation — enable only when needed.

## GitHub Token

For cloning repositories. Create at [GitHub → Settings → Developer settings → Fine-grained tokens](https://github.com/settings/tokens?type=beta): `Repository access: All repositories` + `Contents: Read-only`. Set `GITHUB_TOKEN` (with `INSTALL_GH=true`).

## OpenSpec

Spec-driven development. `INSTALL_OPENSPEC=true`, run `openspec init`, then use `/opsx:explore`, `/opsx:propose`, `/opsx:apply`, `/opsx:archive` in Claude Code.

## Other environment variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PASEO_PASSWORD` | Connection password (**required**) | — |
| `PASEO_LISTEN` | Listen address & port (custom port on host networking, e.g. `PASEO_LISTEN=0.0.0.0:8080`) | `0.0.0.0:6767` |
| `PASEO_HOSTNAMES` | Host header allowlist (`true` = allow any; ⚠️ set specific domains instead of `true` for public deployments) | `true` |
| `PASEO_LOG_LEVEL` | Daemon log level (`trace`/`debug`/`info`/`warn`/`error`/`silent`). Set to `error` to silence noisy metrics output in `docker logs` | `info` |

## References

- [getpaseo/paseo](https://github.com/getpaseo/paseo) — Multi-agent orchestration CLI
- [anthropics/claude-code](https://github.com/anthropics/claude-code) — Claude Code
- [openai/codex](https://github.com/openai/codex) — OpenAI Codex
- [sst/opencode](https://github.com/sst/opencode) — OpenCode
- [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec) — Spec-driven development
- [go.dev](https://go.dev) — Go
- [flutter.dev](https://flutter.dev) — Flutter
