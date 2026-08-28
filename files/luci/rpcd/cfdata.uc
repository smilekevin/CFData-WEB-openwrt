'use strict';

/*
 * CFData-Web LuCI 后端 (rpcd ucode 插件)
 *
 * 安装位置: /usr/share/rpcd/ucode/cfdata.uc
 * 注册 ubus 对象: cfdata
 *   方法: status / start / stop / restart / update
 * 安装后需重启 rpcd: /etc/init.d/rpcd restart
 *
 * 注意: shell 调用写法与 luci-app-tailscale-community 的
 * tailscale.uc 保持一致 (fs.popen + read('line') 循环),
 * 不依赖新版 ucode 才支持的 read('all')。
 */

import { popen } from 'fs';

const CFDATA_DIR   = '/opt/cfdata';
const INIT_SCRIPT  = '/etc/init.d/cfdata';
const VERSION_FILE = CFDATA_DIR + '/VERSION';
const LATEST_FILE  = CFDATA_DIR + '/LATEST';
const LOG_FILE     = CFDATA_DIR + '/update.log';

/* 执行 shell 命令并捕获 stdout+stderr */
function run(cmd) {
    let p = popen(cmd + ' 2>&1', 'r');
    sleep(100);

    if (p == null)
        return { ok: false, output: '执行失败: ' + cmd };

    let out = '';
    for (let line = p.read('line'); length(line); line = p.read('line'))
        out += line;

    let code = p.close() || 0;

    return { ok: (code == 0), output: rtrim(out) };
}

/* 只取输出 */
function sh(cmd) {
    return run(cmd).output;
}

/* 读文件第一行 (trim 掉换行) */
function read_first_line(path) {
    return trim(sh('head -n1 ' + path + ' 2>/dev/null'));
}

/* 是否在运行 */
function is_running() {
    return sh('pidof cfdata 2>/dev/null').length > 0;
}

function status() {
    let res = {
        running: false,
        version: '',
        latest:  '',
        enabled: false,
        log:     '',
        errors:  ''
    };
    let errs = [];

    try { res.running = is_running(); }
    catch (e) { errs.push('running: ' + sprintf('%s', e)); }

    try { res.version = read_first_line(VERSION_FILE); }
    catch (e) { errs.push('version: ' + sprintf('%s', e)); }

    try { res.latest = read_first_line(LATEST_FILE); }
    catch (e) { errs.push('latest: ' + sprintf('%s', e)); }

    try { res.enabled = sh('ls -d /etc/rc.d/S*cfdata 2>/dev/null').length > 0; }
    catch (e) { errs.push('enabled: ' + sprintf('%s', e)); }

    try { res.log = sh('tail -n 25 ' + LOG_FILE + ' 2>/dev/null'); }
    catch (e) { errs.push('log: ' + sprintf('%s', e)); }

    if (length(errs)) {
        res.errors = errs[0];
        for (let i = 1; i < length(errs); i++)
            res.errors += ' | ' + errs[i];
    }

    return res;
}

function action(name) {
    return run(INIT_SCRIPT + ' ' + name);
}

function trigger_update() {
    system(CFDATA_DIR + '/cfdata-update.sh >/dev/null 2>&1 &');

    return {
        ok: true,
        output: '更新已在后台启动, 几秒后刷新页面查看结果'
    };
}

return {
    cfdata: {
        status:  { call: function() { return status(); } },
        start:   { call: function() { return action('start'); } },
        stop:    { call: function() { return action('stop'); } },
        restart: { call: function() { return action('restart'); } },
        update:  { call: function() { return trigger_update(); } }
    }
};
