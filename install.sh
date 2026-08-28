#!/bin/sh
# ============================================================
# CFData-WEB-openwrt 一键部署脚本 (OpenWrt / busybox ash 兼容)
#
# 用法:
#   直连:    wget -O- https://raw.githubusercontent.com/smilekevin/CFData-WEB-openwrt/main/install.sh | sh
#   国内:    wget -O- https://cdn.jsdelivr.net/gh/smilekevin/CFData-WEB-openwrt@main/install.sh | sh
#   或先下载再执行: wget -O /tmp/install.sh <上面的URL> && sh /tmp/install.sh
#
# 可选环境变量:
#   BRANCH=main          指定分支
#   SKIP_BIN=1           跳过二进制下载 (仅安装脚本/LuCI)
#   NO_SERVICE=1         不执行服务操作 (启停/cron/rpcd 重启)
#   PROXY=nginx          自动配置纯 HTTP 反代 (无 SSL, 需已装 nginx 包)
#   PROXY_PORT=8080      纯 HTTP 反代端口 (默认 8080, 避开 LuCI 的 80)
#   CFDATA_DIR=...       覆盖数据目录 (默认 /opt/cfdata, 可用于离线安装测试)
#   LUCI_RPCD_DIR=...    覆盖 LuCI 后端目录 (默认 /usr/share/rpcd/ucode)
#   LUCI_ACL_DIR=...     覆盖 ACL 目录 (默认 /usr/share/rpcd/acl.d)
#   LUCI_MENU_DIR=...    覆盖菜单目录 (默认 /usr/share/luci/menu.d)
#   LUCI_VIEW_DIR=...    覆盖页面目录 (默认 /www/luci-static/resources/view/cfdata)
# ============================================================

REPO_USER="smilekevin"
REPO_NAME="CFData-WEB-openwrt"
BRANCH=${BRANCH:-main}

CF_REPO="PoemMisty/CFData-WEB"          # 上游二进制仓库
CFDATA_DIR=${CFDATA_DIR:-/opt/cfdata}
INIT_SCRIPT=${INIT_SCRIPT:-/etc/init.d/cfdata}
CRONTAB=${CRONTAB:-/etc/crontabs/root}
CRON_LINE="0 4 * * * $CFDATA_DIR/cfdata-update.sh >/dev/null 2>&1"

# 反代模式: none = 直连 (默认, 程序监听 0.0.0.0:13335, 局域网直接访问)
#           nginx = 自动配置纯 HTTP 反代 (无 SSL, 端口默认 8080, 可用 PROXY_PORT 改)
PROXY=${PROXY:-none}
PROXY_PORT=${PROXY_PORT:-8080}

LUCI_RPCD_DIR=${LUCI_RPCD_DIR:-/usr/share/rpcd/ucode}
LUCI_ACL_DIR=${LUCI_ACL_DIR:-/usr/share/rpcd/acl.d}
LUCI_MENU_DIR=${LUCI_MENU_DIR:-/usr/share/luci/menu.d}
LUCI_VIEW_DIR=${LUCI_VIEW_DIR:-/www/luci-static/resources/view/cfdata}

say() { echo "[CFData] $*"; }
die() { say "ERROR: $*"; exit 1; }

# ---------- 下载器: 多镜像回退 ----------
STAGE=$(dirname "$0")

# repo 文件: 本地(离线) -> raw.githubusercontent -> jsDelivr -> ghproxy
repo_fetch() { # $1=相对路径  $2=输出文件
    local path="$1" out="$2" u
    mkdir -p "$(dirname "$out")"
    if [ -f "$STAGE/$path" ]; then
        cp -f "$STAGE/$path" "$out" && return 0
    fi
    for u in \
        "https://raw.githubusercontent.com/$REPO_USER/$REPO_NAME/$BRANCH/$path" \
        "https://cdn.jsdelivr.net/gh/$REPO_USER/$REPO_NAME@$BRANCH/$path" \
        "https://ghproxy.net/https://raw.githubusercontent.com/$REPO_USER/$REPO_NAME/$BRANCH/$path"; do
        wget -q -T 30 -O "$out" "$u" 2>/dev/null && [ -s "$out" ] && return 0
    done
    return 1
}

# release 资产: github 直连 -> ghproxy -> gh-proxy
rel_fetch() { # $1=tag  $2=asset  $3=输出文件
    local tag="$1" asset="$2" out="$3" u
    for u in \
        "https://github.com/$CF_REPO/releases/download/$tag/$asset" \
        "https://ghproxy.net/https://github.com/$CF_REPO/releases/download/$tag/$asset" \
        "https://gh-proxy.com/https://github.com/$CF_REPO/releases/download/$tag/$asset"; do
        wget -q -T 180 -O "$out" "$u" 2>/dev/null && [ -s "$out" ] && return 0
    done
    return 1
}

# 最新 release 信息
api_fetch() { # $1=输出文件
    local u
    for u in \
        "https://api.github.com/repos/$CF_REPO/releases/latest" \
        "https://ghproxy.net/https://api.github.com/repos/$CF_REPO/releases/latest"; do
        wget -q -T 30 -O "$1" "$u" 2>/dev/null && [ -s "$1" ] && return 0
    done
    return 1
}

# ---------- 架构探测 ----------
case "$(uname -m)" in
    aarch64|arm64) ASSET="cfdata-linux-arm64" ;;
    x86_64|amd64)  ASSET="cfdata-linux-amd64" ;;
    *) die "不支持的架构: $(uname -m) (仅支持 arm64/amd64)" ;;
esac

# ---------- 1/4 下载并安装二进制 ----------
mkdir -p "$CFDATA_DIR"
if [ "${SKIP_BIN:-0}" != "1" ]; then
    say "检查最新版本..."
    api_fetch /tmp/cfdata-rel.json || die "获取 Release 信息失败 (网络问题?), 可用 SKIP_BIN=1 跳过二进制"

    TAG=$(grep -o '"tag_name": *"[^"]*"' /tmp/cfdata-rel.json | head -1 | sed 's/.*"tag_name": *"//; s/"$//')
    [ -z "$TAG" ] && die "解析版本号失败"

    CUR=$(cat "$CFDATA_DIR/VERSION" 2>/dev/null)
    if [ "$CUR" = "$TAG" ] && [ -x "$CFDATA_DIR/cfdata" ]; then
        say "已是最新 $TAG, 跳过二进制下载"
    else
        say "下载 $ASSET ($TAG) ..."
        rel_fetch "$TAG" "$ASSET" /tmp/cfdata-bin || die "二进制下载失败 (直连+镜像均失败)"

        rel_fetch "$TAG" "$ASSET.sha256" /tmp/cfdata-bin.sha256
        if [ -s /tmp/cfdata-bin.sha256 ]; then
            EXPECT=$(awk '{print $1}' /tmp/cfdata-bin.sha256)
            ACTUAL=$(sha256sum /tmp/cfdata-bin | awk '{print $1}')
            [ -n "$EXPECT" ] && [ "$EXPECT" = "$ACTUAL" ] || die "sha256 校验失败 ($ACTUAL != $EXPECT)"
            say "sha256 校验通过"
        fi

        chmod +x /tmp/cfdata-bin
        [ -f "$CFDATA_DIR/cfdata" ] && mv -f "$CFDATA_DIR/cfdata" "$CFDATA_DIR/cfdata.bak"
        mv /tmp/cfdata-bin "$CFDATA_DIR/cfdata"
        echo "$TAG" > "$CFDATA_DIR/VERSION"
        echo "$TAG" > "$CFDATA_DIR/LATEST"
        say "二进制就绪: $CFDATA_DIR/cfdata ($TAG)"
    fi
fi

# ---------- 2/4 安装更新脚本 + 服务脚本 ----------
say "安装更新脚本..."
repo_fetch "files/cfdata-update.sh" "$CFDATA_DIR/cfdata-update.sh" || die "下载 cfdata-update.sh 失败"
chmod +x "$CFDATA_DIR/cfdata-update.sh"

say "安装服务脚本..."
repo_fetch "files/cfdata.init" "$INIT_SCRIPT" || die "下载 cfdata.init 失败"
chmod +x "$INIT_SCRIPT"

say "初始化配置 (uci)..."
if [ ! -f /etc/config/cfdata ]; then
    cat > /etc/config/cfdata <<'EOF' 2>/dev/null || say "WARN: 无法写入 /etc/config/cfdata (端口将使用默认 13335)"
config cfdata 'main'
	option port '13335'
EOF
fi

if [ "${NO_SERVICE:-0}" != "1" ]; then
    $INIT_SCRIPT enable 2>/dev/null || say "WARN: enable 失败"
    $INIT_SCRIPT start 2>/dev/null || say "WARN: start 失败 (可能已在运行或二进制缺失)"
else
    say "NO_SERVICE=1, 跳过服务启停"
fi

# ---------- 3/4 配置每日自动更新 ----------
if [ "${NO_SERVICE:-0}" != "1" ]; then
    mkdir -p "$(dirname "$CRONTAB")"
    grep -q 'cfdata-update' "$CRONTAB" 2>/dev/null || echo "$CRON_LINE" >> "$CRONTAB"
    /etc/init.d/cron restart 2>/dev/null || say "WARN: cron 重启失败"
    say "每日 4:00 自动检查更新已配置"
fi

# ---------- 4/4 安装 LuCI 页面 ----------
say "安装 LuCI 页面..."
mkdir -p "$LUCI_RPCD_DIR" "$LUCI_ACL_DIR" "$LUCI_MENU_DIR" "$LUCI_VIEW_DIR"

repo_fetch "files/luci/rpcd/cfdata.uc"  "$LUCI_RPCD_DIR/cfdata.uc"  || die "下载 cfdata.uc 失败"
repo_fetch "files/luci/acl.d/luci-app-cfdata.json" "$LUCI_ACL_DIR/luci-app-cfdata.json" || die "下载 acl 失败"
repo_fetch "files/luci/menu.d/luci-app-cfdata.json" "$LUCI_MENU_DIR/luci-app-cfdata.json" || die "下载 menu 失败"
repo_fetch "files/luci/htdocs/cfdata/status.js" "$LUCI_VIEW_DIR/status.js" || die "下载 status.js 失败"

if [ "${NO_SERVICE:-0}" != "1" ]; then
    # 重启 rpcd 注册 ubus 对象 + 加载 ACL
    /etc/init.d/rpcd restart 2>/dev/null || say "WARN: rpcd 重启失败, LuCI 页可能不可用"
    # 清 LuCI 菜单缓存
    rm -f /tmp/luci-indexcache* /tmp/luci-modulecache/* 2>/dev/null
    say "rpcd 已重启 (LuCI 如被登出, 重新登录一次即可)"
else
    say "NO_SERVICE=1, 跳过 rpcd 重启"
fi

# ---------- 5/5 可选: nginx 纯 HTTP 反代 (无 SSL) ----------
if [ "$PROXY" = "nginx" ]; then
    if [ ! -x /etc/init.d/nginx ]; then
        say "WARN: 未检测到 nginx, 请先 opkg install nginx; 或去掉 PROXY=nginx 用直连模式"
    elif [ "${NO_SERVICE:-0}" = "1" ]; then
        say "NO_SERVICE=1, 跳过 nginx 配置"
    else
        say "配置 nginx 纯 HTTP 反代 (端口 $PROXY_PORT)..."
        mkdir -p /etc/nginx/conf.d
        cat > /etc/nginx/conf.d/cfdata.proxy <<'EOF'
location / {
    proxy_pass http://127.0.0.1:13335;

    client_max_body_size 10m;   # 上传 IP 列表文件用, 默认 1m 会 413

    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto http;

    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";

    proxy_buffering off;        # 扫描进度流式输出
    proxy_read_timeout 1h;      # 长任务防断
    proxy_send_timeout 1h;
}
EOF
        uci -q delete nginx.cfdata
        uci set nginx.cfdata=server
        uci set nginx.cfdata.listen="0.0.0.0:$PROXY_PORT"
        uci set nginx.cfdata.server_name='_'
        uci set nginx.cfdata.include='conf.d/cfdata.proxy'
        uci set nginx.cfdata.access_log='off; # logd openwrt'
        uci commit nginx
        /etc/init.d/nginx restart 2>/dev/null || say "WARN: nginx 重启失败, 检查 /etc/nginx/nginx.conf"
        say "HTTP 反代已配置"
    fi
fi

say "=============================================="
say "部署完成!"
say "  LuCI 页面:  服务 -> CFData-Web"
say "  局域网直连: http://$(uci -q get network.lan.ipaddr 2>/dev/null || echo '<路由器IP>'):13335"
say "  手动更新:   $CFDATA_DIR/cfdata-update.sh --force"
say "  服务控制:   $INIT_SCRIPT {start|stop|restart|status}"
say "  运行日志:   logread -e cfdata"
say "  更新日志:   tail -f $CFDATA_DIR/update.log"
if [ "$PROXY" = "nginx" ]; then
    say "  HTTP 反代: http://$(uci -q get network.lan.ipaddr 2>/dev/null || echo '<路由器IP>'):$PROXY_PORT"
fi
say "=============================================="
