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
ENV INSTALL_GH=""

ENV CLAUDE_VERSION="latest"
ENV OPENSPEC_VERSION="latest"
ENV CODEX_VERSION="latest"
ENV OPENCODE_VERSION="latest"
ENV GO_VERSION="1.26.5"

# ---- Claude Code custom API ----
# Always exported (even when Claude Code is not installed) so a
# runtime-installed Claude Code inherits them. Runtime overrides via -e.
ENV ANTHROPIC_BASE_URL=https://api.anthropic.com
ENV CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

# Allow any Host header
ENV PASEO_HOSTNAMES=true

# Wrapper entrypoint: install optional tools (root) -> banner -> official
# entrypoint (drops to paseo user via gosu).
COPY docker-entrypoint.sh /usr/local/bin/paseo-cc-entrypoint.sh
COPY install-optionals.sh /usr/local/bin/install-optionals.sh
RUN chmod +x /usr/local/bin/paseo-cc-entrypoint.sh \
             /usr/local/bin/install-optionals.sh
ENTRYPOINT ["/usr/local/bin/paseo-cc-entrypoint.sh"]
