#!/bin/bash
# Paseo wrapper entrypoint
# 1) install optional tools as ROOT (env-driven, idempotent)
# 2) print version banner + warnings
# 3) hand off to official entrypoint (which drops to `paseo` user)

probe() { # $1=label $2=binary
  local label="$1" bin="$2"
  if command -v "$bin" >/dev/null 2>&1; then
    echo "  ${label}: $("$bin" --version 2>/dev/null | head -1)"
  else
    echo "  ${label}: not installed"
  fi
}

echo "=============================================="
echo "  Paseo (pikapeek) — optional tools"
echo "=============================================="

# Optional-tool installs run asynchronously in the background so Paseo
# starts immediately. Tools that fail are logged; boot never blocks.
# Progress: docker exec paseo tail -f /home/paseo/install-optionals.log
#   or just: docker logs -f paseo
if [[ -x /usr/local/bin/install-optionals.sh ]]; then
  nohup /usr/local/bin/install-optionals.sh 2>&1 | tee /home/paseo/install-optionals.log &
  echo "  [optional] 工具安装中，docker logs -f 可查看进度"
fi

# Propagate Go env to the daemon process (gosu does NOT source profile.d).
if [[ -x /usr/local/go/bin/go ]]; then
  export GOROOT=/usr/local/go
  export PATH="/usr/local/go/bin:$PATH"
fi

# Propagate Flutter's bin to PATH for the daemon/agents.
if [[ -x /usr/local/flutter/bin/flutter ]]; then
  export PATH="/usr/local/flutter/bin:$PATH"
fi

# Export per-tool API vars so the daemon (and any agent it spawns) inherit
# them. Codex's config.toml references CODEX_API_KEY by name via env_key, so
# it MUST be in the environment. Claude/OpenCode read their config files
# directly, but exporting is harmless and keeps agents consistent.
if [[ -n "${CODEX_API_KEY:-}" ]]; then
  export CODEX_API_KEY
fi
if [[ -n "${CLAUDE_API_KEY:-}" ]]; then
  export CLAUDE_API_KEY
fi
if [[ -n "${OPENCODE_API_KEY:-}" ]]; then
  export OPENCODE_API_KEY
fi

echo "=============================================="
probe "Paseo"       paseo
probe "Claude Code" claude
probe "OpenSpec"    openspec
probe "Codex"       codex
probe "OpenCode"    opencode
probe "Go"          go
probe "Flutter"     flutter
probe "gh"          gh
echo "=============================================="

if [ -n "${CLAUDE_API_KEY:-}" ] || [ -n "${CODEX_API_KEY:-}" ] || [ -n "${OPENCODE_API_KEY:-}" ]; then
    echo "  API keys:    claude=${CLAUDE_API_KEY:+set} codex=${CODEX_API_KEY:+set} opencode=${OPENCODE_API_KEY:+set}"
else
    echo "  WARNING: no API keys set (CLAUDE_API_KEY / CODEX_API_KEY / OPENCODE_API_KEY)"
fi

# GitHub token -> gh credential helper for the paseo user.
# Only runs when both a token is supplied AND gh is installed.
if [ -n "${GITHUB_TOKEN:-}" ] && command -v gh >/dev/null 2>&1; then
    if gosu paseo gh auth setup-git --hostname github.com 2>/dev/null; then
        echo "  GitHub:      authenticated"
    else
        echo "  GitHub:      auth failed (check GITHUB_TOKEN)"
    fi
fi

echo "=============================================="
echo ""

exec /usr/bin/tini -- /usr/local/bin/paseo-docker-entrypoint "$@"