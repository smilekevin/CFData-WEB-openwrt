'use strict';

/*
 * CFData-Web LuCI 后端 (rpcd ucode 插件)
 *
 * 安装位置: /usr/share/rpcd/ucode/cfdata.uc
 * 注册 ubus 对象: cfdata
 *   方法: status / start / stop / restart / update
 * 安装后需重启 rpcd: /etc/init.d/rpcd restart
 *
 * 兼容性注意 (踩坑记录):
 * - shell 调用: fs.popen + read('line') 循环 (tailscale.uc 同款)
 * - ucode 数组没有 .push(), 字符串没有 .length 属性
 *   -> 一律用全局 length() 和字符串拼接
 * - 不用 sprintf, 直接 'str' + value 拼接
 * - 所有可能抛错的地方都 try/catch, 错误转成 errors 字段返回
 */

import { popen } from 'fs';

const CFDATA_DIR   = '/opt/cfdata';
const INIT_SCRIPT  = '/etc/init.d/cfdata';
const VERSION_FILE = CFDATA_DIR + '/VERSION';
const LATEST_FILE  = CFDATA_DIR + '/LATEST';
const LOG_FILE     = CFDATA_DIR + '/update.log';

/* 执行 shell 命令并捕获 stdout+stderr, 任何异常都转成返回值 */
function run(cmd) {
    let out = '';
    let code = -1;

    try {
        let p = popen(cmd + ' 2>&1', 'r');
        sleep(100);

        if (p == null)
            return { ok: false, output: '执行失败: ' + cmd };

        for (let line = p.read('line'); length(line); line = p.read('line'))
            out += line;

        code = p.close() || 0;
    }
    catch (e) {
        return { ok: false, output: '命令异常: ' + e };
    }

    return { ok: (code == 0), output: out };
}

/* 只取输出 */
function sh(cmd) {
    return run(cmd).output;
}

/* 读文件第一行 */
function read_first_line(path) {
    return trim(sh('head -n1 ' + path + ' 2>/dev/null'));
}

/* 是否在运行 */
function is_running() {
    return length(sh('pidof cfdata 2>/dev/null')) > 0;
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
    let errs = '';

    try { res.running = is_running(); }
    catch (e) { errs += 'running: ' + e + ' | '; }

    try { res.version = read_first_line(VERSION_FILE); }
    catch (e) { errs += 'version: ' + e + ' | '; }

    try { res.latest = read_first_line(LATEST_FILE); }
    catch (e) { errs += 'latest: ' + e + ' | '; }

    try { res.enabled = length(sh('ls -d /etc/rc.d/S*cfdata 2>/dev/null')) > 0; }
    catch (e) { errs += 'enabled: ' + e + ' | '; }

    try { res.log = sh('tail -n 25 ' + LOG_FILE + ' 2>/dev/null'); }
    catch (e) { errs += 'log: ' + e + ' | '; }

    if (length(errs) > 0)
        res.errors = errs;

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
