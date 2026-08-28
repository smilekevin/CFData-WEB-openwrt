'use strict';

/*
 * CFData-Web LuCI 后端 (rpcd ucode 插件)
 *
 * 安装位置: /usr/share/rpcd/ucode/cfdata.uc
 * 注册 ubus 对象: cfdata
 *   方法: status / start / stop / restart / update
 * 安装后需重启 rpcd: /etc/init.d/rpcd restart
 */

import * as fs from 'fs';

const CFDATA_DIR   = '/opt/cfdata';
const INIT_SCRIPT  = '/etc/init.d/cfdata';
const BIN_FILE     = CFDATA_DIR + '/cfdata';
const VERSION_FILE = CFDATA_DIR + '/VERSION';
const LATEST_FILE  = CFDATA_DIR + '/LATEST';
const LOG_FILE     = CFDATA_DIR + '/update.log';

/* 执行 shell 命令并捕获 stdout+stderr, 返回 { ok, output } */
function run(cmd) {
    let proc = fs.popen(cmd + ' 2>&1', 'r');

    if (!proc)
        return { ok: false, output: '无法执行: ' + cmd };

    let out = proc.read('all') || '';
    let code = proc.close() || 0;

    return { ok: (code == 0), output: trim(out) };
}

/* 只取输出内容 (丢弃退出码) */
function sh(cmd) {
    return run(cmd).output;
}

/* 读文件第一行 (trim 掉换行) */
function read_first_line(path) {
    return trim(sh('head -n1 ' + path + ' 2>/dev/null'));
}

/* 是否在运行: 优先查 procd, 兜底 pidof */
function is_running() {
    let out = sh('ubus call service list \'{"name":"cfdata"}\' 2>/dev/null');

    if (out.indexOf('"running": true') >= 0)
        return true;

    if (out.length > 0)
        return false;

    return sh('pidof cfdata 2>/dev/null').length > 0;
}

function status() {
    return {
        running: is_running(),
        version: read_first_line(VERSION_FILE),
        latest:  read_first_line(LATEST_FILE),
        enabled: sh('ls -d /etc/rc.d/S*cfdata 2>/dev/null').length > 0,
        log:     sh('tail -n 25 ' + LOG_FILE + ' 2>/dev/null')
    };
}

function action(name) {
    return run(INIT_SCRIPT + ' ' + name);
}

function trigger_update() {
    system('(' + CFDATA_DIR + '/cfdata-update.sh >/dev/null 2>&1 &)');

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
