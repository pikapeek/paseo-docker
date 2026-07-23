# =====================================================
# Paseo + Claude Code Docker 镜像
# 基于官方 Paseo 镜像，预装 Claude Code，支持自定义 API
# =====================================================

FROM ghcr.io/getpaseo/paseo:latest

USER root

# 安装 Claude Code
RUN npm install -g @anthropic-ai/claude-code && \
    claude --version

# ---- Claude Code 自定义 API 环境变量 ----
ENV ANTHROPIC_AUTH_TOKEN=
ENV ANTHROPIC_BASE_URL=https://api.anthropic.com
ENV ANTHROPIC_MODEL=claude-sonnet-4-6
ENV ANTHROPIC_OPUS_MODEL=claude-opus-4-8
ENV ANTHROPIC_SONNET_MODEL=claude-sonnet-4-6
ENV ANTHROPIC_HAIKU_MODEL=claude-haiku-4-5
ENV CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

# 允许任意 Host header（Docker 部署通过宿主机 IP/域名访问时需要）
ENV PASEO_HOSTNAMES=true

# 保持 root，官方 entrypoint 会自动切换到 paseo 用户运行 daemon

# 包装 entrypoint：打印版本信息 → 交给官方 entrypoint
COPY docker-entrypoint.sh /usr/local/bin/paseo-cc-entrypoint.sh
RUN chmod +x /usr/local/bin/paseo-cc-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/paseo-cc-entrypoint.sh"]
