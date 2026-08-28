#!/bin/sh
# ============================================================
# CFData-WEB-openwrt 卸载脚本 (OpenWrt / busybox ash)
# 用法: sh uninstall.sh [--purge]
#       --purge 连 /opt/cfdata 数据目录一起删除
# ============================================================

CFDATA_DIR=${CFDATA_DIR:-/opt/cfdata}
INIT_SCRIPT=${INIT_SCRIPT:-/etc/init.d/cfdata}
CRONTAB=${CRONTAB:-/etc/crontabs/root}
LUCI_RPCD_DIR=${LUCI_RPCD_DIR:-/usr/share/rpcd/ucode}
LUCI_ACL_DIR=${LUCI_ACL_DIR:-/usr/share/rpcd/acl.d}
LUCI_MENU_DIR=${LUCI_MENU_DIR:-/usr/share/luci/menu.d}
LUCI_VIEW_DIR=${LUCI_VIEW_DIR:-/www/luci-static/resources/view/cfdata}

say() { echo "[CFData] $*"; }

say "停止并移除服务..."
$INIT_SCRIPT stop 2>/dev/null
$INIT_SCRIPT disable 2>/dev/null
rm -f "$INIT_SCRIPT" /etc/rc.d/S99cfdata /etc/rc.d/K10cfdata

say "移除 LuCI 文件..."
rm -f "$LUCI_RPCD_DIR/cfdata.uc"
rm -f "$LUCI_ACL_DIR/luci-app-cfdata.json"
rm -f "$LUCI_MENU_DIR/luci-app-cfdata.json"
rm -rf "$LUCI_VIEW_DIR"

say "移除 cron 任务..."
grep -v 'cfdata-update' "$CRONTAB" 2>/dev/null > "$CRONTAB.tmp" && mv "$CRONTAB.tmp" "$CRONTAB"

if [ "$1" = "--purge" ]; then
    say "删除数据目录 $CFDATA_DIR ..."
    rm -rf "$CFDATA_DIR"
else
    say "保留数据目录 $CFDATA_DIR (如需删除: sh uninstall.sh --purge)"
fi

/etc/init.d/rpcd restart 2>/dev/null
rm -f /tmp/luci-indexcache* /tmp/luci-modulecache/* 2>/dev/null

say "卸载完成"
