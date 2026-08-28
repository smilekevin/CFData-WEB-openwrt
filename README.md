# CFData-WEB-openwrt

[CFData-Web](https://github.com/PoemMisty/CFData-WEB) 在 OpenWrt 路由器上的一键部署方案：**自动更新 + 常驻服务 + LuCI 网页控制**。

- 🔄 每日 4:00 自动检查 GitHub 最新 Release，下载 → sha256 校验 → 原子替换 → 重启
- 🛡️ procd 常驻服务：崩溃自动拉起、开机自启
- 🌐 LuCI 网页：服务开关（启动/停止/重启）、一键检查更新、**访问链接直达**、**端口在线修改**、版本与日志
- 🇨🇳 国内网络友好：下载带多镜像回退（直连 → jsDelivr → ghproxy）

## 一键部署

在路由器上执行（任选其一）：

```sh
# 直连 GitHub
wget -O- https://raw.githubusercontent.com/smilekevin/CFData-WEB-openwrt/main/install.sh | sh

# 国内镜像 (jsDelivr)
wget -O- https://cdn.jsdelivr.net/gh/smilekevin/CFData-WEB-openwrt@main/install.sh | sh

# 或先下载再执行 (便于看错误输出)
wget -O /tmp/install.sh https://raw.githubusercontent.com/smilekevin/CFData-WEB-openwrt/main/install.sh
sh /tmp/install.sh
```

装完：

- **LuCI** → 服务 → **CFData-Web** 即可控制
- 局域网直连 `http://<路由器IP>:13335`（详见下方"访问方式"）

## 访问方式

程序**实测监听所有网卡**（`0.0.0.0:13335`，日志里的 localhost 只是显示文案），局域网设备直接访问：

- **局域网直连（默认，零配置）**：`http://<路由器IP>:13335`

> ⚠️ 安全提醒：程序默认**无登录认证**。仅限局域网/内网使用时直连即可；
> 若要暴露到公网，务必启用认证（`echo '-user admin -password 你的密码' > /opt/cfdata/ARGS` 后
> `/etc/init.d/cfdata restart`）或走 VPN/Tailscale，别裸奔。

## 安装内容

| 文件 | 安装位置 | 说明 |
|---|---|---|
| `files/cfdata-update.sh` | `/opt/cfdata/cfdata-update.sh` | 自动更新器（含镜像链） |
| `files/cfdata.init` | `/etc/init.d/cfdata` | procd 常驻服务 |
| `files/luci/rpcd/cfdata.uc` | `/usr/share/rpcd/ucode/cfdata.uc` | LuCI 后端（ubus 对象 `cfdata`） |
| `files/luci/acl.d/luci-app-cfdata.json` | `/usr/share/rpcd/acl.d/` | 权限控制 |
| `files/luci/menu.d/luci-app-cfdata.json` | `/usr/share/luci/menu.d/` | 菜单入口 |
| `files/luci/htdocs/cfdata/status.js` | `/www/luci-static/resources/view/cfdata/` | 前端页面 |
| 二进制 | `/opt/cfdata/cfdata` | 当前版本（上一版备份为 `cfdata.bak`） |

其他：`/etc/crontabs/root` 添加每日 4:00 更新任务；配置/缓存（`cfdata-config.json`、`locations.json` 等）存于 `/opt/cfdata/`。

## 手动操作

```sh
# 服务控制
/etc/init.d/cfdata {start|stop|restart|status}
/etc/init.d/cfdata enable     # 开机自启 (安装时已启用)

# 端口配置 (uci, 默认 13335; 也可在 LuCI 页面直接改)
uci set cfdata.main.port=13336
uci commit cfdata
/etc/init.d/cfdata restart

# 高级参数: 写入 /opt/cfdata/ARGS (如启用认证)
echo '-user admin -password 你的密码' > /opt/cfdata/ARGS
/etc/init.d/cfdata restart

# 手动检查更新 (--force 忽略版本记录强制重下)
/opt/cfdata/cfdata-update.sh --force

# 日志
logread -e cfdata                       # 服务运行日志
tail -f /opt/cfdata/update.log          # 更新日志
```

## 卸载

```sh
sh uninstall.sh          # 保留 /opt/cfdata 数据
sh uninstall.sh --purge  # 连数据一起删
```

## 架构支持

- aarch64/arm64 → `cfdata-linux-arm64`（多数软路由/ARM 路由器）
- x86_64/amd64 → `cfdata-linux-amd64`

## 环境变量（可选）

| 变量 | 默认 | 说明 |
|---|---|---|
| `BRANCH` | `main` | 指定部署分支 |
| `SKIP_BIN` | - | `1` = 跳过二进制下载 |
| `NO_SERVICE` | - | `1` = 不执行启停/cron/rpcd 重启（离线预装场景） |
| `CFDATA_DIR` 等 | 见上表 | 覆盖安装路径 |

## 备注

- 服务监听 `0.0.0.0:13335`（实测），局域网默认可达；公网暴露请先启用认证或走 VPN。
- 安装后 rpcd 会重启以注册 ubus 对象与 ACL，LuCI 若被登出重新登录一次即可。
- 免责声明：CFData-Web 仅限学习研究用途，请遵守当地法律法规。
