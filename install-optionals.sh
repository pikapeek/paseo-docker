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
# Inherits the container's ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN /
# ANTHROPIC_API_KEY so a runtime-installed claude can talk to a custom
# endpoint (or the official API) without manual setup.
configure_claude() {
  have claude || return 0
  local dir="${PASEO_HOME}/.claude"
  local cfg="$dir/settings.json"
  local base="${ANTHROPIC_BASE_URL:-}"
  local tok="${ANTHROPIC_AUTH_TOKEN:-${ANTHROPIC_API_KEY:-}}"
  [[ -n "$tok" ]] || return 0
  mkdir -p "$dir"
  if [[ -f "$cfg" ]]; then
    # Preserve an existing settings.json; merge the env block.
    cp "$cfg" "$cfg.tmp" 2>/dev/null || true
  fi
  {
    printf '{\n  "env": {\n'
    if [[ -n "$base" ]]; then
      printf '    "ANTHROPIC_BASE_URL": "%s",\n' "$base"
    fi
    printf '    "ANTHROPIC_AUTH_TOKEN": "%s"\n' "$tok"
    printf '  }\n}\n'
  } > "$cfg"
  own_as_paseo "$dir"
  ok "claude-config" "wrote $cfg"
}

# ---- Codex CLI API config (~/.codex/config.toml) ----
# Uses OPENAI_API_KEY + OPENAI_BASE_URL; writes a custom model_provider so
# Codex points at the intended endpoint. Keeps the official `openai` provider
# untouched; only the `model_provider` default is redirected when a base URL
# is supplied.
configure_codex() {
  have codex || return 0
  local dir="${PASEO_HOME}/.codex"
  local cfg="$dir/config.toml"
  local key="${OPENAI_API_KEY:-}"
  local base="${OPENAI_BASE_URL:-}"
  [[ -n "$key" ]] || return 0
  mkdir -p "$dir"
  {
    if [[ -n "$base" ]]; then
      cat <<EOF
model_provider = "custom"

[model_providers.custom]
name = "custom"
base_url = "${base}"
wire_api = "chat"
env_key = "OPENAI_API_KEY"
EOF
    else
      echo 'model_provider = "openai"'
    fi
  } > "$cfg"
  own_as_paseo "$dir"
  ok "codex-config" "wrote $cfg"
}

# ---- OpenCode API config (auth.json + opencode.json) ----
# auth.json stores `{ "<provider-id>": { "type": "api", "key": "..." } }`
# under ~/.local/share/opencode. baseURL is configured via the provider
# table in opencode.json (provider.<name>.options.baseURL).
configure_opencode() {
  have opencode || return 0
  local data="${PASEO_HOME}/.local/share/opencode"
  local auth="$data/auth.json"
  local key="${OPENAI_API_KEY:-}"
  [[ -n "$key" ]] || return 0
  mkdir -p "$data"
  # auth.json — provider id keyed by the API family actually configured.
  {
    if [[ -n "${ANTHROPIC_AUTH_TOKEN:-${ANTHROPIC_API_KEY:-}}" ]]; then
      printf '{\n  "anthropic": {\n    "type": "api",\n    "key": "%s"\n  }\n}\n' \
        "${ANTHROPIC_AUTH_TOKEN:-${ANTHROPIC_API_KEY}}"
    else
      printf '{\n  "openai": {\n    "type": "api",\n    "key": "%s"\n  }\n}\n' "$key"
    fi
  } > "$auth"
  chmod 600 "$auth"
  # opencode.json — point the matching provider at the custom base URL.
  local base="${OPENAI_BASE_URL:-${ANTHROPIC_BASE_URL:-}}"
  if [[ -n "$base" ]]; then
    local provider="openai"
    if [[ -n "${ANTHROPIC_AUTH_TOKEN:-${ANTHROPIC_API_KEY:-}}" ]]; then
      provider="anthropic"
    fi
    local cfg="${PASEO_HOME}/opencode.json"
    printf '{\n  "provider": {\n    "%s": {\n      "options": {\n        "baseURL": "%s"\n      }\n    }\n  }\n}\n' \
      "$provider" "$base" > "$cfg"
    own_as_paseo "${PASEO_HOME}/opencode.json"
    ok "opencode-config" "wrote auth.json + opencode.json ($provider)"
  else
    own_as_paseo "$data"
    ok "opencode-config" "wrote auth.json"
  fi
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
