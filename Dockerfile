# =====================================================
# Paseo + Claude Code Docker 镜像
# =====================================================
# 用法:
#   docker build --build-arg PASEO_VERSION=v0.1.107 -t paseo-claude-code .
#   docker run -it --rm -e ANTHROPIC_AUTH_TOKEN=sk-xxx paseo-claude-code
# =====================================================

FROM node:22-slim

# 构建参数：Paseo 版本号（如 v0.1.107）
ARG PASEO_VERSION=latest

# 元数据标签
LABEL org.opencontainers.image.title="Paseo + Claude Code"
LABEL org.opencontainers.image.description="Pre-installed Paseo (multi-agent orchestrator) and Claude Code with custom API support"
LABEL org.opencontainers.image.source="https://github.com/getpaseo/paseo"
LABEL org.opencontainers.image.licenses="MIT"

# 安装系统依赖
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        ca-certificates \
        curl \
        ripgrep \
        fd-find \
    && rm -rf /var/lib/apt/lists/*

# 安装 Claude Code（最新稳定版）
RUN npm install -g @anthropic-ai/claude-code && \
    claude --version

# 安装 Paseo CLI（指定版本或最新版）
RUN if [ "${PASEO_VERSION}" = "latest" ]; then \
        npm install -g @getpaseo/cli; \
    else \
        npm install -g @getpaseo/cli@${PASEO_VERSION#v}; \
    fi && \
    paseo --version

# 创建工作目录
WORKDIR /workspace

# 创建数据目录
RUN mkdir -p /home/paseo

# ---- Claude Code 自定义 API 环境变量 ----
# 自定义 API 端点（默认指向 Anthropic 官方 API）
ENV ANTHROPIC_BASE_URL=https://api.anthropic.com

# API Key / Token（运行时必须提供）
ENV ANTHROPIC_AUTH_TOKEN=

# 默认模型
ENV ANTHROPIC_MODEL=claude-sonnet-4-6

# 各 tier 模型映射（使用自定义 API 时可设置为对应模型名）
ENV ANTHROPIC_OPUS_MODEL=claude-opus-4-8
ENV ANTHROPIC_SONNET_MODEL=claude-sonnet-4-6
ENV ANTHROPIC_HAIKU_MODEL=claude-haiku-4-5

# 禁用遥测和自动更新检查
ENV CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

# Paseo daemon 监听地址（0.0.0.0 允许外部访问 Dashboard）
ENV PASEO_LISTEN=0.0.0.0:6767

# 记录构建时传入的 Paseo 版本
ENV PASEO_VERSION=${PASEO_VERSION}

EXPOSE 6767

# 创建非 root 用户（可选，方便权限管理）
RUN useradd --create-home --shell /bin/bash coder
RUN chown -R coder:coder /workspace /home/paseo

# 保留 root 用户，通过 entrypoint 切换到 coder 或直接使用
# 若需要以非 root 运行，可在 docker run 时指定 --user coder

# 复制 entrypoint
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["sh", "-c", "exec paseo daemon start"]
