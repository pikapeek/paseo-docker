# =====================================================
# Paseo Docker image — minimal base + OPTIONAL tools
# Base ships only paseo. Claude Code / OpenSpec / Codex /
# OpenCode / Go / gh are installed at CONTAINER STARTUP
# (as root) when the matching INSTALL_* env var is set.
# Version is pinned via the companion *_VERSION var
# (default: latest).
# =====================================================

FROM ghcr.io/getpaseo/paseo:latest

USER root

# ---- Optional-tool install flags (default: OFF) ----
ENV INSTALL_CLAUDE=""
ENV INSTALL_OPENSPEC=""
ENV INSTALL_CODEX=""
ENV INSTALL_OPENCODE=""
ENV INSTALL_GO=""
ENV INSTALL_FLUTTER=""
ENV INSTALL_GH=""

ENV CLAUDE_VERSION="latest"
ENV OPENSPEC_VERSION="latest"
ENV CODEX_VERSION="latest"
ENV OPENCODE_VERSION="latest"
ENV GO_VERSION="latest"
ENV FLUTTER_VERSION="latest"

# ---- Per-tool API credentials (independent) ----
# Each AI tool is configured with its own key + base URL. Version pins above
# select the version; the *_BASE_URL / *_API_KEY vars configure it.
ENV CLAUDE_BASE_URL="https://api.anthropic.com"
ENV CODEX_BASE_URL=""
ENV OPENCODE_BASE_URL=""
ENV OPENCODE_PROVIDER="openai"
ENV CLAUDE_MODEL=""
ENV CLAUDE_OPUS_MODEL=""
ENV CLAUDE_SONNET_MODEL=""
ENV CLAUDE_HAIKU_MODEL=""
ENV CODEX_MODEL=""
ENV CODEX_REVIEW_MODEL=""
ENV OPENCODE_MODEL=""
ENV OPENCODE_SMALL_MODEL=""
ENV CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

# Allow any Host header
ENV PASEO_HOSTNAMES=true

# Wrapper entrypoint: install optional tools (root) -> banner -> official
# entrypoint (drops to paseo user via gosu).
# Give paseo user passwordless sudo for agent operations (install pkgs, etc.).
COPY docker-entrypoint.sh /usr/local/bin/paseo-cc-entrypoint.sh
COPY install-optionals.sh /usr/local/bin/install-optionals.sh
# sudo needed for paseo user agents (install pkgs, manage network, etc.)
RUN apt-get update && \
    apt-get install -y --no-install-recommends sudo && \
    rm -rf /var/lib/apt/lists/* && \
    echo "paseo ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/paseo && \
    chmod 440 /etc/sudoers.d/paseo && \
    chmod +x /usr/local/bin/paseo-cc-entrypoint.sh \
             /usr/local/bin/install-optionals.sh
ENTRYPOINT ["/usr/local/bin/paseo-cc-entrypoint.sh"]
