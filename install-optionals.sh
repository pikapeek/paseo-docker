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
# stall detection (not hard wall-clock timeout). Failed tools are retried
# per-source with exponential backoff.
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
#   * "latest" resolves to a concrete version via the tool's registry API.
#   * A tool already at the correct version is skipped.
#   * A failing tool is logged and skipped; boot never aborts.
#   * Stall detection: curl downloads use --speed-limit; npm uses pipe output monitor.
#   * A global INSTALL_MAX_WALL_TIME (default 7200s) acts as final safety net.
#
# API credentials for claude / codex / opencode are read from standard
# environment variables and written into each tool's config file (owned by
# the `paseo` user), so a runtime-installed agent uses them immediately.

set -u

# Cleanup process group on exit/signal to prevent zombie processes
trap 'kill -TERM -- -$$ 2>/dev/null; wait' EXIT INT TERM

PASEO_UID="${PASEO_UID:-1000}"
PASEO_GID="${PASEO_GID:-1000}"
PASEO_HOME="${PASEO_HOME:-/home/paseo}"

# ---- configurable defaults ----
RETRY_COUNT="${INSTALL_RETRY_COUNT:-3}"
RETRY_BASE_DELAY="${INSTALL_RETRY_BASE_DELAY:-2}"
MAX_WALL_TIME="${INSTALL_MAX_WALL_TIME:-7200}"
SPEED_LIMIT="${INSTALL_SPEED_LIMIT:-1024}"
STALL_SECONDS_CURL="${INSTALL_STALL_SECONDS:-120}"
STALL_SECONDS_NPM="${INSTALL_STALL_SECONDS:-180}"
NPM_CACHE_DIR="${NPM_CACHE_DIR:-/tmp/npm-cache}"
NPM_ARGS=(--no-audit --no-fund --cache "$NPM_CACHE_DIR")

# ---- summary tracking ----
declare -a SUMMARY_LINES
SUMMARY_TOTAL=0
SUMMARY_OK=0
SUMMARY_SKIP=0
SUMMARY_FAIL=0
OVERALL_START_SEC=0

inf()  { echo "  [可选工具] $*"; }
ok()   { echo "  [可选工具] $1 -> $2"; }
bad()  { echo "  [可选工具] $1 -> 失败 (继续): $2" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# Make a file/dir owned by the paseo user (when running as root).
own_as_paseo() { chown -R "${PASEO_UID}:${PASEO_GID}" "$1" 2>/dev/null || true; }

# ---- exit code analysis ----
analyze_exit_code() {
  local code="$1"
  case "$code" in
    0)   echo "成功" ;;
    28)  echo "下载停滞 (速率 < ${SPEED_LIMIT} B/s)" ;;
    124) echo "超时" ;;
    125) echo "timeout 命令自身失败" ;;
    137) echo "被 SIGKILL 强制终止" ;;
    139) echo "段错误 (SIGSEGV)" ;;
    143) echo "被 SIGTERM 终止" ;;
    *)   echo "非零退出码: $code" ;;
  esac
}

# ---- stall-detect for curl downloads ----
# curl --speed-limit detects when transfer rate drops below threshold.
# Exit code 28 means the speed limit was triggered (stall), NOT total time.
curl_with_stall_detect() {
  local url="$1" dest="$2" label="$3"
  inf "${label}: 下载 ${url} ..."
  curl --speed-limit "$SPEED_LIMIT" --speed-time "$STALL_SECONDS_CURL" \
       -fSL --connect-timeout 30 --retry 0 \
       "$url" -o "$dest"
}

# ---- stall-detect for npm/compile commands (pipe output monitor) ----
# Monitors stdout/stderr: if no new output for STALL_SECONDS_NPM seconds,
# the process is considered hung and gets killed.
run_with_stall_detect() {
  local stall_secs="$1"; shift
  local cmd_pid pipe_file last_mtime now

  pipe_file="$(mktemp -u)"
  mkfifo "$pipe_file"

  # Run the command, tee output to both the pipe and stdout (via the fifo reader)
  "$@" >"$pipe_file" 2>&1 &
  cmd_pid=$!

  # Background reader: feeds fifo to stdout and tracks last output time
  last_mtime=$(date +%s)
  (
    while IFS= read -r line; do
      echo "$line"
      last_mtime=$(date +%s)
    done < "$pipe_file"
  ) &
  reader_pid=$!

  # Stall monitor loop
  (
    while kill -0 "$cmd_pid" 2>/dev/null; do
      sleep 1
      now=$(date +%s)
      if [[ $(( now - last_mtime )) -ge "$stall_secs" ]]; then
        echo "  [可选工具] 进程卡死 (${stall_secs}s 无输出), 终止中..." >&2
        kill -TERM -- -"$cmd_pid" 2>/dev/null || true
        sleep 5
        kill -KILL -- -"$cmd_pid" 2>/dev/null || true
        break
      fi
    done
  ) &
  monitor_pid=$!

  wait "$cmd_pid" 2>/dev/null
  local ret=$?

  # Cleanup
  kill "$reader_pid" 2>/dev/null || true
  kill "$monitor_pid" 2>/dev/null || true
  wait "$reader_pid" 2>/dev/null || true
  wait "$monitor_pid" 2>/dev/null || true
  rm -f "$pipe_file"

  # If we killed it due to stall, return 124 (mimics timeout)
  if [[ $ret -eq 0 ]]; then
    # Check if it was SIGKILL'd by monitor
    return 0
  fi
  return "$ret"
}

# ---- common retry wrapper ----
# Usage: run_with_retry <label> <source_url> <timeout_secs> <cmd...>
# Tries the command up to RETRY_COUNT times with exponential backoff.
# The command is guarded by MAX_WALL_TIME as a final safety net.
# Returns 0 on success, 1 after exhausting retries.
run_with_retry() {
  local label="$1" source="$2" timeout_s="$3"; shift 3
  local attempt=1 delay="$RETRY_BASE_DELAY" ret reason

  while [[ $attempt -le $RETRY_COUNT ]]; do
    echo "  [${label}] 开始安装 (第${attempt}/${RETRY_COUNT}次, 源: ${source})"
    timeout "$MAX_WALL_TIME" "$@" 2>/dev/null
    ret=$?

    if [[ $ret -eq 0 ]]; then
      return 0
    fi

    reason="$(analyze_exit_code "$ret")"
    if [[ $attempt -lt $RETRY_COUNT ]]; then
      echo "  [${label}] 重试 (第${attempt}/${RETRY_COUNT}次失败: ${reason}, ${delay}s后重试)"
      sleep "$delay"
      attempt=$(( attempt + 1 ))
      delay=$(( delay * 2 ))
    else
      echo "  [${label}] 失败 (${reason}, 已尝试${RETRY_COUNT}次)"
      return 1
    fi
  done
  return 1
}

# ---- version resolution helpers ----
resolve_npm_version() {
  local pkg="$1" registry="$2"
  local url="${registry}/${pkg}/latest"
  timeout 30 curl -fsSL --connect-timeout 10 "$url" 2>/dev/null \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['version'])" 2>/dev/null
}

resolve_go_version() {
  local mirror="$1"
  local url="${mirror}go.dev/dl/?mode=json"
  # Use primary go.dev URL, but substitute mirror base for the actual download step
  timeout 30 curl -fsSL --connect-timeout 10 "https://go.dev/dl/?mode=json" 2>/dev/null \
    | python3 -c "
import json,sys
data=json.load(sys.stdin)
for r in data:
    if r.get('stable',False):
        v=r['version']
        print(v[2:] if v.startswith('go') else v); break
" 2>/dev/null
}

resolve_flutter_version() {
  timeout 30 curl -fsSL --connect-timeout 10 \
    "https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json" 2>/dev/null \
    | python3 -c "
import json,sys
d=json.load(sys.stdin)
for r in d['releases']:
    if r['channel']=='stable':
        print(r['version']); break
" 2>/dev/null
}

resolve_gh_version() {
  timeout 30 curl -fsSL --connect-timeout 10 \
    "https://api.github.com/repos/cli/cli/releases/latest" 2>/dev/null \
    | python3 -c "import json,sys; v=json.load(sys.stdin)['tag_name']; print(v[1:] if v.startswith('v') else v)" 2>/dev/null
}

# ---- idempotency check ----
# Returns 0 (skip) if the binary is already at the requested version.
skip_ok() {
  local bin="$1" want="$2"
  have "$bin" || return 1
  [[ "$want" == "latest" || -z "$want" ]] && return 0
  local have_ver
  have_ver="$("$bin" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  [[ "$have_ver" == "$want" ]] && return 0
  return 1
}

# ---- tool install functions ----

# Fallback version resolution inside install for tools that need concrete versions.
# Called when the main loop couldn't resolve "latest" and passed "latest" as the version.
resolve_latest_inline() {
  local label="$1"
  case "$label" in
    go)      resolve_go_version ;;
    flutter) resolve_flutter_version ;;
    gh)      resolve_gh_version ;;
    *)       echo "latest" ;;
  esac
}

# AI Tool: npm-based (claude / openspec / codex / opencode)
install_npm_tool() {
  local bin="$1" pkg="$2" ver="$3"
  local spec="${pkg}@${ver}"

  if skip_ok "$bin" "$ver"; then
    local installed; installed="$("$bin" --version 2>/dev/null | head -1)"
    echo "  [${bin}] 跳过 (${installed} 已安装)"
    return 0
  fi

  npm install -g "${NPM_ARGS[@]}" "$spec" 2>/dev/null
}

# Go toolchain
install_go() {
  local ver="$1" go_root=/usr/local/go

  # If version resolution failed earlier, try again now
  if [[ "$ver" == "latest" ]]; then
    echo "  [go] 解析最新版本..."
    ver="$(resolve_go_version)"
    [[ -z "$ver" ]] && ver="latest"
  fi
  [[ "$ver" == "latest" ]] && { echo "  [go] 无法解析版本"; return 1; }

  if [[ -x "$go_root/bin/go" ]] && "$go_root/bin/go" version 2>/dev/null | grep -qE "go${ver//./\\.}([^0-9]|\$)"; then
    echo "  [go] 跳过 (go${ver} 已安装)"
    return 0
  fi

  local arch
  case "$(uname -m)" in
    x86_64|amd64)  arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    armv7l|armhf)  arch=armv6l ;;
    *) echo "  [go] 不支持的架构: $(uname -m)" >&2; return 1 ;;
  esac

  inf "下载 go${ver}.linux-${arch}.tar.gz ..."
  local tmp; tmp="$(mktemp -d)"
  local dl_url="https://go.dev/dl/go${ver}.linux-${arch}.tar.gz"

  if ! curl_with_stall_detect "$dl_url" "$tmp/go.tgz" "go"; then
    echo "  [go] 下载停滞或失败"
    rm -rf "$tmp"
    return 1
  fi

  inf "解压到 ${go_root} ..."
  rm -rf "$go_root"
  if ! tar -C /usr/local -xzf "$tmp/go.tgz"; then
    echo "  [go] 解压失败"
    rm -rf "$tmp"
    return 1
  fi
  rm -rf "$tmp"

  # PATH/GOROOT for interactive/login shells
  cat > /etc/profile.d/paseo-go.sh <<'EOF'
export GOROOT=/usr/local/go
export PATH="$GOROOT/bin:$PATH"
EOF
  chmod 644 /etc/profile.d/paseo-go.sh
  "$go_root/bin/go" version 2>&1
}

# Flutter SDK
install_flutter() {
  local ver="$1" flutter_root=/usr/local/flutter

  # If version resolution failed earlier, try again now
  if [[ "$ver" == "latest" ]]; then
    echo "  [flutter] 解析最新版本..."
    ver="$(resolve_flutter_version)"
    [[ -z "$ver" ]] && ver="latest"
  fi
  [[ "$ver" == "latest" ]] && { echo "  [flutter] 无法解析版本"; return 1; }

  if [[ -x "$flutter_root/bin/flutter" ]]; then
    local installed; installed="$("$flutter_root/bin/flutter" --version 2>/dev/null | head -1)"
    if [[ "$ver" == "latest" ]]; then
      echo "  [flutter] 跳过 (已安装)"
      return 0
    fi
  fi

  local dl_url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${ver}-stable.tar.xz"
  local tmp; tmp="$(mktemp -d)"

  inf "下载 flutter_linux_${ver}-stable.tar.xz ..."
  if ! curl_with_stall_detect "$dl_url" "$tmp/flutter.tar.xz" "flutter"; then
    echo "  [flutter] 下载停滞或失败"
    rm -rf "$tmp"
    return 1
  fi

  inf "解压到 ${flutter_root} ..."
  rm -rf "$flutter_root"
  if ! tar -C /usr/local -xJf "$tmp/flutter.tar.xz"; then
    echo "  [flutter] 解压失败"
    rm -rf "$tmp"
    return 1
  fi
  rm -rf "$tmp"

  # PATH for interactive/login shells
  cat > /etc/profile.d/paseo-flutter.sh <<'EOF'
export PATH="/usr/local/flutter/bin:$PATH"
EOF
  chmod 644 /etc/profile.d/paseo-flutter.sh

  "$flutter_root/bin/flutter" --version >/dev/null 2>&1 || true
  "$flutter_root/bin/flutter" --version 2>/dev/null | head -1
}

# GitHub CLI (from GitHub Releases .deb, NOT apt)
install_gh() {
  local ver="$1"

  # If version resolution failed earlier, try again now
  if [[ "$ver" == "latest" ]]; then
    echo "  [gh] 解析最新版本..."
    ver="$(resolve_gh_version)"
    [[ -z "$ver" ]] && ver="latest"
  fi
  [[ "$ver" == "latest" ]] && { echo "  [gh] 无法解析版本"; return 1; }

  if have gh; then
    local installed; installed="$(gh --version 2>/dev/null | head -1)"
    if [[ "$ver" == "latest" ]]; then
      echo "  [gh] 跳过 (已安装)"
      return 0
    fi
    local have_ver; have_ver="$(echo "$installed" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [[ "$have_ver" == "$ver" ]]; then
      echo "  [gh] 跳过 (gh ${have_ver} 已安装)"
      return 0
    fi
  fi

  local deb_url="https://github.com/cli/cli/releases/download/v${ver}/gh_${ver}_linux_amd64.deb"
  local tmp; tmp="$(mktemp -d)"

  inf "下载 gh_${ver}_linux_amd64.deb ..."
  if ! curl_with_stall_detect "$deb_url" "$tmp/gh.deb" "gh"; then
    echo "  [gh] 下载停滞或失败"
    rm -rf "$tmp"
    return 1
  fi

  timeout 60 dpkg -i "$tmp/gh.deb" 2>/dev/null
  local ret=$?
  rm -rf "$tmp"

  if [[ $ret -ne 0 ]]; then
    echo "  [gh] dpkg 安装失败 (退出码: $ret)"
    return 1
  fi
  gh --version 2>/dev/null | head -1
}

# ---- API config functions (unchanged logic, extracted for clarity) ----
configure_claude() {
  have claude || return 0
  local dir="${PASEO_HOME}/.claude" cfg="$dir/settings.json"
  local base="${CLAUDE_BASE_URL:-}" tok="${CLAUDE_API_KEY:-}"
  local model="${CLAUDE_MODEL:-}" opus="${CLAUDE_OPUS_MODEL:-}"
  local sonnet="${CLAUDE_SONNET_MODEL:-}" haiku="${CLAUDE_HAIKU_MODEL:-}"
  [[ -n "$tok" ]] || return 0
  mkdir -p "$dir"
  {
    printf '{\n  "env": {\n'
    [[ -n "$base" ]]   && printf '    "ANTHROPIC_BASE_URL": "%s",\n' "$base"
    [[ -n "$model" ]]  && printf '    "ANTHROPIC_MODEL": "%s",\n' "$model"
    [[ -n "$opus" ]]   && printf '    "ANTHROPIC_DEFAULT_OPUS_MODEL": "%s",\n' "$opus"
    [[ -n "$sonnet" ]] && printf '    "ANTHROPIC_DEFAULT_SONNET_MODEL": "%s",\n' "$sonnet"
    [[ -n "$haiku" ]]  && printf '    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "%s",\n' "$haiku"
    printf '    "ANTHROPIC_API_KEY": "%s"\n' "$tok"
    printf '  }\n}\n'
  } > "$cfg"
  own_as_paseo "$dir"
  echo "  [claude-config] 写入 ${cfg}"
}

configure_codex() {
  have codex || return 0
  local dir="${PASEO_HOME}/.codex" cfg="$dir/config.toml"
  local key="${CODEX_API_KEY:-}" base="${CODEX_BASE_URL:-}"
  local model="${CODEX_MODEL:-}" review="${CODEX_REVIEW_MODEL:-}"
  [[ -n "$key" ]] || return 0
  mkdir -p "$dir"
  [[ -z "$base" ]] && base="https://api.openai.com/v1"
  {
    cat <<EOF
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
  } > "$cfg"
  own_as_paseo "$dir"
  echo "  [codex-config] 写入 ${cfg}"
}

configure_opencode() {
  have opencode || return 0
  local data="${PASEO_HOME}/.local/share/opencode"
  local auth="$data/auth.json" key="${OPENCODE_API_KEY:-}"
  local base="${OPENCODE_BASE_URL:-}" model="${OPENCODE_MODEL:-}"
  local small="${OPENCODE_SMALL_MODEL:-}" provider="${OPENCODE_PROVIDER:-openai}"
  [[ -n "$key" ]] || return 0
  mkdir -p "$data"
  {
    printf '{\n  "%s": {\n    "type": "api",\n    "key": "%s"\n  }\n}\n' \
      "$provider" "$key"
  } > "$auth"
  chmod 600 "$auth"
  own_as_paseo "$data"
  local cfgdir="${XDG_CONFIG_HOME:-${PASEO_HOME}/.config}/opencode"
  mkdir -p "$cfgdir"
  local cfg="$cfgdir/opencode.json"
  {
    printf '{\n'
    [[ -n "$model" ]] && printf '  "model": "%s",\n' "$model"
    [[ -n "$small" ]] && printf '  "small_model": "%s",\n' "$small"
    printf '  "provider": {\n    "%s": {\n' "$provider"
    [[ -n "$base" ]] && printf '      "options": {\n        "baseURL": "%s"\n      }\n' "$base"
    printf '    }\n  }\n}\n'
  } > "$cfg"
  own_as_paseo "$cfgdir"
  echo "  [opencode-config] 写入 auth.json + opencode.json ($provider)"
}

# ---- main ----
OVERALL_START_SEC=$SECONDS

echo "=============================================="
echo "  Paseo 可选工具安装"
echo "=============================================="

# ---- Build ordered tool queue ----
# Each entry: label enabled_flag version_var install_func resolve_func
# AI tools first, then API configs, then Go, Flutter, gh.
declare -a TOOL_LABELS TOOL_ENABLED TOOL_INSTALL_FN TOOL_VERSION_VAR
declare -a TOOL_RESOLVE_FN TOOL_SOURCES TOOL_TIMEOUT

# 1) Claude Code (AI tool)
TOOL_LABELS+=("claude")
TOOL_ENABLED+=("${INSTALL_CLAUDE:-}")
TOOL_VERSION_VAR+=("CLAUDE_VERSION")
TOOL_RESOLVE_FN+=(resolve_npm_version)
TOOL_SOURCES+=( "https://registry.npmjs.org" "https://registry.npmmirror.com" )
TOOL_TIMEOUT+=(300)

# 2) OpenSpec (AI tool)
TOOL_LABELS+=("openspec")
TOOL_ENABLED+=("${INSTALL_OPENSPEC:-}")
TOOL_VERSION_VAR+=("OPENSPEC_VERSION")
TOOL_RESOLVE_FN+=(resolve_npm_version)
TOOL_SOURCES+=( "https://registry.npmjs.org" "https://registry.npmmirror.com" )
TOOL_TIMEOUT+=(300)

# 3) Codex (AI tool)
TOOL_LABELS+=("codex")
TOOL_ENABLED+=("${INSTALL_CODEX:-}")
TOOL_VERSION_VAR+=("CODEX_VERSION")
TOOL_RESOLVE_FN+=(resolve_npm_version)
TOOL_SOURCES+=( "https://registry.npmjs.org" "https://registry.npmmirror.com" )
TOOL_TIMEOUT+=(300)

# 4) OpenCode (AI tool)
TOOL_LABELS+=("opencode")
TOOL_ENABLED+=("${INSTALL_OPENCODE:-}")
TOOL_VERSION_VAR+=("OPENCODE_VERSION")
TOOL_RESOLVE_FN+=(resolve_npm_version)
TOOL_SOURCES+=( "https://registry.npmjs.org" "https://registry.npmmirror.com" )
TOOL_TIMEOUT+=(300)

# 5) Go toolchain
TOOL_LABELS+=("go")
TOOL_ENABLED+=("${INSTALL_GO:-}")
TOOL_VERSION_VAR+=("GO_VERSION")
TOOL_RESOLVE_FN+=(resolve_go_version)
TOOL_SOURCES+=( "https://go.dev/dl/" "${GO_MIRROR_URL:-}" "https://mirrors.ustc.edu.cn/golang/" )
TOOL_TIMEOUT+=(600)

# 6) Flutter SDK
TOOL_LABELS+=("flutter")
TOOL_ENABLED+=("${INSTALL_FLUTTER:-}")
TOOL_VERSION_VAR+=("FLUTTER_VERSION")
TOOL_RESOLVE_FN+=(resolve_flutter_version)
TOOL_SOURCES+=( "https://storage.googleapis.com" "${FLUTTER_MIRROR:-}" "https://storage.flutter-io.cn" )
TOOL_TIMEOUT+=(900)

# 7) GitHub CLI
TOOL_LABELS+=("gh")
TOOL_ENABLED+=("${INSTALL_GH:-}")
TOOL_VERSION_VAR+=("GH_VERSION")
TOOL_RESOLVE_FN+=(resolve_gh_version)
TOOL_SOURCES+=( "https://github.com" "${GH_MIRROR_URL:-}" "https://mirror.ghproxy.com" )
TOOL_TIMEOUT+=(180)

# ---- Count enabled tools ----
enabled_count=0
for i in "${!TOOL_LABELS[@]}"; do
  flag="${TOOL_ENABLED[$i]}"
  [[ "$flag" == "true" || "$flag" == "1" ]] && enabled_count=$(( enabled_count + 1 ))
done

# ---- NPM registry override ----
npm_registry="${NPM_REGISTRY:-https://registry.npmjs.org}"
# Override AI tool sources if NPM_REGISTRY is set
if [[ -n "${NPM_REGISTRY:-}" ]]; then
  for i in 0 1 2 3; do
    TOOL_SOURCES[$i]="$npm_registry https://registry.npmjs.org"
  done
fi

# ---- Main install loop ----
current=0
for i in "${!TOOL_LABELS[@]}"; do
  label="${TOOL_LABELS[$i]}"
  flag="${TOOL_ENABLED[$i]}"
  ver_var="${TOOL_VERSION_VAR[$i]}"
  resolve_fn="${TOOL_RESOLVE_FN[$i]}"
  sources="${TOOL_SOURCES[$i]}"
  timeout_s="${TOOL_TIMEOUT[$i]}"

  # Skip disabled tools
  if [[ "$flag" != "true" && "$flag" != "1" ]]; then
    echo "  [${label}] 跳过 (未启用)"
    SUMMARY_LINES+=("[${label}]|跳过|未启用|-")
    SUMMARY_SKIP=$(( SUMMARY_SKIP + 1 ))
    SUMMARY_TOTAL=$(( SUMMARY_TOTAL + 1 ))
    continue
  fi

  current=$(( current + 1 ))
  tool_start=$SECONDS

  # Resolve version
  requested_ver="latest"
  if [[ -n "${!ver_var:-}" && "${!ver_var}" != "latest" ]]; then
    requested_ver="${!ver_var}"
  else
    # Resolve latest from registry; fall back to npm/curl native "@latest" on failure
    echo "  [${current}/${enabled_count}] ${label}: 解析最新版本..."
    case "$label" in
      claude)
        resolved="$($resolve_fn "@anthropic-ai/claude-code" "${TOOL_SOURCES[$i]%% *}")"
        ;;
      openspec)
        resolved="$($resolve_fn "@fission-ai/openspec" "${TOOL_SOURCES[$i]%% *}")"
        ;;
      codex)
        resolved="$($resolve_fn "@openai/codex" "${TOOL_SOURCES[$i]%% *}")"
        ;;
      opencode)
        resolved="$($resolve_fn "opencode-ai" "${TOOL_SOURCES[$i]%% *}")"
        ;;
      *)
        resolved="$($resolve_fn)"
        ;;
    esac
    if [[ -n "$resolved" ]]; then
      requested_ver="$resolved"
      echo "  [${current}/${enabled_count}] ${label}: 最新版本 = ${requested_ver}"
    else
      echo "  [${current}/${enabled_count}] ${label}: 版本解析失败, 用 latest 兜底"
      requested_ver="latest"
    fi
  fi

  # Try each source in order
  install_success=false
  source_used=""
  total_attempts=0

  IFS=' ' read -ra src_arr <<< "$sources"
  for src in "${src_arr[@]}"; do
    [[ -z "$src" ]] && continue

    if [[ "$install_success" == "true" ]]; then
      break
    fi

    # Run with retry + stall detection for this source
    local_attempts=0
    local_ok=false

    while [[ $local_attempts -lt $RETRY_COUNT ]]; do
      local_attempts=$(( local_attempts + 1 ))
      total_attempts=$(( total_attempts + 1 ))

      echo "  [${current}/${enabled_count}] ${label}: 开始安装 (第${local_attempts}/${RETRY_COUNT}次, 源: ${src})"

      ret=0
      case "$label" in
        claude|openspec|codex|opencode)
          timeout "$MAX_WALL_TIME" install_npm_tool "$label" \
            "$(case $label in
              claude)   echo "@anthropic-ai/claude-code" ;;
              openspec) echo "@fission-ai/openspec" ;;
              codex)    echo "@openai/codex" ;;
              opencode) echo "opencode-ai" ;;
            esac)" "$requested_ver" 2>&1
          ret=$?
          ;;
        go)
          timeout "$MAX_WALL_TIME" install_go "$requested_ver" 2>&1
          ret=$?
          ;;
        flutter)
          timeout "$MAX_WALL_TIME" install_flutter "$requested_ver" 2>&1
          ret=$?
          ;;
        gh)
          timeout "$MAX_WALL_TIME" install_gh "$requested_ver" 2>&1
          ret=$?
          ;;
      esac

      if [[ $ret -eq 0 ]]; then
        local_ok=true
        source_used="$src"
        install_success=true
        break
      fi

      reason="$(analyze_exit_code "$ret")"
      if [[ $local_attempts -lt $RETRY_COUNT ]]; then
        delay="$RETRY_BASE_DELAY"
        for ((m=1; m<local_attempts; m++)); do delay=$((delay * 2)); done
        echo "  [${label}] 重试 (第${local_attempts}/${RETRY_COUNT}次失败: ${reason}, ${delay}s后重试)"
        sleep "$delay"
      fi
    done

    if [[ "$local_ok" == "false" ]]; then
      if [[ "$src" != "${src_arr[-1]}" ]]; then
        echo "  [${label}] 切换到备用源: ${src_arr[$(( ${#src_arr[@]} - 1 ))]}"
      fi
    fi
  done

  tool_duration=$(( SECONDS - tool_start ))

  if [[ "$install_success" == "true" ]]; then
    echo "  [${current}/${enabled_count}] ${label}: 完成 (v${requested_ver}, ${tool_duration}s, 源: ${source_used})"
    SUMMARY_LINES+=("[${label}]|完成|v${requested_ver} (${tool_duration}s)|${source_used}")
    SUMMARY_OK=$(( SUMMARY_OK + 1 ))
  else
    echo "  [${current}/${enabled_count}] ${label}: 失败 (所有源已耗尽, ${tool_duration}s)"
    SUMMARY_LINES+=("[${label}]|失败|所有源已耗尽 (${tool_duration}s)|-")
    SUMMARY_FAIL=$(( SUMMARY_FAIL + 1 ))
  fi
  SUMMARY_TOTAL=$(( SUMMARY_TOTAL + 1 ))
done

# ---- API configs (after AI tools are installed) ----
echo "=============================================="
echo "  API 配置"
echo "=============================================="

configure_claude
configure_codex
configure_opencode

# ---- Summary table ----
overall_duration=$(( SECONDS - OVERALL_START_SEC ))

echo ""
echo "=============================================="
echo "  安装汇总 (总耗时: ${overall_duration}s)"
echo "=============================================="

for line in "${SUMMARY_LINES[@]}"; do
  IFS='|' read -r lab status detail src <<< "$line"
  if [[ "$status" == "完成" ]]; then
    printf "  %-20s %-8s %-40s 源: %s\n" "$lab" "$status" "$detail" "$src"
  elif [[ "$status" == "跳过" ]]; then
    printf "  %-20s %-8s %-40s\n" "$lab" "$status" "$detail"
  else
    printf "  %-20s %-8s %-40s\n" "$lab" "$status" "$detail"
  fi
done

echo "=============================================="
echo "  ${SUMMARY_OK} 成功, ${SUMMARY_SKIP} 跳过, ${SUMMARY_FAIL} 失败"
echo "=============================================="

exit 0
