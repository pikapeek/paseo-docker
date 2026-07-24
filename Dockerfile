# =====================================================
# Paseo + Claude Code Docker 镜像
# 基于官方 Paseo 镜像，预装 Claude Code，支持自定义 API
# =====================================================

FROM ghcr.io/getpaseo/paseo:latest

USER root

# 安装 Claude Code + GitHub CLI
RUN npm install -g @anthropic-ai/claude-code && \
    claude --version

# 安装 gh CLI（Paseo clone 需要）
RUN apt-get update && \
    apt-get install -y --no-install-recommends gh && \
    rm -rf /var/lib/apt/lists/*

# ---- Claude Code 自定义 API ----
# 通过 -e 运行时注入: ANTHROPIC_BASE_URL, ANTHROPIC_AUTH_TOKEN 等
ENV ANTHROPIC_BASE_URL=https://api.anthropic.com
ENV CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

# ---- OpenSpec ----
RUN npm install -g @fission-ai/openspec@latest && \
    openspec --version

# 允许任意 Host header
ENV PASEO_HOSTNAMES=true

# 保持 root，官方 entrypoint 会自动切换到 paseo 用户运行 daemon

# 包装 entrypoint：打印版本信息 → 交给官方 entrypoint
COPY docker-entrypoint.sh /usr/local/bin/paseo-cc-entrypoint.sh
RUN chmod +x /usr/local/bin/paseo-cc-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/paseo-cc-entrypoint.sh"]
