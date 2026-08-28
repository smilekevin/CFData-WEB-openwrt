#!/bin/sh
# ============================================================
# CFData-Web 自动更新脚本 (OpenWrt / busybox ash 兼容)
#
# 功能: 检查 GitHub 最新 Release -> 下载 -> sha256 校验
#       -> 原子替换二进制 -> 重启服务
#       结果写入 $CFDATA_DIR/LATEST (供 LuCI 页面显示)
# 镜像链: github.com 直连 -> ghproxy.net -> gh-proxy.com
# 用法: /opt/cfdata/cfdata-update.sh [--force]
#       --force 强制重新下载当前最新版 (忽略 VERSION 记录)
# ============================================================

CFDATA_DIR=${CFDATA_DIR:-/opt/cfdata}
ARCH=${ARCH:-}
CF_REPO="PoemMisty/CFData-WEB"
API_URL="https://api.github.com/repos/${CF_REPO}/releases/latest"
LOG_FILE="$CFDATA_DIR/update.log"
VERSION_FILE="$CFDATA_DIR/VERSION"
LATEST_FILE="$CFDATA_DIR/LATEST"
BIN_FILE="$CFDATA_DIR/cfdata"
BAK_FILE="$CFDATA_DIR/cfdata.bak"

mkdir -p "$CFDATA_DIR"

# ---------- 日志: 写文件 + 回显 ----------
log() {
    echo "[$(date '+%F %T')] $*" >> "$LOG_FILE"
    echo "[$(date '+%F %T')] $*"
}

# ---------- 架构探测 (可被环境变量 ARCH 覆盖) ----------
if [ -z "$ARCH" ]; then
    case "$(uname -m)" in
        aarch64|arm64)  ARCH="linux-arm64" ;;
        x86_64|amd64)   ARCH="linux-amd64" ;;
        *)
            log "警告: 未知架构 $(uname -m), 默认尝试 linux-arm64"
            ARCH="linux-arm64"
            ;;
    esac
fi

# ---------- 下载器: 依次尝试镜像, 成功即返回 ----------
wget_f() { # $1=URL  $2=输出文件  $3=超时秒
    wget -q -T "$3" -O "$2" "$1" 2>/dev/null
}

api_fetch() { # $1=输出文件
    local u
    for u in \
        "$API_URL" \
        "https://ghproxy.net/$API_URL"; do
        wget_f "$u" "$1" 30 && [ -s "$1" ] && return 0
    done
    return 1
}

rel_fetch() { # $1=tag  $2=asset  $3=输出文件
    local u
    for u in \
        "https://github.com/$CF_REPO/releases/download/$1/$2" \
        "https://ghproxy.net/https://github.com/$CF_REPO/releases/download/$1/$2" \
        "https://gh-proxy.com/https://github.com/$CF_REPO/releases/download/$1/$2"; do
        wget_f "$u" "$3" 180 && [ -s "$3" ] && return 0
    done
    return 1
}

# ---------- 获取最新版本信息 ----------
log "当前架构: $ARCH"

if ! api_fetch /tmp/cfdata-rel.json; then
    log "ERROR: 获取 Release 信息失败 (网络不通或 API 限流)"
    exit 1
fi

TAG=$(grep -o '"tag_name": *"[^"]*"' /tmp/cfdata-rel.json | head -1 | sed 's/.*"tag_name": *"//; s/"$//')
URL=$(grep -o '"browser_download_url": *"[^"]*'"$ARCH"'"' /tmp/cfdata-rel.json | head -1 | sed 's/.*"browser_download_url": *"//; s/"$//')

if [ -z "$TAG" ] || [ -z "$URL" ]; then
    log "ERROR: 解析 Release 失败 (tag=$TAG url=$URL arch=$ARCH)"
    exit 1
fi

# 记录 GitHub 最新版 (供 LuCI 显示, 即使已是最新也更新)
echo "$TAG" > "$LATEST_FILE"

# ---------- 版本判断: 已是最新则跳过 ----------
CUR=$(cat "$VERSION_FILE" 2>/dev/null)
if [ "$CUR" = "$TAG" ] && [ "$1" != "--force" ]; then
    log "已是最新版本 $TAG, 跳过"
    exit 0
fi

# ---------- 下载 + 校验 ----------
TMP="$CFDATA_DIR/.cfdata.tmp.$$"
rm -rf "$TMP"
mkdir -p "$TMP" || { log "ERROR: 无法创建临时目录 $TMP"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

ASSET="cfdata-$ARCH"
log "发现新版本 $TAG (当前: ${CUR:-无}), 开始下载..."
log "URL: $URL"

if ! rel_fetch "$TAG" "$ASSET" "$TMP/cfdata"; then
    log "ERROR: 二进制下载失败 (直连+镜像均失败)"
    exit 1
fi
rel_fetch "$TAG" "$ASSET.sha256" "$TMP/cfdata.sha256"

if [ -s "$TMP/cfdata.sha256" ]; then
    EXPECT=$(awk '{print $1}' "$TMP/cfdata.sha256")
    ACTUAL=$(sha256sum "$TMP/cfdata" | awk '{print $1}')
    if [ -z "$EXPECT" ] || [ "$EXPECT" != "$ACTUAL" ]; then
        log "ERROR: sha256 校验失败 (期望 $EXPECT, 实际 $ACTUAL)"
        exit 1
    fi
    log "sha256 校验通过"
else
    log "警告: 未获取到 sha256 文件, 跳过校验"
fi

# ---------- 原子替换 (旧版留作 cfdata.bak) ----------
[ -f "$BIN_FILE" ] && mv -f "$BIN_FILE" "$BAK_FILE"
mv "$TMP/cfdata" "$BIN_FILE"
chmod +x "$BIN_FILE"
echo "$TAG" > "$VERSION_FILE"
log "部署完成: $BIN_FILE ($TAG)"

# 保持数据目录属主为专用用户 cfdata (若启用了 OpenClash 绕行 BYPASS_PROXY)
grep -q '^cfdata:' /etc/passwd 2>/dev/null && chown -R cfdata:cfdata "$CFDATA_DIR" 2>/dev/null

# ---------- 重启服务 ----------
if [ -x /etc/init.d/cfdata ]; then
    /etc/init.d/cfdata restart 2>/dev/null && log "服务已重启" \
        || log "WARN: 服务重启失败, 请手动执行 /etc/init.d/cfdata restart"
else
    log "提示: 未安装 init 脚本, 跳过重启"
fi
log "----------------------------------------"
