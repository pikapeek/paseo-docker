#!/bin/bash
# Paseo optional-tool installer.  AI tools first, then dev tools.
# Env-driven, idempotent — restart skips everything already installed.
set -uo pipefail

trap 'kill -TERM -- -$$ 2>/dev/null; wait' EXIT INT TERM

PASEO_HOME="${PASEO_HOME:-/home/paseo}"
LOCAL="${PASEO_HOME}/tool"
export PATH="${LOCAL}/bin:${LOCAL}/go/bin:${LOCAL}/flutter/bin:${PATH}"

RETRY_COUNT="${INSTALL_RETRY_COUNT:-3}"
RETRY_BASE_DELAY="${INSTALL_RETRY_BASE_DELAY:-2}"
NPM_ARGS=(--no-audit --no-fund --cache "${NPM_CACHE_DIR:-/tmp/npm-cache}")

declare -a TOOL_LABEL TOOL_FLAG TOOL_VER_VAR TOOL_FUNC TOOL_TYPE
TOOL_OK=0 TOOL_SKIP=0 TOOL_FAIL=0 ENABLED=0 T0=$SECONDS

# ---- helpers ----
have() { command -v "$1" >/dev/null 2>&1; }
_own() { chown -R "${PASEO_UID:-1000}:${PASEO_GID:-1000}" "$1" 2>/dev/null || true; }

# curl download: show progress bar, no verbose headers
_dl() {
  local url="$1" dest="$2" label="$3"
  local proxy_args=()
  if [[ -n "${DOWNLOAD_PROXY:-}" ]]; then
    proxy_args+=(--proxy "${DOWNLOAD_PROXY}")
    [[ "${DOWNLOAD_PROXY}" == socks* ]] && proxy_args+=(--socks5-hostname "${DOWNLOAD_PROXY#socks5://}")
  fi
  curl -fSL -C - --progress-bar --connect-timeout 30 --retry 3 --retry-delay 5 \
       "${proxy_args[@]}" "$url" -o "$dest"
}

# ---- version resolvers ----
_resolve_go()      { timeout 30 curl -fsSL --connect-timeout 10 "https://go.dev/VERSION?m=text" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1; }
_resolve_flutter() { timeout 30 curl -fsSL --connect-timeout 10 "https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json" 2>/dev/null | sed -n '/"channel"[[:space:]]*:[[:space:]]*"stable"/{n;s/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p;q}'; }
_resolve_gh()      { timeout 30 curl -fsSL --connect-timeout 10 "https://api.github.com/repos/cli/cli/releases/latest" 2>/dev/null | sed -n 's/.*"tag_name"[^"]*"\([^"]*\)".*/\1/p' | sed 's/^v//' | head -1; }

# ---- install: npm ----
_npm_install() {
  local bin="$1" pkg="$2" ver="$3"
  if [[ "$ver" == "latest" ]] && have "$bin"; then return 0; fi
  if [[ "$ver" != "latest" ]] && have "$bin" && "$bin" --version 2>/dev/null | grep -qE "${ver//./\\.}"; then return 0; fi
  mkdir -p "${LOCAL}/bin" "${LOCAL}/lib/node_modules"
  npm install -g --prefix "${LOCAL}" "${NPM_ARGS[@]}" "${pkg}@${ver}" 2>&1 | tail -1
  _own "${LOCAL}"
  have "$bin"
}

# ---- install: Go ----
_go_install() {
  local ver="$1" root="${LOCAL}/go"
  if [[ "$ver" == "latest" ]]; then
    [[ -x "$root/bin/go" ]] && return 0
    ver="$(_resolve_go)"; [[ -z "$ver" ]] && return 1
  else
    [[ -x "$root/bin/go" ]] && "$root/bin/go" version 2>/dev/null | grep -qE "go${ver//./\\.}([^0-9]|\$)" && return 0
  fi
  local arch; case "$(uname -m)" in x86_64|amd64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; armv7l|armhf) arch=armv6l ;; *) return 1 ;; esac
  local url="${GO_MIRROR_URL:-https://go.dev/dl}/go${ver}.linux-${arch}.tar.gz"
  local tmp; tmp="$(mktemp -d)"
  _dl "$url" "$tmp/go.tgz" "go" || { rm -rf "$tmp"; return 1; }
  rm -rf "$root"; mkdir -p "$(dirname "$root")"
  tar -C "${LOCAL}" -xzf "$tmp/go.tgz" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"; _own "$root"
  [[ -x "$root/bin/go" ]]
}

# ---- install: Flutter ----
_flutter_install() {
  local ver="$1" root="${LOCAL}/flutter"
  if [[ "$ver" == "latest" ]]; then
    [[ -x "$root/bin/flutter" ]] && return 0
    ver="$(_resolve_flutter)"; [[ -z "$ver" ]] && return 1
  else
    [[ -x "$root/bin/flutter" ]] && "$root/bin/flutter" --version 2>/dev/null | grep -qE "${ver//./\\.}" && return 0
  fi
  local url="${FLUTTER_MIRROR:-https://storage.googleapis.com}/flutter_infra_release/releases/stable/linux/flutter_linux_${ver}-stable.tar.xz"
  local tmp; tmp="$(mktemp -d)"
  _dl "$url" "$tmp/flutter.tar.xz" "flutter" || { rm -rf "$tmp"; return 1; }
  rm -rf "$root"; mkdir -p "$(dirname "$root")"
  tar -C "${LOCAL}" -xJf "$tmp/flutter.tar.xz" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"; _own "$root"
  "$root/bin/flutter" --version >/dev/null 2>&1
  [[ -x "$root/bin/flutter" ]]
}

# ---- install: gh ----
_gh_install() {
  local ver="$1"
  if [[ "$ver" == "latest" ]]; then
    have gh && return 0
    ver="$(_resolve_gh)"; [[ -z "$ver" ]] && return 1
  else
    have gh && gh --version 2>/dev/null | grep -qE "${ver//./\\.}" && return 0
  fi
  local url="${GH_MIRROR_URL:-https://github.com}/cli/cli/releases/download/v${ver}/gh_${ver}_linux_amd64.deb"
  local tmp; tmp="$(mktemp -d)"
  _dl "$url" "$tmp/gh.deb" "gh" || { rm -rf "$tmp"; return 1; }
  dpkg -i "$tmp/gh.deb" 2>/dev/null; rm -rf "$tmp"
  have gh
}

# ---- install: Python ----
_python_install() {
  have python3 && return 0
  apt-get update -qq && apt-get install -y --no-install-recommends python3 python3-pip >/dev/null 2>&1
  have python3
}

# ================================================================
# Tool queue
# ================================================================
_add() { TOOL_LABEL+=("$1"); TOOL_FLAG+=("$2"); TOOL_VER_VAR+=("$3"); TOOL_FUNC+=("$4"); TOOL_TYPE+=("$5"); }
_add claude   "${INSTALL_CLAUDE:-}"       CLAUDE_VERSION       _npm_install      npm
_add openspec "${INSTALL_OPENSPEC:-}"     OPENSPEC_VERSION     _npm_install      npm
_add codex    "${INSTALL_CODEX:-}"        CODEX_VERSION        _npm_install      npm
_add opencode "${INSTALL_OPENCODE:-}"     OPENCODE_VERSION     _npm_install      npm
_add python   "${INSTALL_PYTHON:-}"       PYTHON_VERSION       _python_install   apt
_add go       "${INSTALL_GO:-}"           GO_VERSION           _go_install       go
_add gh       "${INSTALL_GH:-}"           GH_VERSION           _gh_install       gh
_add flutter  "${INSTALL_FLUTTER:-}"      FLUTTER_VERSION      _flutter_install  flutter

for f in "${TOOL_FLAG[@]}"; do [[ "$f" == "true" || "$f" == "1" ]] && ENABLED=$((ENABLED+1)); done

# ================================================================
# Install loop
# ================================================================
echo "══════════════════════════════════════════════"
echo "  Paseo 可选工具安装  [${ENABLED} 个已启用]"
echo "══════════════════════════════════════════════"

CUR=0
for i in "${!TOOL_LABEL[@]}"; do
  label="${TOOL_LABEL[$i]}"; flag="${TOOL_FLAG[$i]}"
  ver_var="${TOOL_VER_VAR[$i]}"; func="${TOOL_FUNC[$i]}"; ptype="${TOOL_TYPE[$i]}"

  if [[ "$flag" != "true" && "$flag" != "1" ]]; then continue; fi

  CUR=$((CUR+1)); t1=$SECONDS
  ver="${!ver_var:-latest}"; [[ -z "$ver" ]] && ver="latest"

  # Map npm package names
  pkg="$label"
  case "$label" in
    claude)   pkg="@anthropic-ai/claude-code" ;;
    openspec) pkg="@fission-ai/openspec" ;;
    codex)    pkg="@openai/codex" ;;
    opencode) pkg="opencode-ai" ;;
  esac

  # Retry loop
  ok=false; attempt=0
  while [[ $attempt -lt $RETRY_COUNT ]]; do
    attempt=$((attempt+1))
    printf "  [%d/%d] %-10s " "$CUR" "$ENABLED" "${label}"

    if [[ "$ptype" == "npm" ]]; then
      "$func" "$label" "$pkg" "$ver" && { ok=true; break; }
    else
      "$func" "$ver" && { ok=true; break; }
    fi

    if [[ $attempt -lt $RETRY_COUNT ]]; then
      delay=$(( RETRY_BASE_DELAY * (1 << (attempt-1)) ))
      sleep "$delay"
    fi
  done

  t2=$((SECONDS-t1))

  if [[ "$ok" == "true" ]]; then
    TOOL_OK=$((TOOL_OK+1))
    local _ver; _ver="$(command -v "$label" 2>/dev/null && "$label" --version 2>/dev/null | head -1 || echo ok)"
    printf "✓ %s  (%ds)\n" "$_ver" "$t2"
  else
    TOOL_FAIL=$((TOOL_FAIL+1))
    printf "✗ 失败  (%ds)\n" "$t2"
  fi
done

# ================================================================
# Summary
# ================================================================
t=$((SECONDS-T0))
echo ""
echo "──────────────────────────────────────────────"
printf "  %d 成功  %d 失败  (%ds)\n" "$TOOL_OK" "$TOOL_FAIL" "$t"
echo "──────────────────────────────────────────────"

exit 0
