import Foundation

/// 局域网网页面板：一张自包含的 HTML（内联 CSS + JS，不联网取任何资源），
/// 配色与状态词跟浮窗 / 详情面板同一套，手机上打开就能看、能加载卸载模型、能测速
enum LanDashboard {
    static let html = #"""
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#0e1116">
<title>oMLX 小工具</title>
<style>
:root {
  color-scheme: dark light;
  --bg: #0e1116; --card: #171b22; --inset: #1d222b;
  --ink: #e8ecf3; --muted: #97a1b1; --line: #262c36;
}
@media (prefers-color-scheme: light) {
  :root { --bg: #eef1f6; --card: #ffffff; --inset: #f4f6fa; --ink: #161a20; --muted: #6a7482; --line: #e1e6ee; }
}
* { box-sizing: border-box; }
body {
  margin: 0; background: var(--bg); color: var(--ink);
  font: 14px/1.45 -apple-system, "PingFang SC", "Helvetica Neue", sans-serif;
  -webkit-text-size-adjust: 100%;
}
#app { max-width: 420px; margin: 0 auto; padding: 12px 12px 28px; display: grid; gap: 10px; }
@media (min-width: 720px) { #app { max-width: 760px; } #pair { grid-template-columns: 1fr 1fr; } }
header { display: flex; align-items: center; gap: 9px; padding: 2px 2px 0; }
.dot { width: 11px; height: 11px; border-radius: 50%; background: #739eeb; flex: none; }
.dot.pulse { animation: pulse 1.1s ease-in-out infinite; }
@keyframes pulse { 50% { opacity: .35; } }
.head { flex: 1; min-width: 0; }
.head b { display: block; font-size: 13px; font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.head span { display: block; font-size: 11px; color: var(--muted); font-variant-numeric: tabular-nums; }
button {
  font: inherit; font-size: 12px; color: var(--ink); background: var(--inset);
  border: 1px solid var(--line); border-radius: 8px; padding: 7px 11px; min-height: 32px;
}
button:active { opacity: .6; }
button.primary { border-color: transparent; color: #06131f; background: #4fc2f7; font-weight: 600; }
button:disabled { opacity: .45; }
.card {
  position: relative; overflow: hidden; background: var(--card);
  border: 1px solid var(--line); border-radius: 14px; padding: 12px;
}
.card h3 { margin: 0 0 9px; font-size: 11px; font-weight: 600; letter-spacing: .04em; color: var(--muted); }
.row { display: flex; align-items: baseline; justify-content: space-between; gap: 8px; }
.big { font-size: 40px; font-weight: 700; letter-spacing: -.02em; font-variant-numeric: tabular-nums; line-height: 1; }
.unit { font-size: 13px; color: var(--muted); margin-left: 4px; }
.pill { font-size: 11px; font-weight: 600; padding: 3px 8px; border-radius: 999px; }
#spark { display: block; width: 100%; height: 58px; margin: 6px 0 4px; }
.legend { display: flex; flex-wrap: wrap; gap: 4px 10px; font-size: 11px; color: var(--muted); font-variant-numeric: tabular-nums; }
.legend i { width: 8px; height: 8px; border-radius: 2px; display: inline-block; margin-right: 4px; }
.metrics { display: flex; justify-content: space-between; gap: 8px; font-size: 11px; color: var(--muted); margin-top: 7px; font-variant-numeric: tabular-nums; }
.water {
  position: absolute; left: 0; right: 0; bottom: 0; height: 0; pointer-events: none;
  background: linear-gradient(180deg, rgba(87,168,250,.32), rgba(87,168,250,.04));
  border-top: 1px solid rgba(120,190,255,.75); transition: height .45s ease;
}
.stack { position: relative; z-index: 1; }
#pair { display: grid; gap: 10px; }
.bar { position: relative; height: 9px; border-radius: 99px; background: var(--inset); overflow: hidden; margin: 7px 0 6px; }
.bar i { position: absolute; inset: 0 auto 0 0; border-radius: 99px; transition: width .4s ease, background .4s ease; }
.bar u { position: absolute; top: -2px; bottom: -2px; width: 2px; background: rgba(230,87,82,.85); }
.kv { display: flex; justify-content: space-between; gap: 8px; font-size: 12px; padding: 3px 0; font-variant-numeric: tabular-nums; }
.kv span { color: var(--muted); }
.tok { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; margin-bottom: 9px; }
.tok div { background: var(--inset); border-radius: 10px; padding: 7px 8px; }
.tok b { display: block; font-size: 16px; font-variant-numeric: tabular-nums; }
.tok span { font-size: 10px; color: var(--muted); }
#heat { display: flex; align-items: flex-end; gap: 2px; height: 42px; }
#heat i { flex: 1; min-height: 2px; border-radius: 2px 2px 0 0; background: #4fc2f7; opacity: .85; }
#heat i.now { background: #4dcc8c; opacity: 1; }
.model { display: flex; align-items: center; gap: 8px; padding: 7px 0; border-top: 1px solid var(--line); }
.model:first-child { border-top: 0; }
.model .name { flex: 1; min-width: 0; }
.model .name b { display: block; font-size: 12px; font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.model .name span { display: block; font-size: 10.5px; color: var(--muted); font-variant-numeric: tabular-nums; }
.badge { font-size: 10px; padding: 2px 6px; border-radius: 999px; flex: none; }
.banner { font-size: 12px; padding: 9px 11px; border-radius: 12px; background: rgba(230,87,82,.14); border: 1px solid rgba(230,87,82,.4); }
.banner.warn { background: rgba(250,199,77,.14); border-color: rgba(250,199,77,.42); }
.banner input { font: inherit; font-size: 12px; padding: 6px 8px; border-radius: 8px; border: 1px solid var(--line); background: var(--inset); color: var(--ink); width: 100%; margin-top: 7px; }
.hidden { display: none !important; }
.notice { font-size: 12px; padding: 9px 11px; border-radius: 12px; background: rgba(77,204,140,.14); border: 1px solid rgba(77,204,140,.4); }
footer { font-size: 10.5px; color: var(--muted); text-align: center; padding: 4px 0 0; }
footer a { color: #4fc2f7; text-decoration: none; }
</style>
</head>
<body>
<div id="app">
  <header>
    <div class="dot" id="dot"></div>
    <div class="head"><b id="server">正在连接小工具…</b><span id="sub"></span></div>
    <button id="refresh">刷新</button>
    <button id="probe">测速</button>
  </header>
  <div class="banner hidden" id="banner"></div>
  <div class="notice hidden" id="notice"></div>
  <div class="card" id="speed">
    <div class="water" id="water"></div>
    <div class="stack">
      <div class="row">
        <div><span class="big" id="tps">0</span><span class="unit">t/s</span></div>
        <span class="pill" id="kind">—</span>
      </div>
      <svg id="spark" viewBox="0 0 300 58" preserveAspectRatio="none"></svg>
      <div class="legend" id="legend"></div>
      <div class="metrics"><span id="queue"></span><span id="prefill"></span></div>
    </div>
  </div>
  <div id="pair">
    <div class="card">
      <h3>统一内存</h3>
      <div class="row"><span class="big" id="mem-percent" style="font-size:26px">—</span><span class="pill" id="mem-label">—</span></div>
      <div class="bar"><i id="mem-fill" style="width:0%"></i><u id="mem-soft" class="hidden"></u><u id="mem-hard" class="hidden"></u></div>
      <div class="kv"><span>已用 / 上限</span><b id="mem-bytes">—</b></div>
      <div class="kv"><span>模型</span><b id="models-count">—</b></div>
    </div>
    <div class="card">
      <h3>GPU 与温度</h3>
      <div class="row"><span class="big" id="gpu-percent" style="font-size:26px">—</span><span class="pill" id="heat-label">—</span></div>
      <div class="bar"><i id="gpu-fill" style="width:0%"></i></div>
      <div class="kv"><span>温度 / 功耗</span><b id="gpu-detail">—</b></div>
      <div class="kv"><span>来源</span><b id="gpu-source">—</b></div>
    </div>
  </div>
  <div class="card">
    <h3>今日用量</h3>
    <div class="tok">
      <div><b id="t-requests">—</b><span>请求数</span></div>
      <div><b id="t-tokens">—</b><span>tokens</span></div>
      <div><b id="t-cache">—</b><span>缓存命中</span></div>
      <div><b id="t-avg">—</b><span>平均耗时</span></div>
    </div>
    <div id="heat"></div>
    <div class="metrics"><span>近 24 小时 token 分布</span><span id="week"></span></div>
  </div>
  <div class="card">
    <h3>模型</h3>
    <div id="models">正在读取…</div>
  </div>
  <footer id="footer"></footer>
</div>
<script>
const KIND = { offline: '#e65752', idle: '#739eeb', busy: '#4dcc8c', loading: '#fab840' };
const BANDS = ['#4dcc8c', '#5cadf5', '#fac74d', '#e65752'];
const BAND_WORDS = ['充裕', '正常', '偏高', '吃紧'];
const HEAT_WORDS = { '正常': '#4dcc8c', '偏热': '#fac74d', '很热': '#ff9e45', '过热': '#e65752', '未知': '#97a1b1' };
const TASKS = ['#4fc2f7', '#ffc43d', '#ff7aab', '#a68cfa', '#2ed4bf', '#ff9e45', '#a3e636', '#7d9cff'];
const PREFILL = '#57a8fa';
const duty = [[0, '#4a7fd6'], [35, '#2ed4bf'], [65, '#4dcc8c'], [80, '#fac74d'], [100, '#ff8a3d']];

const urlKey = new URLSearchParams(location.search).get('key') || '';
if (urlKey) { localStorage.setItem('omlx-key', urlKey); }
function currentKey() { return localStorage.getItem('omlx-key') || urlKey; }
const el = (id) => document.getElementById(id);
let busyButton = false;

function shortName(id) {
  const parts = String(id).split('/');
  return parts[parts.length - 1];
}
function esc(value) {
  const node = document.createElement('div');
  node.textContent = value === null || value === undefined ? '' : String(value);
  return node.innerHTML;
}
function num(value, digits) {
  if (value === null || value === undefined || !isFinite(value)) return '—';
  return value.toFixed(digits === undefined ? 1 : digits);
}
function pct(value) {
  if (value === null || value === undefined || !isFinite(value)) return '—';
  return Math.round(value) + '%';
}
function bandIndex(percent) {
  const value = Math.round(percent);
  if (value <= 75) return 0;
  if (value <= 80) return 1;
  if (value <= 90) return 2;
  return 3;
}
function dutyColor(value) {
  let color = duty[0][1];
  duty.forEach((stop) => { if (value >= stop[0]) color = stop[1]; });
  return color;
}
function pill(node, text, color) {
  node.textContent = text;
  node.style.color = color;
  node.style.background = color + '22';
}

function sparkline(speed) {
  const curves = (speed.tasks || []).filter((task) => task.series && task.series.length > 1);
  const source = curves.length >= 2 ? curves : [{ series: speed.series, colorIndex: -1 }];
  let top = 1;
  source.forEach((task) => task.series.forEach((value) => { if (value > top) top = value; }));
  const width = 300;
  const height = 58;
  const paths = source.map((task) => {
    const values = task.series.slice(-60);
    const step = values.length > 1 ? width / (values.length - 1) : width;
    const points = values.map((value, index) => {
      const y = height - 2 - Math.min(1, value / top) * (height - 6);
      return (index * step).toFixed(1) + ',' + y.toFixed(1);
    });
    const color = task.colorIndex < 0 ? KIND.busy : TASKS[task.colorIndex % TASKS.length];
    const last = points[points.length - 1].split(',');
    return '<polyline fill="none" stroke="' + color + '" stroke-width="1.6" points="' + points.join(' ') + '"/>'
      + '<circle cx="' + last[0] + '" cy="' + last[1] + '" r="2" fill="' + color + '"/>';
  });
  el('spark').innerHTML = paths.join('');
}

function legend(speed) {
  const tasks = (speed.tasks || []).filter((task) => task.latest > 0.05).sort((a, b) => b.latest - a.latest);
  if (tasks.length < 2) return '';
  const shown = tasks.slice(0, 3).map((task) => {
    const color = TASKS[task.colorIndex % TASKS.length];
    return '<span><i style="background:' + color + '"></i>' + esc(task.label) + ' ' + num(task.latest, 1) + '</span>';
  });
  if (tasks.length > 3) shown.push('<span>+' + (tasks.length - 3) + '</span>');
  return shown.join('');
}

function heat(heatmap) {
  const top = Math.max.apply(null, heatmap.concat([1]));
  const hour = new Date().getHours();
  return heatmap.map((value, index) => {
    const height = Math.max(2, Math.round(value / top * 42));
    return '<i class="' + (index === hour ? 'now' : '') + '" style="height:' + height + 'px" title="' + index + ':00 ' + value + '"></i>';
  }).join('');
}

function models(list, offline) {
  if (!list || !list.length) return '没有发现模型';
  return list.map((model) => {
    const state = model.loading ? '<span class="badge" style="color:#fab840;background:#fab84022">载入中</span>'
      : (model.loaded ? '<span class="badge" style="color:#4dcc8c;background:#4dcc8c22">已加载</span>' : '');
    const meta = [model.sizeText, model.context ? 'ctx ' + model.context : '', model.pinned ? '常驻' : '', model.engine || '']
      .filter((piece) => piece && piece !== '—').join(' · ');
    const disabled = offline || model.loading ? ' disabled' : '';
    return '<div class="model"><div class="name"><b title="' + esc(model.id) + '">' + esc(shortName(model.id)) + '</b>'
      + '<span>' + esc(meta) + '</span></div>'
      + state
      + '<button data-id="' + esc(model.id) + '" data-loaded="' + (model.loaded ? 1 : 0) + '"' + disabled + '>'
      + (model.loaded ? '卸载' : '加载') + '</button></div>';
  }).join('');
}

function render(data) {
  const server = data.server;
  document.title = (server.kindLabel || 'oMLX') + ' · oMLX 小工具';
  el('server').textContent = server.name + '  ' + server.url;
  el('sub').textContent = (server.online ? '延迟 ' + num(server.latencyMillis, 0) + 'ms · 更新于 ' + (server.updatedAt || '—')
    : (server.error || '离线')) + ' · 页面每 ' + Math.round(data.pollSeconds) + ' 秒自取';
  const kindColor = KIND[server.kind] || KIND.idle;
  el('dot').style.background = kindColor;
  el('dot').className = 'dot' + (server.kind === 'busy' || server.kind === 'loading' ? ' pulse' : '');
  pill(el('kind'), server.kindLabel, kindColor);

  el('tps').textContent = num(data.speed.tps, data.speed.tps >= 100 ? 0 : 1);
  sparkline(data.speed);
  el('legend').innerHTML = legend(data.speed);
  el('queue').textContent = '请求中 ' + data.speed.activeRequests + ' · 排队 ' + data.speed.waitingRequests;

  if (data.prefill) {
    el('water').style.height = Math.max(3, data.prefill.percent) + '%';
    el('prefill').textContent = '预填充 ' + data.prefill.percent + '% · ' + num(data.prefill.speed, 0) + ' t/s · '
      + (data.prefill.processed || 0) + '/' + (data.prefill.total || 0) + ' tokens';
    el('speed').style.borderColor = PREFILL;
  } else {
    el('water').style.height = '0%';
    el('prefill').textContent = '';
    el('speed').style.borderColor = '';
  }

  const memory = data.memory;
  const hasMemory = memory.percent !== null && memory.percent !== undefined;
  el('mem-percent').textContent = hasMemory ? pct(memory.percent) : '—';
  const band = hasMemory ? bandIndex(memory.percent) : 0;
  pill(el('mem-label'), hasMemory ? BAND_WORDS[band] : '—', hasMemory ? BANDS[band] : '#97a1b1');
  el('mem-fill').style.width = (hasMemory ? Math.min(100, memory.percent) : 0) + '%';
  el('mem-fill').style.background = hasMemory ? BANDS[band] : 'transparent';
  el('mem-bytes').textContent = memory.usedText + ' / ' + memory.maxText;
  el('models-count').textContent = (data.models || []).filter((model) => model.loaded).length + ' 个已加载 · 共 ' + (data.models || []).length + ' 个';
  ['soft', 'hard'].forEach((name) => {
    const bytes = memory[name + 'Bytes'];
    const mark = el('mem-' + name);
    if (bytes && memory.max) { mark.classList.remove('hidden'); mark.style.left = Math.min(100, bytes / memory.max * 100) + '%'; }
    else { mark.classList.add('hidden'); }
  });

  const system = data.system;
  if (system) {
    const used = system.gpuDevice || 0;
    el('gpu-percent').textContent = num(used, 0) + '%';
    el('gpu-fill').style.width = Math.min(100, used) + '%';
    el('gpu-fill').style.background = dutyColor(used);
    pill(el('heat-label'), system.thermalLabel, HEAT_WORDS[system.thermalLabel] || '#97a1b1');
    el('gpu-detail').textContent = (system.temperatureGPU !== null && system.temperatureGPU !== undefined
      ? system.temperatureGPU.toFixed(0) : '—') + '°C / '
      + (system.powerTotal !== null && system.powerTotal !== undefined ? system.powerTotal.toFixed(0) : '—') + 'W';
    el('gpu-source').textContent = system.sourceLabel + (system.collectedAt ? ' · ' + system.collectedAt : '')
      + (system.error ? ' · ' + system.error : (system.macmonReady ? '' : ' · 无温度源'));
  } else {
    el('gpu-percent').textContent = '—';
    el('gpu-fill').style.width = '0%';
    pill(el('heat-label'), '—', '#97a1b1');
    el('gpu-detail').textContent = '没开采集或还没采到';
    el('gpu-source').textContent = '在跑小工具的这台机器设置';
  }

  const today = data.today || {};
  el('t-requests').textContent = today.requests === undefined ? '—' : today.requests;
  el('t-tokens').textContent = today.totalTokensText || '—';
  el('t-cache').textContent = today.cacheEfficiency === undefined || today.cacheEfficiency === null
    ? '—' : (today.cacheEfficiency * 100).toFixed(0) + '%';
  el('t-avg').textContent = today.averageSeconds === undefined || today.averageSeconds === null
    ? '—' : today.averageSeconds.toFixed(1) + 's';
  el('heat').innerHTML = heat(data.heatmap || []);
  el('week').textContent = data.week && data.week.totalTokensText ? '近 7 天 ' + data.week.totalTokensText : '';

  el('models').innerHTML = models(data.models, !server.online);
  el('footer').innerHTML = '数据来自 Mac 上的 oMLX 小工具 v' + esc(data.version)
    + (data.consoleURL ? ' · <a href="' + esc(data.consoleURL) + '">oMLX 控制台</a>' : '');

  const banner = el('banner');
  if (!server.online) {
    banner.className = 'banner';
    banner.innerHTML = '<b>连不上 oMLX</b><br>' + esc(server.error || '离线')
      + (server.needsAPIKey ? '<br>小工具里需要填 API Key（Mac 上右键菜单栏图标 → 设置… → 服务器）' : '');
  } else if (data.notice) {
    banner.className = 'banner hidden';
  } else {
    banner.className = 'banner hidden';
  }
  const notice = el('notice');
  if (data.notice) { notice.className = 'notice'; notice.textContent = data.notice; }
  else { notice.className = 'notice hidden'; }
}

function askKey() {
  const banner = el('banner');
  banner.className = 'banner warn';
  banner.innerHTML = '<b>这个页面设了访问口令</b><br>填一次就好，会记在这台设备的浏览器里';
  const input = document.createElement('input');
  input.placeholder = '访问口令';
  input.autocapitalize = 'none';
  const button = document.createElement('button');
  button.textContent = '好';
  button.className = 'primary';
  button.style.marginTop = '7px';
  button.onclick = () => {
    localStorage.setItem('omlx-key', input.value.trim());
    banner.className = 'banner hidden';
    poll();
  };
  banner.appendChild(input);
  banner.appendChild(button);
}

async function action(payload) {
  if (busyButton) return;
  busyButton = true;
  el('refresh').disabled = true;
  el('probe').disabled = true;
  try {
    await fetch('api/action?key=' + encodeURIComponent(currentKey()), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
  } catch (error) { /* 下一轮轮询会反映结果 */ }
  busyButton = false;
  el('refresh').disabled = false;
  el('probe').disabled = false;
  poll();
}

let timer = null;
async function poll() {
  if (timer) { clearTimeout(timer); timer = null; }
  try {
    const response = await fetch('api/snapshot?key=' + encodeURIComponent(currentKey()), { cache: 'no-store' });
    if (response.status === 401) { askKey(); return; }
    const data = await response.json();
    render(data);
    timer = setTimeout(poll, Math.max(1, data.pollSeconds || 3) * 1000);
  } catch (error) {
    const banner = el('banner');
    banner.className = 'banner';
    banner.innerHTML = '<b>取不到数据</b><br>' + esc(error.message) + '<br>小工具还在运行吗？';
    timer = setTimeout(poll, 4000);
  }
}

el('refresh').onclick = () => action({ action: 'refresh' });
el('probe').onclick = () => action({ action: 'probe' });
el('models').addEventListener('click', (event) => {
  const button = event.target.closest('button');
  if (!button) return;
  action({ action: 'toggle', id: button.dataset.id, loaded: button.dataset.loaded === '1' });
});
document.addEventListener('visibilitychange', () => {
  if (document.hidden) { if (timer) { clearTimeout(timer); timer = null; } }
  else { poll(); }
});
poll();
</script>
</body>
</html>
"""#
}
