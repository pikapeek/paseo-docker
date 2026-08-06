#!/bin/bash
# Paseo wrapper entrypoint — start tools in background, write configs, hand off to daemon.
set -uo pipefail

# Install optional tools asynchronously. Paseo starts immediately.
if [[ -x /usr/local/bin/install-optionals.sh ]]; then
  nohup /usr/local/bin/install-optionals.sh 2>&1 | tee /home/paseo/install-optionals.log &
fi

# Volume-persisted tool paths (all under /home/paseo/tool)
TOOL="${PASEO_HOME:-/home/paseo}/tool"
export PATH="${TOOL}/bin:$PATH"

[[ -x "${TOOL}/go/bin/go" ]]           && export GOROOT="${TOOL}/go" PATH="${TOOL}/go/bin:$PATH"
[[ -x "${TOOL}/flutter/bin/flutter" ]] && export PATH="${TOOL}/flutter/bin:$PATH"

# ============================================================
# Credential env-var passthrough:
#   - Claude Code:  reads ANTHROPIC_API_KEY / ANTHROPIC_AUTH_TOKEN
#   - Codex:        reads OPENAI_API_KEY (our CODEX_API_KEY maps to it)
#   - OpenCode:     reads OPENAI_API_KEY / ANTHROPIC_API_KEY directly
# All three CLI's auto-detect these standard env vars; no config files needed.
# ============================================================
if [[ -n "${CLAUDE_API_KEY:-}" ]]; then
  export ANTHROPIC_API_KEY="${CLAUDE_API_KEY}"
  export ANTHROPIC_AUTH_TOKEN="${CLAUDE_API_KEY}"
fi
if [[ -n "${CODEX_API_KEY:-}" ]]; then
  export OPENAI_API_KEY="${CODEX_API_KEY}"
fi
# OpenCode uses OPENAI_API_KEY / ANTHROPIC_API_KEY — already exported above.
[[ -n "${CLAUDE_BASE_URL:-}" ]]  && export ANTHROPIC_BASE_URL="${CLAUDE_BASE_URL}"
[[ -n "${CODEX_BASE_URL:-}" ]]   && export OPENAI_BASE_URL="${CODEX_BASE_URL}"
[[ -n "${OPENCODE_BASE_URL:-}" ]] && export OPENAI_BASE_URL="${OPENCODE_BASE_URL}"


# GitHub token → gh credential helper (for paseo user).
if [[ -n "${GITHUB_TOKEN:-}" ]] && command -v gh >/dev/null 2>&1; then
  gosu paseo gh auth setup-git --hostname github.com 2>/dev/null || true
fi

exec /usr/bin/tini -- /usr/local/bin/paseo-docker-entrypoint "$@"