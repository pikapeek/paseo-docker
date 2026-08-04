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

# Optional-tool installs run as root, BEFORE the gosu drop. Tools that fail
# to install are logged and skipped; boot always continues.
if [[ -x /usr/local/bin/install-optionals.sh ]]; then
  /usr/local/bin/install-optionals.sh || \
    echo "  [optional] one or more tools failed to install (see above)"
fi

# Propagate Go env to the daemon process (gosu does NOT source profile.d).
if [[ -x /usr/local/go/bin/go ]]; then
  export GOROOT=/usr/local/go
  export PATH="/usr/local/go/bin:$PATH"
fi

echo "=============================================="
probe "Paseo"       paseo
probe "Claude Code" claude
probe "OpenSpec"    openspec
probe "Codex"       codex
probe "OpenCode"    opencode
probe "Go"          go
probe "gh"          gh
echo "=============================================="

if [ -n "${ANTHROPIC_BASE_URL:-}" ] && [ "${ANTHROPIC_BASE_URL}" != "https://api.anthropic.com" ]; then
    echo "  API:         ${ANTHROPIC_BASE_URL}"
fi

if [ -z "${ANTHROPIC_AUTH_TOKEN:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    echo "  ---"
    echo "  WARNING: no Anthropic API key is set!"
    echo "  Set it via: -e ANTHROPIC_AUTH_TOKEN=<your-token>"
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