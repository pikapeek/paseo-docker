#!/bin/bash
# Paseo wrapper entrypoint — start tools in background, write configs, hand off to daemon.

# Install optional tools asynchronously. Paseo starts immediately.
if [[ -x /usr/local/bin/install-optionals.sh ]]; then
  nohup /usr/local/bin/install-optionals.sh 2>&1 | tee /home/paseo/install-optionals.log &
fi

# Volume-persisted tool paths (all under /home/paseo/tool)
TOOL="${PASEO_HOME:-/home/paseo}/tool"
export PATH="${TOOL}/bin:$PATH"

[[ -x "${TOOL}/go/bin/go" ]]           && export GOROOT="${TOOL}/go" PATH="${TOOL}/go/bin:$PATH"
[[ -x "${TOOL}/flutter/bin/flutter" ]] && export PATH="${TOOL}/flutter/bin:$PATH"

# Export per-tool API keys so daemon + agents inherit them.
[[ -n "${CODEX_API_KEY:-}" ]]    && export CODEX_API_KEY
[[ -n "${CLAUDE_API_KEY:-}" ]]   && export CLAUDE_API_KEY
[[ -n "${OPENCODE_API_KEY:-}" ]] && export OPENCODE_API_KEY

# ---- Write API configs (synchronous, BEFORE daemon starts) ----
PASEO_HOME="${PASEO_HOME:-/home/paseo}"
_own() { chown -R "${PASEO_UID:-1000}:${PASEO_GID:-1000}" "$1" 2>/dev/null || true; }

if [[ -n "${CLAUDE_API_KEY:-}" ]]; then
  mkdir -p "${PASEO_HOME}/.claude"
  cat > "${PASEO_HOME}/.claude/settings.json" <<'SETTINGS_EOF'
{
  "env": {
SETTINGS_EOF
  printf '    "ANTHROPIC_API_KEY": "%s",\n'    "${CLAUDE_API_KEY}"
  printf '    "ANTHROPIC_BASE_URL": "%s",\n'     "${CLAUDE_BASE_URL:-https://api.anthropic.com}"
  printf '    "ANTHROPIC_MODEL": "%s",\n'        "${CLAUDE_MODEL:-}"
  printf '    "ANTHROPIC_DEFAULT_OPUS_MODEL": "%s",\n'   "${CLAUDE_OPUS_MODEL:-}"
  printf '    "ANTHROPIC_DEFAULT_SONNET_MODEL": "%s",\n' "${CLAUDE_SONNET_MODEL:-}"
  printf '    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "%s"\n'  "${CLAUDE_HAIKU_MODEL:-}"
  printf '  }\n}\n' >> "${PASEO_HOME}/.claude/settings.json"
  _own "${PASEO_HOME}/.claude"
fi

if [[ -n "${CODEX_API_KEY:-}" ]]; then
  mkdir -p "${PASEO_HOME}/.codex"
  cat > "${PASEO_HOME}/.codex/config.toml" <<CODEX_EOF
model_provider = "custom"
model = "${CODEX_MODEL:-}"
review_model = "${CODEX_REVIEW_MODEL:-}"

[model_providers.custom]
name = "custom"
base_url = "${CODEX_BASE_URL:-https://api.openai.com/v1}"
wire_api = "chat"
env_key = "CODEX_API_KEY"
CODEX_EOF
  _own "${PASEO_HOME}/.codex"
fi

if [[ -n "${OPENCODE_API_KEY:-}" ]]; then
  _oc_provider="${OPENCODE_PROVIDER:-openai}"
  mkdir -p "${PASEO_HOME}/.local/share/opencode"
  cat > "${PASEO_HOME}/.local/share/opencode/auth.json" <<AUTH_EOF
{
  "${_oc_provider}": {
    "type": "api",
    "key": "${OPENCODE_API_KEY}"
  }
}
AUTH_EOF
  chmod 600 "${PASEO_HOME}/.local/share/opencode/auth.json"
  _own "${PASEO_HOME}/.local/share/opencode"

  _oc_cfgdir="${XDG_CONFIG_HOME:-${PASEO_HOME}/.config}/opencode"
  mkdir -p "$_oc_cfgdir"
  cat > "$_oc_cfgdir/opencode.json" <<OPENCODE_EOF
{
  "model": "${OPENCODE_MODEL:-}",
  "small_model": "${OPENCODE_SMALL_MODEL:-}",
  "provider": {
    "${_oc_provider}": {
      "options": {
        "baseURL": "${OPENCODE_BASE_URL:-}"
      }
    }
  }
}
OPENCODE_EOF
  _own "$_oc_cfgdir"
fi

# GitHub token → gh credential helper (for paseo user).
if [[ -n "${GITHUB_TOKEN:-}" ]] && command -v gh >/dev/null 2>&1; then
  gosu paseo gh auth setup-git --hostname github.com 2>/dev/null || true
fi

exec /usr/bin/tini -- /usr/local/bin/paseo-docker-entrypoint "$@"