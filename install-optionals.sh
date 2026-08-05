#!/bin/bash
#
# install-optionals.sh — optional-tool bootstrap for the Paseo Docker image.
#
# Runs as ROOT at container startup, BEFORE the official entrypoint drops
# privileges to the `paseo` user. Env-driven and idempotent. Per-tool
# failures are logged and skipped; the daemon always boots.
#
#   INSTALL_CLAUDE   (CLAUDE_VERSION)   npm @anthropic-ai/claude-code
#   INSTALL_OPENSPEC (OPENSPEC_VERSION) npm @fission-ai/openspec
#   INSTALL_CODEX    (CODEX_VERSION)    npm @openai/codex
#   INSTALL_OPENCODE (OPENCODE_VERSION) npm opencode-ai
#   INSTALL_GO       (GO_VERSION)       go.dev official tarball
#   INSTALL_GH                          apt-get install gh
#
# Semantics:
#   * Flag value must be "true" (or "1") to enable.
#   * A tool already installed is skipped (unless a pinned, different
#     version is requested).
#   * A failing tool is logged and skipped; boot never aborts.
#
# API credentials for claude / codex / opencode are read from standard
# environment variables and written into each tool's config file (owned by
# the `paseo` user), so a runtime-installed agent uses them immediately.

set -u

PASEO_UID="${PASEO_UID:-1000}"
PASEO_GID="${PASEO_GID:-1000}"
PASEO_HOME="${PASEO_HOME:-/home/paseo}"

NPM_ARGS=(--no-audit --no-fund --cache "${NPM_CACHE_DIR:-/tmp/npm-cache}")

inf() { echo "  [optional] $*"; }
ok()  { echo "  [optional] $1 -> $2"; }
bad() { echo "  [optional] $1 -> FAILED (continuing): $2" >&2; }

have() { command -v "$1" >/dev/null 2>&1; }

# Make a file/dir owned by the paseo user (when running as root).
own_as_paseo() { chown -R "${PASEO_UID}:${PASEO_GID}" "$1" 2>/dev/null || true; }

# True => skip install (already present and acceptable).
skip_ok() {
  local bin="$1" want="${2:-latest}" have_ver
  have "$bin" || return 1
  [[ "$want" == "latest" || -z "$want" ]] && return 0
  have_ver="$("$bin" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  [[ "$have_ver" == "$want" ]] && return 0
  return 1
}

# ---- npm-based tools (claude / openspec / codex / opencode) ----
install_npm_tool() { # $1=flag $2=binary $3=package $4=version
  local flag="${1:-}" bin="$2" pkg="$3" ver="${4:-latest}" spec
  [[ "$flag" == "true" || "$flag" == "1" ]] || return 0
  if skip_ok "$bin" "$ver"; then
    ok "$bin" "already installed (skipped)"
    return 0
  fi
  spec="$pkg@$ver"
  inf "installing $spec via npm (global, as root)..."
  if npm install -g "${NPM_ARGS[@]}" "$spec" >/dev/null; then
    ok "$bin" "$("$bin" --version 2>/dev/null | head -1)"
  else
    bad "$bin" "npm install returned non-zero"
  fi
}

# ---- Go toolchain (official tarball) ----
install_go() {
  [[ "${INSTALL_GO:-}" == "true" || "${INSTALL_GO:-}" == "1" ]] || return 0
  local ver="${GO_VERSION:-1.26.5}" arch go_root=/usr/local/go
  if [[ -x "$go_root/bin/go" ]] && "$go_root/bin/go" version | grep -qE "go$ver([^0-9]|$)"; then
    ok go "already installed (skipped)"
    return 0
  fi
  case "$(uname -m)" in
    x86_64|amd64)  arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    armv7l|armhf)  arch=armv6l ;;
    *) bad go "unsupported architecture: $(uname -m)"; return 1 ;;
  esac
  local url="https://go.dev/dl/go${ver}.linux-${arch}.tar.gz"
  local tmp; tmp="$(mktemp -d)"
  inf "downloading ${url} ..."
  if ! curl -fsSL "$url" -o "$tmp/go.tgz"; then
    bad go "download failed: $url"; rm -rf "$tmp"; return 1
  fi
  inf "extracting to $go_root ..."
  rm -rf "$go_root"
  if ! tar -C /usr/local -xzf "$tmp/go.tgz"; then
    bad go "extract failed"; rm -rf "$tmp"; return 1
  fi
  rm -rf "$tmp"
  # PATH/GOROOT for interactive/login shells.
  cat > /etc/profile.d/paseo-go.sh <<'EOF'
export GOROOT=/usr/local/go
export PATH="$GOROOT/bin:$PATH"
EOF
  chmod 644 /etc/profile.d/paseo-go.sh
  ok go "$("$go_root/bin/go" version 2>&1)"
}

# ---- GitHub CLI (needs apt) ----
install_gh() {
  [[ "${INSTALL_GH:-}" == "true" || "${INSTALL_GH:-}" == "1" ]] || return 0
  have gh && { ok gh "already installed (skipped)"; return 0; }
  inf "installing gh via apt-get (as root)..."
  if apt-get update >/dev/null && \
     apt-get install -y --no-install-recommends gh >/dev/null; then
    ok gh "$(gh --version 2>/dev/null | head -1)"
  else
    bad gh "apt-get install returned non-zero"
  fi
}

# ---- Claude Code API config (~/.claude/settings.json) ----
# Uses CLAUDE_API_KEY + CLAUDE_BASE_URL (per-tool, independent). Values are
# written directly into settings.json so a runtime-installed claude works
# without any exported env vars.
configure_claude() {
  have claude || return 0
  local dir="${PASEO_HOME}/.claude"
  local cfg="$dir/settings.json"
  local base="${CLAUDE_BASE_URL:-}"
  local tok="${CLAUDE_API_KEY:-}"
  local model="${CLAUDE_MODEL:-}"
  local opus="${CLAUDE_OPUS_MODEL:-}"
  local sonnet="${CLAUDE_SONNET_MODEL:-}"
  local haiku="${CLAUDE_HAIKU_MODEL:-}"
  [[ -n "$tok" ]] || return 0
  mkdir -p "$dir"
  {
    printf '{\n  "env": {\n'
    if [[ -n "$base" ]]; then
      printf '    "ANTHROPIC_BASE_URL": "%s",\n' "$base"
    fi
    if [[ -n "$model" ]]; then
      printf '    "ANTHROPIC_MODEL": "%s",\n' "$model"
    fi
    if [[ -n "$opus" ]]; then
      printf '    "ANTHROPIC_DEFAULT_OPUS_MODEL": "%s",\n' "$opus"
    fi
    if [[ -n "$sonnet" ]]; then
      printf '    "ANTHROPIC_DEFAULT_SONNET_MODEL": "%s",\n' "$sonnet"
    fi
    if [[ -n "$haiku" ]]; then
      printf '    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "%s",\n' "$haiku"
    fi
    printf '    "ANTHROPIC_API_KEY": "%s"\n' "$tok"
    printf '  }\n}\n'
  } > "$cfg"
  own_as_paseo "$dir"
  ok "claude-config" "wrote $cfg"
}

# ---- Codex CLI API config (~/.codex/config.toml) ----
# Uses CODEX_API_KEY + CODEX_BASE_URL (per-tool, independent). Codex's
# config.toml references the API key by env var name via `env_key`, so the
# entrypoint must also export CODEX_API_KEY (see docker-entrypoint.sh).
configure_codex() {
  have codex || return 0
  local dir="${PASEO_HOME}/.codex"
  local cfg="$dir/config.toml"
  local key="${CODEX_API_KEY:-}"
  local base="${CODEX_BASE_URL:-}"
  local model="${CODEX_MODEL:-}"
  local review="${CODEX_REVIEW_MODEL:-}"
  [[ -n "$key" ]] || return 0
  mkdir -p "$dir"
  # Default to official OpenAI endpoint when no custom base URL is set.
  if [[ -z "$base" ]]; then
    base="https://api.openai.com/v1"
  fi
  {
    cat <<EOF
model_provider = "custom"
EOF
    if [[ -n "$model" ]]; then
      echo "model = \"${model}\""
    fi
    if [[ -n "$review" ]]; then
      echo "review_model = \"${review}\""
    fi
    cat <<EOF

[model_providers.custom]
name = "custom"
base_url = "${base}"
wire_api = "chat"
env_key = "CODEX_API_KEY"
EOF
  } > "$cfg"
  own_as_paseo "$dir"
  ok "codex-config" "wrote $cfg"
}

# ---- OpenCode API config (auth.json + opencode.json) ----
# Uses OPENCODE_API_KEY + OPENCODE_BASE_URL (per-tool, independent).
# auth.json stores `{ "<provider-id>": { "type": "api", "key": "..." } }`
# under ~/.local/share/opencode. baseURL is configured via the provider
# table in opencode.json (provider.<name>.options.baseURL). The key value is
# written directly into auth.json (no exported env needed).
configure_opencode() {
  have opencode || return 0
  local data="${PASEO_HOME}/.local/share/opencode"
  local auth="$data/auth.json"
  local key="${OPENCODE_API_KEY:-}"
  local base="${OPENCODE_BASE_URL:-}"
  local model="${OPENCODE_MODEL:-}"
  local small="${OPENCODE_SMALL_MODEL:-}"
  local provider="${OPENCODE_PROVIDER:-openai}"
  [[ -n "$key" ]] || return 0
  mkdir -p "$data"
  # auth.json — keyed by provider id. OPENCODE_PROVIDER controls which
  # provider the key is stored under (default: openai). Set to "anthropic"
  # if you connect to an Anthropic-compatible endpoint.
  {
    printf '{\n  "%s": {\n    "type": "api",\n    "key": "%s"\n  }\n}\n' \
      "$provider" "$key"
  } > "$auth"
  chmod 600 "$auth"
  own_as_paseo "$data"
  # opencode.json — global config dir is $XDG_CONFIG_HOME/opencode
  # (base image sets XDG_CONFIG_HOME=/home/paseo/.config). Provider baseURL
  # lives in the `provider` table here; model is top-level "provider/model".
  local cfgdir="${XDG_CONFIG_HOME:-${PASEO_HOME}/.config}/opencode"
  mkdir -p "$cfgdir"
  local cfg="$cfgdir/opencode.json"
  {
    printf '{\n'
    if [[ -n "$model" ]]; then
      printf '  "model": "%s",\n' "$model"
    fi
    if [[ -n "$small" ]]; then
      printf '  "small_model": "%s",\n' "$small"
    fi
    printf '  "provider": {\n    "%s": {\n' "$provider"
    if [[ -n "$base" ]]; then
      printf '      "options": {\n        "baseURL": "%s"\n      }\n' "$base"
    fi
    printf '    }\n  }\n}\n'
  } > "$cfg"
  own_as_paseo "$cfgdir"
  ok "opencode-config" "wrote auth.json + opencode.json ($provider)"
}

# ---- main ----
install_npm_tool "${INSTALL_CLAUDE:-}"   claude    @anthropic-ai/claude-code "${CLAUDE_VERSION:-latest}"
install_npm_tool "${INSTALL_OPENSPEC:-}" openspec  @fission-ai/openspec      "${OPENSPEC_VERSION:-latest}"
install_npm_tool "${INSTALL_CODEX:-}"    codex     @openai/codex             "${CODEX_VERSION:-latest}"
install_npm_tool "${INSTALL_OPENCODE:-}" opencode  opencode-ai               "${OPENCODE_VERSION:-latest}"
install_go
install_gh

configure_claude
configure_codex
configure_opencode

# NOTE: Go env for the daemon is exported by paseo-cc-entrypoint.sh, not here
# (child-process exports do not propagate back).
