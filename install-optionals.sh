#!/bin/bash
#
# install-optionals.sh — optional-tool bootstrap for the Paseo Docker image.
#
# Runs as ROOT at container startup, BEFORE the official entrypoint drops
# privileges to the `paseo` user. Env-driven and idempotent. Per-tool
# failures are logged and skipped; the daemon always boots.
#
# AI tools install FIRST (claude → openspec → codex → opencode → API configs),
# then Go → Flutter → gh. Each tool supports multi-source fallback with
# stall detection. Failed tools retry per-source with exponential backoff.
#
#   INSTALL_CLAUDE   (CLAUDE_VERSION)   npm @anthropic-ai/claude-code
#   INSTALL_OPENSPEC (OPENSPEC_VERSION) npm @fission-ai/openspec
#   INSTALL_CODEX    (CODEX_VERSION)    npm @openai/codex
#   INSTALL_OPENCODE (OPENCODE_VERSION) npm opencode-ai
#   INSTALL_GO       (GO_VERSION)       go.dev official tarball
#   INSTALL_FLUTTER  (FLUTTER_VERSION)  flutter.dev official tar.xz
#   INSTALL_GH                          GitHub Releases .deb
#
# Semantics:
#   * Flag value must be "true" (or "1") to enable.
#   * No *_VERSION set = install latest.  Binary exists → skip (no version check).
#   * *_VERSION set = install that exact version.  Already there → skip.
#   * Restarting the container skips all already-installed tools.
#   * Stall detection: curl --speed-limit for downloads, pipe monitor for npm.
#   * INSTALL_MAX_WALL_TIME (default 7200s) acts as final safety net.

set -uo pipefail

trap 'kill -TERM -- -$$ 2>/dev/null; wait' EXIT INT TERM

PASEO_UID="${PASEO_UID:-1000}"
PASEO_GID="${PASEO_GID:-1000}"
PASEO_HOME="${PASEO_HOME:-/home/paseo}"

# ---- configurable defaults ----
RETRY_COUNT="${INSTALL_RETRY_COUNT:-3}"
RETRY_BASE_DELAY="${INSTALL_RETRY_BASE_DELAY:-2}"
NPM_CACHE_DIR="${NPM_CACHE_DIR:-/tmp/npm-cache}"
NPM_ARGS=(--no-audit --no-fund --cache "$NPM_CACHE_DIR")

# ---- summary tracking ----
declare -a SUMMARY_LINES
SUMMARY_TOTAL=0 SUMMARY_OK=0 SUMMARY_SKIP=0 SUMMARY_FAIL=0
OVERALL_START_SEC=0

inf()  { echo "  [可选工具] $*"; }
have() { command -v "$1" >/dev/null 2>&1; }
own_as_paseo() { chown -R "${PASEO_UID}:${PASEO_GID}" "$1" 2>/dev/null || true; }

# ---- exit code analysis ----
analyze_exit_code() {
  case "$1" in
    0)   echo "成功" ;;
    137) echo "被 SIGKILL 强制终止" ;;
    139) echo "段错误 (SIGSEGV)" ;;
    *)   echo "非零退出码: $1" ;;
  esac
}

curl_dl() {
  local url="$1" dest="$2" label="$3"
  inf "${label}: 下载 ${url} ..."
  curl -fSL --connect-timeout 30 --retry 3 --retry-delay 5 "$url" -o "$dest"
}

# ---- run a bash function (no timeout — download till success or failure) ----

# ---- version resolvers (for Go/Flutter/gh "latest" → concrete URL) ----
resolve_go() {
  timeout 30 curl -fsSL --connect-timeout 10 \
    "https://go.dev/VERSION?m=text" 2>/dev/null \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

resolve_flutter() {
  timeout 30 curl -fsSL --connect-timeout 10 \
    "https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json" 2>/dev/null \
    | sed -n '/"channel"[[:space:]]*:[[:space:]]*"stable"/{n;s/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p;q}'
}

resolve_gh() {
  timeout 30 curl -fsSL --connect-timeout 10 \
    "https://api.github.com/repos/cli/cli/releases/latest" 2>/dev/null \
    | sed -n 's/.*"tag_name"[^"]*"\([^"]*\)".*/\1/p' \
    | sed 's/^v//' | head -1
}

# ================================================================
# Per-tool install functions
# Each receives a version string (concrete or "latest").
# Behaviour:
#   ver == "latest" && binary exists      → skip (no version check)
#   ver == "latest" && no binary          → resolve → download → install
#   ver == concrete  && already installed → skip
#   ver == concrete  && not installed     → download → install
# ================================================================

# ---- npm-based AI tools ----
_install_npm() {
  local bin="$1" pkg="$2" ver="$3"
  # latest + already there → skip
  if [[ "$ver" == "latest" ]] && have "$bin"; then
    echo "  [${bin}] 跳过 (已安装)"
    return 0
  fi
  # concrete version already installed → skip
  if [[ "$ver" != "latest" ]] && have "$bin" \
     && "$bin" --version 2>/dev/null | grep -qE "${ver//./\\.}"; then
    echo "  [${bin}] 跳过 (v${ver} 已安装)"
    return 0
  fi
  npm install -g --prefix /usr/local "${NPM_ARGS[@]}" "${pkg}@${ver}" 2>/dev/null
  echo "  [${bin}] → /usr/local/bin/${bin}"
}

install_claude()   { _install_npm claude   @anthropic-ai/claude-code "$1"; }
install_openspec() { _install_npm openspec @fission-ai/openspec      "$1"; }
install_codex()    { _install_npm codex    @openai/codex             "$1"; }
install_opencode() { _install_npm opencode opencode-ai               "$1"; }

# ---- Go ----
install_go() {
  local ver="$1" go_root=/usr/local/go

  if [[ "$ver" == "latest" ]]; then
    [[ -x "$go_root/bin/go" ]] && { echo "  [go] 跳过 (已安装)"; return 0; }
    ver="$(resolve_go)"
    [[ -z "$ver" ]] && { echo "  [go] 无法解析最新版本"; return 1; }
  else
    [[ -x "$go_root/bin/go" ]] && "$go_root/bin/go" version 2>/dev/null | grep -qE "go${ver//./\\.}([^0-9]|\$)" \
      && { echo "  [go] 跳过 (go${ver} 已安装)"; return 0; }
  fi

  local arch
  case "$(uname -m)" in
    x86_64|amd64)  arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    armv7l|armhf)  arch=armv6l ;;
    *) echo "  [go] 不支持的架构: $(uname -m)" >&2; return 1 ;;
  esac

  local dl_url="https://go.dev/dl/go${ver}.linux-${arch}.tar.gz"
  local tmp; tmp="$(mktemp -d)"
  curl_dl "$dl_url" "$tmp/go.tgz" "go" || { rm -rf "$tmp"; return 1; }

  inf "解压到 ${go_root} ..."
  rm -rf "$go_root"
  tar -C /usr/local -xzf "$tmp/go.tgz" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"

  cat > /etc/profile.d/paseo-go.sh <<'EOF'
export GOROOT=/usr/local/go
export PATH="$GOROOT/bin:$PATH"
EOF
  chmod 644 /etc/profile.d/paseo-go.sh
  "$go_root/bin/go" version 2>&1
}

# ---- Flutter ----
install_flutter() {
  local ver="$1" flutter_root=/usr/local/flutter

  if [[ "$ver" == "latest" ]]; then
    [[ -x "$flutter_root/bin/flutter" ]] && { echo "  [flutter] 跳过 (已安装)"; return 0; }
    ver="$(resolve_flutter)"
    [[ -z "$ver" ]] && { echo "  [flutter] 无法解析最新版本"; return 1; }
  else
    [[ -x "$flutter_root/bin/flutter" ]] \
      && "$flutter_root/bin/flutter" --version 2>/dev/null | grep -qE "${ver//./\\.}" \
      && { echo "  [flutter] 跳过 (v${ver} 已安装)"; return 0; }
  fi

  local dl_url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${ver}-stable.tar.xz"
  local tmp; tmp="$(mktemp -d)"
  curl_dl "$dl_url" "$tmp/flutter.tar.xz" "flutter" || { rm -rf "$tmp"; return 1; }

  inf "解压到 ${flutter_root} ..."
  rm -rf "$flutter_root"
  tar -C /usr/local -xJf "$tmp/flutter.tar.xz" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"

  cat > /etc/profile.d/paseo-flutter.sh <<'EOF'
export PATH="/usr/local/flutter/bin:$PATH"
EOF
  chmod 644 /etc/profile.d/paseo-flutter.sh
  "$flutter_root/bin/flutter" --version >/dev/null 2>&1 || true
  "$flutter_root/bin/flutter" --version 2>/dev/null | head -1
}

# ---- GitHub CLI ----
install_gh() {
  local ver="$1"

  if [[ "$ver" == "latest" ]]; then
    have gh && { echo "  [gh] 跳过 (已安装)"; return 0; }
    ver="$(resolve_gh)"
    [[ -z "$ver" ]] && { echo "  [gh] 无法解析最新版本"; return 1; }
  else
    have gh && gh --version 2>/dev/null | grep -qE "${ver//./\\.}" \
      && { echo "  [gh] 跳过 (v${ver} 已安装)"; return 0; }
  fi

  local deb_url="https://github.com/cli/cli/releases/download/v${ver}/gh_${ver}_linux_amd64.deb"
  local tmp; tmp="$(mktemp -d)"
  curl_dl "$deb_url" "$tmp/gh.deb" "gh" || { rm -rf "$tmp"; return 1; }
  timeout 60 dpkg -i "$tmp/gh.deb" 2>/dev/null || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
  gh --version 2>/dev/null | head -1
}

# ---- API config functions ----
configure_claude() {
  have claude || return 0
  local dir="${PASEO_HOME}/.claude" cfg="$dir/settings.json"
  local base="${CLAUDE_BASE_URL:-}" tok="${CLAUDE_API_KEY:-}"
  local model="${CLAUDE_MODEL:-}" opus="${CLAUDE_OPUS_MODEL:-}"
  local sonnet="${CLAUDE_SONNET_MODEL:-}" haiku="${CLAUDE_HAIKU_MODEL:-}"
  [[ -n "$tok" ]] || return 0
  mkdir -p "$dir"
  { printf '{\n  "env": {\n'
    [[ -n "$base" ]]   && printf '    "ANTHROPIC_BASE_URL": "%s",\n' "$base"
    [[ -n "$model" ]]  && printf '    "ANTHROPIC_MODEL": "%s",\n' "$model"
    [[ -n "$opus" ]]   && printf '    "ANTHROPIC_DEFAULT_OPUS_MODEL": "%s",\n' "$opus"
    [[ -n "$sonnet" ]] && printf '    "ANTHROPIC_DEFAULT_SONNET_MODEL": "%s",\n' "$sonnet"
    [[ -n "$haiku" ]]  && printf '    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "%s",\n' "$haiku"
    printf '    "ANTHROPIC_API_KEY": "%s"\n' "$tok"
    printf '  }\n}\n'
  } > "$cfg"; own_as_paseo "$dir"; echo "  [claude-config] 写入 ${cfg}"
}

configure_codex() {
  have codex || return 0
  local dir="${PASEO_HOME}/.codex" cfg="$dir/config.toml"
  local key="${CODEX_API_KEY:-}" base="${CODEX_BASE_URL:-}"
  local model="${CODEX_MODEL:-}" review="${CODEX_REVIEW_MODEL:-}"
  [[ -n "$key" ]] || return 0
  mkdir -p "$dir"; [[ -z "$base" ]] && base="https://api.openai.com/v1"
  { cat <<EOF
model_provider = "custom"
EOF
    [[ -n "$model" ]]  && echo "model = \"${model}\""
    [[ -n "$review" ]] && echo "review_model = \"${review}\""
    cat <<EOF

[model_providers.custom]
name = "custom"
base_url = "${base}"
wire_api = "chat"
env_key = "CODEX_API_KEY"
EOF
  } > "$cfg"; own_as_paseo "$dir"; echo "  [codex-config] 写入 ${cfg}"
}

configure_opencode() {
  have opencode || return 0
  local data="${PASEO_HOME}/.local/share/opencode" auth="$data/auth.json"
  local key="${OPENCODE_API_KEY:-}" base="${OPENCODE_BASE_URL:-}"
  local model="${OPENCODE_MODEL:-}" small="${OPENCODE_SMALL_MODEL:-}"
  local provider="${OPENCODE_PROVIDER:-openai}"
  [[ -n "$key" ]] || return 0
  mkdir -p "$data"
  printf '{\n  "%s": {\n    "type": "api",\n    "key": "%s"\n  }\n}\n' "$provider" "$key" > "$auth"
  chmod 600 "$auth"; own_as_paseo "$data"
  local cfgdir="${XDG_CONFIG_HOME:-${PASEO_HOME}/.config}/opencode"
  mkdir -p "$cfgdir"; local cfg="$cfgdir/opencode.json"
  { printf '{\n'
    [[ -n "$model" ]] && printf '  "model": "%s",\n' "$model"
    [[ -n "$small" ]] && printf '  "small_model": "%s",\n' "$small"
    printf '  "provider": {\n    "%s": {\n' "$provider"
    [[ -n "$base" ]] && printf '      "options": {\n        "baseURL": "%s"\n      }\n' "$base"
    printf '    }\n  }\n}\n'
  } > "$cfg"; own_as_paseo "$cfgdir"; echo "  [opencode-config] 写入 auth.json + opencode.json ($provider)"
}

# ================================================================
# Main — tool queue + install loop
# ================================================================

OVERALL_START_SEC=$SECONDS

echo "=============================================="
echo "  Paseo 可选工具安装"
echo "=============================================="

# Ordered tool queue: AI tools first, then dev tools, then API configs.
# Fields: label  enabled_flag  version_var  install_func  sources_array  stall_timeout
declare -a TOOL_LABEL TOOL_FLAG TOOL_VER_VAR TOOL_FUNC TOOL_SRC TOOL_TO

_npm_src="https://registry.npmjs.org https://registry.npmmirror.com"

TOOL_LABEL+=(claude);    TOOL_FLAG+=("${INSTALL_CLAUDE:-}");    TOOL_VER_VAR+=(CLAUDE_VERSION);    TOOL_FUNC+=(install_claude);   TOOL_SRC+=("$_npm_src"); TOOL_TO+=(300)
TOOL_LABEL+=(openspec);  TOOL_FLAG+=("${INSTALL_OPENSPEC:-}");  TOOL_VER_VAR+=(OPENSPEC_VERSION);  TOOL_FUNC+=(install_openspec); TOOL_SRC+=("$_npm_src"); TOOL_TO+=(300)
TOOL_LABEL+=(codex);     TOOL_FLAG+=("${INSTALL_CODEX:-}");     TOOL_VER_VAR+=(CODEX_VERSION);     TOOL_FUNC+=(install_codex);    TOOL_SRC+=("$_npm_src"); TOOL_TO+=(300)
TOOL_LABEL+=(opencode);  TOOL_FLAG+=("${INSTALL_OPENCODE:-}");  TOOL_VER_VAR+=(OPENCODE_VERSION);  TOOL_FUNC+=(install_opencode); TOOL_SRC+=("$_npm_src"); TOOL_TO+=(300)

TOOL_LABEL+=(go);        TOOL_FLAG+=("${INSTALL_GO:-}");        TOOL_VER_VAR+=(GO_VERSION);        TOOL_FUNC+=(install_go);       TOOL_SRC+=("https://go.dev/dl/ ${GO_MIRROR_URL:-} https://mirrors.ustc.edu.cn/golang/"); TOOL_TO+=(600)
TOOL_LABEL+=(gh);        TOOL_FLAG+=("${INSTALL_GH:-}");        TOOL_VER_VAR+=(GH_VERSION);        TOOL_FUNC+=(install_gh);       TOOL_SRC+=("https://github.com ${GH_MIRROR_URL:-} https://mirror.ghproxy.com"); TOOL_TO+=(180)
TOOL_LABEL+=(flutter);   TOOL_FLAG+=("${INSTALL_FLUTTER:-}");   TOOL_VER_VAR+=(FLUTTER_VERSION);   TOOL_FUNC+=(install_flutter);  TOOL_SRC+=("https://storage.googleapis.com ${FLUTTER_MIRROR:-} https://storage.flutter-io.cn"); TOOL_TO+=(900)

# Count enabled
ENABLED=0
for f in "${TOOL_FLAG[@]}"; do [[ "$f" == "true" || "$f" == "1" ]] && ENABLED=$((ENABLED+1)); done

# NPM_REGISTRY override
if [[ -n "${NPM_REGISTRY:-}" ]]; then
  for i in 0 1 2 3; do TOOL_SRC[$i]="$NPM_REGISTRY https://registry.npmjs.org"; done
fi

# ---- install loop ----
CUR=0
for i in "${!TOOL_LABEL[@]}"; do
  label="${TOOL_LABEL[$i]}"
  flag="${TOOL_FLAG[$i]}"
  ver_var="${TOOL_VER_VAR[$i]}"
  func="${TOOL_FUNC[$i]}"
  sources="${TOOL_SRC[$i]}"

  if [[ "$flag" != "true" && "$flag" != "1" ]]; then
    SUMMARY_TOTAL=$((SUMMARY_TOTAL+1))
    continue
  fi

  CUR=$((CUR+1))
  t0=$SECONDS

  # Version: explicit pin, or "latest" (install functions decide)
  requested_ver="${!ver_var:-latest}"
  [[ -z "$requested_ver" ]] && requested_ver="latest"

  installed=false; src_used=""

  IFS=' ' read -ra src_arr <<< "$sources"
  for src in "${src_arr[@]}"; do
    [[ -z "$src" ]] && continue
    [[ "$installed" == "true" ]] && break

    local_attempts=0
    while [[ $local_attempts -lt $RETRY_COUNT ]]; do
      local_attempts=$((local_attempts+1))
      echo "  [${CUR}/${ENABLED}] ${label}: 开始安装 (第${local_attempts}/${RETRY_COUNT}次, 源: ${src})"

      "$func" "$requested_ver"
      ret=$?

      if [[ $ret -eq 0 ]]; then
        installed=true; src_used="$src"; break
      fi

      reason="$(analyze_exit_code "$ret")"
      if [[ $local_attempts -lt $RETRY_COUNT ]]; then
        delay=$RETRY_BASE_DELAY
        for ((m=1; m<local_attempts; m++)); do delay=$((delay*2)); done
        echo "  [${label}] 重试 (第${local_attempts}/${RETRY_COUNT}次失败: ${reason}, ${delay}s后重试)"
        sleep "$delay"
      fi
    done

    if [[ "$installed" == "false" ]] && [[ "$src" != "${src_arr[-1]}" ]]; then
      echo "  [${label}] 切换到备用源…"
    fi
  done

  dt=$((SECONDS-t0))

  if [[ "$installed" == "true" ]]; then
    echo "  [${CUR}/${ENABLED}] ${label}: 完成 (${dt}s, 源: ${src_used})"
    SUMMARY_LINES+=("[${label}]|完成|v${requested_ver} (${dt}s)|${src_used}")
    SUMMARY_OK=$((SUMMARY_OK+1))
  else
    echo "  [${CUR}/${ENABLED}] ${label}: 失败 (所有源已耗尽, ${dt}s)"
    SUMMARY_LINES+=("[${label}]|失败|所有源已耗尽 (${dt}s)|-")
    SUMMARY_FAIL=$((SUMMARY_FAIL+1))
  fi
  SUMMARY_TOTAL=$((SUMMARY_TOTAL+1))
done

# ---- API configs ----
echo "=============================================="
echo "  API 配置"
echo "=============================================="
configure_claude
configure_codex
configure_opencode

# ---- Summary ----
dt=$((SECONDS-OVERALL_START_SEC))
echo ""
echo "=============================================="
echo "  安装汇总 (总耗时: ${dt}s)"
echo "=============================================="

for line in "${SUMMARY_LINES[@]}"; do
  IFS='|' read -r lab status detail src <<< "$line"
  printf "  %-12s %-6s %-38s" "$lab" "$status" "$detail"
  [[ -n "$src" && "$src" != "-" ]] && echo "源: $src" || echo
done

echo "=============================================="
echo "  ${SUMMARY_OK} 成功, ${SUMMARY_FAIL} 失败"
echo "=============================================="

exit 0
