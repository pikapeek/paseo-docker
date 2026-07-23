#!/bin/bash
set -euo pipefail

# =====================================================
# Paseo + Claude Code Docker Entrypoint
# =====================================================

echo "=============================================="
echo "  Paseo + Claude Code Docker Image"
echo "=============================================="

# 打印已安装版本
echo ""
echo "Installed versions:"

if command -v paseo &> /dev/null; then
    echo "  Paseo:       $(paseo --version 2>&1 || echo 'unknown')"
else
    echo "  Paseo:       NOT INSTALLED"
fi

if command -v claude &> /dev/null; then
    echo "  Claude Code: $(claude --version 2>&1 || echo 'unknown')"
else
    echo "  Claude Code: NOT INSTALLED"
fi

echo "  Node.js:     $(node --version)"
echo "  npm:         $(npm --version)"
echo ""

# ---- 环境变量检查与提示 ----

# 检查自定义 API 配置
if [ -n "${ANTHROPIC_BASE_URL:-}" ] && [ "${ANTHROPIC_BASE_URL}" != "https://api.anthropic.com" ]; then
    echo "Using custom API endpoint: ${ANTHROPIC_BASE_URL}"
fi

if [ -z "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
    echo "-------------------------------------------------------"
    echo "  WARNING: ANTHROPIC_AUTH_TOKEN is not set!"
    echo ""
    echo "  Set it when running the container:"
    echo "    docker run -e ANTHROPIC_AUTH_TOKEN=<your-token> ..."
    echo ""
    echo "  For custom API providers, also set:"
    echo "    -e ANTHROPIC_BASE_URL=<your-api-endpoint>"
    echo "    -e ANTHROPIC_MODEL=<model-name>"
    echo "-------------------------------------------------------"
    echo ""
else
    echo "ANTHROPIC_AUTH_TOKEN is configured."
fi

echo ""
echo "=============================================="
echo ""

# 执行传入的命令，或默认为 bash
exec "$@"
