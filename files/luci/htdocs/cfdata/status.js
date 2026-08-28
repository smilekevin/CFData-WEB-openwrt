'use strict';
'require rpc';

var callStatus = rpc.declare({
	object: 'cfdata',
	method: 'status',
	reject: true,
	expect: { '': {} }
});

var callStart   = rpc.declare({ object: 'cfdata', method: 'start',   reject: true, expect: { '': {} } });
var callStop    = rpc.declare({ object: 'cfdata', method: 'stop',    reject: true, expect: { '': {} } });
var callRestart = rpc.declare({ object: 'cfdata', method: 'restart', reject: true, expect: { '': {} } });
var callUpdate  = rpc.declare({ object: 'cfdata', method: 'update',  reject: true, expect: { '': {} } });
var callSetPort = rpc.declare({
	object: 'cfdata',
	method: 'set_port',
	params: [ 'port' ],
	reject: true,
	expect: { '': {} }
});

function actionBtn(name, label, cls, handler) {
	return E('button', {
		'class': 'cbi-button ' + cls,
		'click': function(ev) {
			ev.target.disabled = true;
			handler().finally(function() {
				ev.target.disabled = false;
			});
		}
	}, label);
}

return L.view.extend({
	render: function() {
		var self = this;

		this.statusEl  = E('strong', { 'class': 'cbi-button cbi-button-negative' }, '查询中...');
		this.versionEl = E('span', {}, '-');
		this.latestEl  = E('span', {}, '-');
		this.enabledEl = E('span', {}, '-');
		this.urlEl     = E('a', { 'href': '#', 'target': '_blank', 'rel': 'noreferrer' }, '-');
		this.portInput = E('input', {
			'class': 'cbi-input-text',
			'type': 'number',
			'min': 1,
			'max': 65535,
			'style': 'width:90px;margin-right:8px'
		});
		this.resultEl  = E('pre', { 'style': 'white-space:pre-wrap;margin:0' }, '');
		this.logEl     = E('textarea', {
			'class': 'cbi-input-textarea',
			'readonly': 'readonly',
			'style': 'width:100%;height:180px;font-family:monospace;font-size:12px'
		}, '');

		var btns = E('div', { 'style': 'margin:8px 0' }, [
			actionBtn('start', '启动', 'cbi-button-action', function() { return self.action('start'); }),
			actionBtn('stop', '停止', 'cbi-button-negative', function() { return self.action('stop'); }),
			actionBtn('restart', '重启', 'cbi-button-action', function() { return self.action('restart'); }),
			actionBtn('update', '立即检查更新', 'cbi-button-positive', function() { return self.action('update'); })
		]);
		btns.querySelectorAll('button').forEach(function(b) { b.style.marginRight = '8px'; });

		var btnSavePort = E('button', { 'class': 'cbi-button cbi-button-apply' }, '保存并重启');
		btnSavePort.addEventListener('click', function(ev) {
			ev.target.disabled = true;
			self.setPort().finally(function() { ev.target.disabled = false; });
		});

		var table = E('table', { 'class': 'cbi-section-table' }, [
			E('tr', { 'class': 'cbi-section-table-titles' }, [
				E('th', { 'class': 'cbi-section-table-cell' }, '项目'),
				E('th', { 'class': 'cbi-section-table-cell' }, '状态')
			]),
			E('tr', {}, [
				E('td', { 'class': 'cbi-section-table-cell' }, '运行状态'),
				E('td', { 'class': 'cbi-section-table-cell' }, [ this.statusEl ])
			]),
			E('tr', {}, [
				E('td', { 'class': 'cbi-section-table-cell' }, '访问地址'),
				E('td', { 'class': 'cbi-section-table-cell' }, [ this.urlEl ])
			]),
			E('tr', {}, [
				E('td', { 'class': 'cbi-section-table-cell' }, '监听端口'),
				E('td', { 'class': 'cbi-section-table-cell' }, [ this.portInput, btnSavePort ])
			]),
			E('tr', {}, [
				E('td', { 'class': 'cbi-section-table-cell' }, '已安装版本'),
				E('td', { 'class': 'cbi-section-table-cell' }, [ this.versionEl ])
			]),
			E('tr', {}, [
				E('td', { 'class': 'cbi-section-table-cell' }, 'GitHub 最新版'),
				E('td', { 'class': 'cbi-section-table-cell' }, [ this.latestEl ])
			]),
			E('tr', {}, [
				E('td', { 'class': 'cbi-section-table-cell' }, '开机自启'),
				E('td', { 'class': 'cbi-section-table-cell' }, [ this.enabledEl ])
			])
		]);

		var content = E('div', {}, [
			E('h3', {}, 'CFData-Web 服务控制'),
			btns,
			table,
			E('h4', {}, '操作结果'),
			this.resultEl,
			E('h4', {}, '更新日志 (update.log)'),
			this.logEl
		]);

		this.refresh();

		return content;
	},

	action: function(name) {
		var self = this;
		var fn = { start: callStart, stop: callStop, restart: callRestart, update: callUpdate }[name];

		return fn().then(function(res) {
			if (res && res.output)
				self.resultEl.textContent = res.output;
			self.refresh();
		}).catch(function(e) {
			self.resultEl.textContent = '操作失败: ' + (e && e.message ? e.message : e);
		});
	},

	setPort: function() {
		var self = this;
		var port = parseInt(this.portInput.value, 10);

		if (!port || port < 1 || port > 65535) {
			this.resultEl.textContent = '端口必须是 1-65535 的整数';
			return Promise.resolve();
		}

		return callSetPort(port).then(function(res) {
			self.resultEl.textContent = (res && res.output) || '已保存';
			self.refresh();
		}).catch(function(e) {
			self.resultEl.textContent = '保存失败: ' + (e && e.message ? e.message : e);
		});
	},

	refresh: function() {
		var self = this;

		callStatus().then(function(res) {
			var running = !!(res && res.running);
			var port = (res && res.port) || '13335';
			var url = 'http://' + location.hostname + ':' + port;

			self.statusEl.textContent = running ? '运行中' : '已停止';
			self.statusEl.className = 'cbi-button cbi-button-' + (running ? 'positive' : 'negative');
			self.versionEl.textContent = (res && res.version) || '未安装';
			self.latestEl.textContent = (res && res.latest) || '-';
			self.enabledEl.textContent = (res && res.enabled) ? '已启用' : '未启用';
			self.urlEl.textContent = url;
			self.urlEl.href = url;
			self.portInput.value = port;
			self.logEl.value = (res && res.log) || '(暂无更新日志)';

			if (res && res.errors)
				self.resultEl.textContent = '⚠️ 后端错误: ' + res.errors;
		}).catch(function(e) {
			self.statusEl.textContent = '状态获取失败';
			self.resultEl.textContent = 'RPC 调用失败: ' + (e && e.message ? e.message : e);
		});

		/* 每 5 秒自动刷新, 页面离开后自动停止 */
		setTimeout(function() {
			if (document.body && document.body.contains(self.statusEl))
				self.refresh();
		}, 5000);
	}
});
