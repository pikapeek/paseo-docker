#!/bin/bash
# Paseo + Claude Code wrapper entrypoint
# Prints version info, warns about missing config, then hands off to official entrypoint

echo "=============================================="
echo "  Paseo + Claude Code"
echo "=============================================="
echo "  Paseo:       $(paseo --version 2>&1 || echo 'N/A')"
echo "  Claude Code: $(claude --version 2>&1 || echo 'N/A')"

if [ -n "${ANTHROPIC_BASE_URL:-}" ] && [ "${ANTHROPIC_BASE_URL}" != "https://api.anthropic.com" ]; then
    echo "  API:         ${ANTHROPIC_BASE_URL}"
fi

if [ -z "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
    echo "  ---"
    echo "  WARNING: ANTHROPIC_AUTH_TOKEN is not set!"
    echo "  Set it via: -e ANTHROPIC_AUTH_TOKEN=<your-token>"
fi

echo "=============================================="
echo ""

exec /usr/bin/tini -- /usr/local/bin/paseo-docker-entrypoint "$@"
