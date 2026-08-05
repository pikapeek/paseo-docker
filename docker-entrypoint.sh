#!/bin/bash
# Paseo wrapper entrypoint — start tools in background, hand off to daemon ASAP.

# Install optional tools asynchronously (nohup). Paseo starts immediately.
# Progress: docker logs -f paseo
if [[ -x /usr/local/bin/install-optionals.sh ]]; then
  nohup /usr/local/bin/install-optionals.sh 2>&1 | tee /home/paseo/install-optionals.log &
fi

# Volume-persisted tool paths (all under /home/paseo/tool)
LOCAL="${PASEO_HOME:-/home/paseo}/tool"
export PATH="${LOCAL}/bin:$PATH"

[[ -x "${LOCAL}/go/bin/go" ]]         && export GOROOT="${LOCAL}/go" PATH="${LOCAL}/go/bin:$PATH"
[[ -x "${LOCAL}/flutter/bin/flutter" ]] && export PATH="${LOCAL}/flutter/bin:$PATH"

# Export per-tool API keys so daemon + agents inherit them.
[[ -n "${CODEX_API_KEY:-}" ]]    && export CODEX_API_KEY
[[ -n "${CLAUDE_API_KEY:-}" ]]   && export CLAUDE_API_KEY
[[ -n "${OPENCODE_API_KEY:-}" ]] && export OPENCODE_API_KEY

# GitHub token → gh credential helper (for paseo user).
if [[ -n "${GITHUB_TOKEN:-}" ]] && command -v gh >/dev/null 2>&1; then
  gosu paseo gh auth setup-git --hostname github.com 2>/dev/null || true
fi

exec /usr/bin/tini -- /usr/local/bin/paseo-docker-entrypoint "$@"