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

	refresh: function() {
		var self = this;

		callStatus().then(function(res) {
			var running = !!(res && res.running);
			self.statusEl.textContent = running ? '运行中' : '已停止';
			self.statusEl.className = 'cbi-button cbi-button-' + (running ? 'positive' : 'negative');
			self.versionEl.textContent = (res && res.version) || '未安装';
			self.latestEl.textContent = (res && res.latest) || '-';
			self.enabledEl.textContent = (res && res.enabled) ? '已启用' : '未启用';
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
