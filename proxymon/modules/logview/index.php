<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Logview — ProxyMon</title>
<style>
/* ── Reset & Base ─────────────────────────────────────────────── */
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;overflow:hidden}
body{
  font-family:'Segoe UI',system-ui,sans-serif;
  background:#f0f4f8;
  color:#1e2a35;
  display:flex;
  flex-direction:column;
  height:100vh;
  transition:background .2s,color .2s;
}
/* ── Dark mode ────────────────────────────────────────────────── */
body.dark{background:#0f1117;color:#e2e8f0}
body.dark .statsbar{background:#141721;color:#546e7a}
body.dark .statsbar b{color:#e2e8f0}
body.dark .logpath{color:#37474f}
body.dark .table-wrap{background:#0f1117}
body.dark tbody tr{border-bottom-color:#1a1f2e}
body.dark tbody tr:hover{background:#1a1d2e}
body.dark thead th{background:#1a1d2e;color:#607d8b;border-bottom-color:#0f1117}
body.dark .col-ts{color:#546e7a}
body.dark .col-client{color:#63b3ed}
body.dark .col-method{color:#f6ad55}
body.dark .col-url{color:#90a4ae}
body.dark .col-bytes{color:#607d8b}
body.dark .col-elapsed{color:#546e7a}
body.dark .col-user{color:#b794f4}
body.dark .h2{color:#68d391}
body.dark .h3{color:#f6e05e}
body.dark .h4{color:#fc8181}
body.dark .h5{color:#feb2b2}
body.dark .hx{color:#718096}
body.dark .hl{background:#744210;color:#fefcbf}
body.dark .empty-msg{color:#4a5568}
body.dark .error-msg{background:#2d1515;color:#fc8181;border-color:#fc8181}
body.dark .table-wrap::-webkit-scrollbar-track{background:#0f1117}
body.dark .table-wrap::-webkit-scrollbar-thumb{background:#2d3748}
body.dark .TCP_HIT{background:#1a3a1a;color:#68d391;border-color:#276749}
body.dark .TCP_MISS{background:#2d1f40;color:#d6bcfa;border-color:#553c9a}
body.dark .TCP_DENIED{background:#2d1515;color:#fc8181;border-color:#742a2a}
body.dark .TCP_TUNNEL{background:#1a2a3a;color:#90cdf4;border-color:#2b6cb0}
body.dark .TCP_MEM_HIT{background:#1a3a1a;color:#9ae6b4;border-color:#276749}
body.dark .TCP_REFRESH_HIT{background:#2d2500;color:#f6e05e;border-color:#744210}
body.dark .TCP_REFRESH_MISS{background:#2d1a26;color:#fbb6ce;border-color:#702459}
body.dark .TCP_MISS_ABORTED{background:#2d1a1a;color:#fca5a5;border-color:#7f1d1d}
body.dark .TCP_REFRESH_UNMODIFIED{background:#1a2d1a;color:#86efac;border-color:#166534}
body.dark .TCP_REFRESH_MODIFIED{background:#1a1a2d;color:#93c5fd;border-color:#1e3a5f}
body.dark .NONE_NONE{background:#1a1a1a;color:#6b7280;border-color:#374151}
body.dark .pill-other{background:#1a1d2e;color:#718096;border-color:#2d3748}
body.dark .grep-banner{background:#1a2a3a;border-color:#2b6cb0;color:#90cdf4}
body.dark .grep-banner b{color:#63b3ed}
.btn-theme{background:#37474f;color:#e6eef8;min-width:36px;padding:7px 10px;font-size:14px}
.btn-theme:hover{background:#455a64}

/* ── Toolbar ──────────────────────────────────────────────────── */
.toolbar{
  background:#1e2a35;
  padding:10px 16px;
  display:flex;
  align-items:center;
  gap:10px;
  flex-wrap:wrap;
  flex-shrink:0;
  border-bottom:3px solid #3498db;
}

.toolbar-title{
  font-size:14px;
  font-weight:700;
  color:#fff;
  display:flex;
  align-items:center;
  gap:7px;
  white-space:nowrap;
}

.toolbar-title .icon{
  background:rgba(255,255,255,0.1);
  border-radius:6px;
  padding:4px 7px;
  font-size:15px;
}

.search-wrap{
  position:relative;
  flex:1;
  min-width:220px;
  display:flex;
  gap:6px;
  align-items:center;
}
.search-wrap input{
  flex:1;
  background:#253545;
  border:1px solid #3a4f63;
  color:#e6eef8;
  padding:8px 12px 8px 34px;
  border-radius:7px;
  font-size:13px;
  outline:none;
  transition:border-color .2s;
}
.search-wrap input::placeholder{color:#607d8b}
.search-wrap input:focus{border-color:#3498db}
.search-wrap .sicon{
  position:absolute;left:10px;top:50%;
  transform:translateY(-50%);
  color:#607d8b;font-size:13px;pointer-events:none;
}

/* Grep button */
.btn-grep{
  background:#1565c0;color:#fff;
  padding:7px 12px;border-radius:7px;font-size:12px;
  font-weight:600;cursor:pointer;border:none;
  transition:background .15s, box-shadow .15s;white-space:nowrap;
  display:flex;align-items:center;gap:5px;
}
.btn-grep:hover{background:#1976d2}
.btn-grep.grep-on{
  background:#e65100;color:#fff;
  box-shadow:0 0 0 2px #ffb74d;
  animation:grepPulse 2s infinite;
}
.btn-grep.grep-on:hover{background:#bf360c}
@keyframes grepPulse{
  0%,100%{box-shadow:0 0 0 2px #ffb74d}
  50%{box-shadow:0 0 0 4px rgba(230,81,0,.3)}
}

select{
  background:#253545;border:1px solid #3a4f63;
  color:#e6eef8;padding:8px 10px;border-radius:7px;
  font-size:12px;outline:none;cursor:pointer;
}
select option{background:#1e2a35}

.btn{
  padding:7px 14px;border-radius:7px;font-size:12px;
  font-weight:600;cursor:pointer;border:none;
  transition:background .15s;white-space:nowrap;
}
.btn-blue{background:#2980b9;color:#fff}
.btn-blue:hover{background:#3498db}
.btn-gray{background:#37474f;color:#e6eef8}
.btn-gray:hover{background:#455a64}

/* Live indicator */
.live-badge{
  display:flex;align-items:center;gap:6px;
  background:#1a3a1a;border:1px solid #2e7d32;
  padding:5px 11px;border-radius:99px;
  font-size:11px;font-weight:700;color:#66bb6a;
  white-space:nowrap;cursor:pointer;
  user-select:none;
}
.live-badge.paused{background:#3a1a1a;border-color:#7d2e2e;color:#ef9a9a}
.dot{width:7px;height:7px;border-radius:50%;background:#66bb6a}
.dot.pulse{animation:pulse 1.2s infinite}
.dot.paused{background:#ef9a9a;animation:none}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.25}}

/* ── Stats bar ────────────────────────────────────────────────── */
.statsbar{
  background:#253545;
  padding:6px 16px;
  display:flex;gap:18px;align-items:center;
  font-size:11px;color:#78909c;
  flex-shrink:0;flex-wrap:wrap;
}
.statsbar b{color:#e6eef8}
.cap-note{color:#ffb74d}
.stime{color:#66bb6a;font-weight:700}
.logpath{color:#546e7a;font-size:10px;margin-left:auto}

/* Grep mode banner */
.grep-banner{
  background:#e3f2fd;
  border-bottom:2px solid #90caf9;
  padding:6px 16px;
  font-size:12px;
  color:#1565c0;
  display:none;
  align-items:center;
  gap:10px;
  flex-shrink:0;
}
.grep-banner b{color:#0d47a1}
.grep-banner .close-grep{
  margin-left:auto;
  cursor:pointer;
  font-size:14px;
  color:#1565c0;
  background:none;
  border:none;
  font-weight:700;
}
.grep-banner .close-grep:hover{color:#c62828}

/* ── Table container ──────────────────────────────────────────── */
.table-wrap{
  flex:1;overflow:auto;
  background:#fff;
}

table{width:100%;border-collapse:collapse;font-size:12px}

thead{position:sticky;top:0;z-index:5}
thead th{
  background:#253545;color:#90a4ae;font-weight:600;
  padding:9px 12px;text-align:left;
  border-bottom:2px solid #1e2a35;
  white-space:nowrap;cursor:pointer;
  user-select:none;
}
thead th:hover{color:#3498db}
thead th .sort-arrow{color:#3498db;margin-left:3px;font-size:10px}

tbody tr{
  border-bottom:1px solid #f0f4f8;
  transition:background .1s;
}
tbody tr:hover{background:#f5f9ff}
tbody tr.new-row{animation:slideIn .5s ease}
@keyframes slideIn{
  from{background:#e8f5e9;opacity:0;transform:translateX(-6px)}
  to{background:transparent;opacity:1;transform:translateX(0)}
}

tbody td{
  padding:7px 12px;white-space:nowrap;
  max-width:260px;overflow:hidden;text-overflow:ellipsis;
}

/* Column colors */
.col-ts{color:#78909c;font-size:11px}
.col-client{font-weight:600;color:#1565c0}
.col-method{font-weight:600;color:#e65100}
.col-url{color:#37474f;max-width:300px}
.col-bytes{color:#546e7a}
.col-elapsed{color:#78909c}
.col-user{color:#6a1b9a}
.col-hier{color:#78909c;font-size:11px}

/* Cache code pills */
.pill{display:inline-block;padding:2px 7px;border-radius:4px;font-size:10px;font-weight:700;letter-spacing:.3px}
.TCP_HIT{background:#e8f5e9;color:#2e7d32;border:1px solid #a5d6a7}
.TCP_MISS{background:#f3e5f5;color:#6a1b9a;border:1px solid #ce93d8}
.TCP_DENIED{background:#ffebee;color:#c62828;border:1px solid #ef9a9a}
.TCP_TUNNEL{background:#e3f2fd;color:#1565c0;border:1px solid #90caf9}
.TCP_MEM_HIT{background:#e8f5e9;color:#1b5e20;border:1px solid #81c784}
.TCP_REFRESH_HIT{background:#fff8e1;color:#f57f17;border:1px solid #ffe082}
.TCP_REFRESH_MISS{background:#fce4ec;color:#880e4f;border:1px solid #f48fb1}
.TCP_MISS_ABORTED{background:#fff3e0;color:#bf360c;border:1px solid #ffcc80}
.TCP_REFRESH_UNMODIFIED{background:#f1f8e9;color:#33691e;border:1px solid #aed581}
.TCP_REFRESH_MODIFIED{background:#e8eaf6;color:#283593;border:1px solid #9fa8da}
.NONE_NONE{background:#eceff1;color:#455a64;border:1px solid #b0bec5}
.pill-other{background:#eceff1;color:#546e7a;border:1px solid #cfd8dc}

/* HTTP code colors */
.h2{color:#2e7d32;font-weight:700}
.h3{color:#f57f17;font-weight:700}
.h4{color:#c62828;font-weight:700}
.h5{color:#880e4f;font-weight:700}
.hx{color:#546e7a;font-weight:700}

/* Search highlight */
.hl{background:#fff176;border-radius:2px;color:#333}

/* Empty & error */
.empty-msg{
  text-align:center;padding:60px 20px;
  color:#90a4ae;
}
.empty-msg .big{font-size:40px;margin-bottom:10px}
.error-msg{
  background:#ffebee;color:#c62828;
  padding:12px 16px;font-size:13px;
  border-left:4px solid #c62828;margin:12px 16px;border-radius:4px;
}

/* New rows banner */
.new-banner{
  position:fixed;bottom:16px;right:16px;
  background:#2e7d32;color:#fff;
  padding:8px 16px;border-radius:8px;
  font-size:12px;font-weight:600;
  box-shadow:0 2px 8px rgba(0,0,0,.2);
  cursor:pointer;
  display:none;
  z-index:100;
}
.new-banner:hover{background:#388e3c}

/* Scrollbar */
.table-wrap::-webkit-scrollbar{width:6px;height:6px}
.table-wrap::-webkit-scrollbar-track{background:#f0f4f8}
.table-wrap::-webkit-scrollbar-thumb{background:#b0bec5;border-radius:3px}

/* Loading spinner */
.spinner{
  display:inline-block;width:12px;height:12px;
  border:2px solid rgba(255,255,255,.3);
  border-top-color:#fff;border-radius:50%;
  animation:spin .6s linear infinite;
  vertical-align:middle;
}
@keyframes spin{to{transform:rotate(360deg)}}
</style>
</head>
<body>

<!-- ── Toolbar ──────────────────────────────────────────────────────── -->
<div class="toolbar">

  <div class="toolbar-title">
    <span class="icon">📄</span>
    Logview
  </div>

  <div class="search-wrap">
    <span class="sicon">🔍</span>
    <input id="q" type="text"
      placeholder="Search IP, URL, user, method, HTTP code..."
      onkeydown="if(event.key==='Enter')grepSearch()">
    <button class="btn-grep" id="btnGrep" onclick="toggleGrep()" title="Search entire log file">
      🔎 Full log
    </button>
  </div>

  <select id="fCache">
    <option value="">All cache codes</option>
    <option value="TCP_HIT">TCP_HIT</option>
    <option value="TCP_MISS">TCP_MISS</option>
    <option value="TCP_MISS_ABORTED">TCP_MISS_ABORTED</option>
    <option value="TCP_DENIED">TCP_DENIED</option>
    <option value="TCP_TUNNEL">TCP_TUNNEL</option>
    <option value="TCP_MEM_HIT">TCP_MEM_HIT</option>
    <option value="TCP_REFRESH_HIT">TCP_REFRESH_HIT</option>
    <option value="TCP_REFRESH_MISS">TCP_REFRESH_MISS</option>
    <option value="TCP_REFRESH_UNMODIFIED">TCP_REFRESH_UNMODIFIED</option>
    <option value="TCP_REFRESH_MODIFIED">TCP_REFRESH_MODIFIED</option>
    <option value="NONE_NONE">NONE_NONE</option>
  </select>

  <select id="fHTTP">
    <option value="">All HTTP</option>
    <option>200</option>
    <option>206</option>
    <option>301</option>
    <option>302</option>
    <option>400</option>
    <option>403</option>
    <option>404</option>
    <option>500</option>
  </select>

  <select id="fLines" onchange="reload()">
    <option value="500">Last 500 lines</option>
    <option value="1000">Last 1,000 lines</option>
    <option value="2000">Last 2,000 lines</option>
    <option value="5000">Last 5,000 lines</option>
  </select>

  <select id="fInterval" onchange="changeInterval()">
    <option value="1000">Refresh: 1s</option>
    <option value="3000" selected>Refresh: 3s</option>
    <option value="5000">Refresh: 5s</option>
    <option value="10000">Refresh: 10s</option>
    <option value="30000">Refresh: 30s</option>
  </select>

  <button class="btn btn-blue" onclick="reload()">🔄 Reload</button>
  <button class="btn btn-theme" id="btnTheme" onclick="toggleTheme()" title="Toggle dark/light mode">🌙</button>

  <div class="live-badge" id="liveBadge" onclick="toggleLive()" title="Click to pause/resume">
    <span class="dot pulse" id="liveDot"></span>
    <span id="liveLabel">LIVE</span>
  </div>

</div>

<!-- ── Grep mode banner ───────────────────────────────────────────────── -->
<div class="grep-banner" id="grepBanner">
  🔎 Full-log search: <b id="grepTerm"></b> &nbsp;—&nbsp; <span id="grepCount">0</span> results found across entire log file
  <button class="close-grep" onclick="closeGrep()" title="Back to live view">✕ Back to live</button>
</div>

<!-- ── Stats bar ─────────────────────────────────────────────────────── -->
<div class="statsbar">
  Showing <b id="sShown">0</b> of <b id="sTotal">0</b>
  <span id="sCapNote" class="cap-note" style="display:none"> (display limited to 1000 rows — refine your filter)</span>
  &nbsp;·&nbsp;
  HIT: <b id="sHit" style="color:#2e7d32">0</b>
  &nbsp;
  MISS: <b id="sMiss" style="color:#6a1b9a">0</b>
  &nbsp;
  DENIED: <b id="sDeny" style="color:#c62828">0</b>
  &nbsp;·&nbsp;
  <span class="stime" id="sTime">—</span>
  <span class="logpath" id="sPath">/var/log/squid/access.log</span>
</div>

<!-- ── Table ─────────────────────────────────────────────────────────── -->
<div class="table-wrap" id="tableWrap">
  <div id="errorMsg"></div>
  <table id="mainTable">
    <thead>
      <tr>
        <th onclick="sortBy('ts')">Timestamp <span class="sort-arrow" id="arr-ts"></span></th>
        <th onclick="sortBy('client')">IP Client <span class="sort-arrow" id="arr-client"></span></th>
        <th onclick="sortBy('cache_code')">Cache Code <span class="sort-arrow" id="arr-cache_code"></span></th>
        <th onclick="sortBy('http_code')">HTTP <span class="sort-arrow" id="arr-http_code"></span></th>
        <th onclick="sortBy('method')">Method <span class="sort-arrow" id="arr-method"></span></th>
        <th onclick="sortBy('url')">URL <span class="sort-arrow" id="arr-url"></span></th>
        <th onclick="sortBy('bytes')">Size <span class="sort-arrow" id="arr-bytes"></span></th>
        <th onclick="sortBy('elapsed')">ms <span class="sort-arrow" id="arr-elapsed"></span></th>
        <th onclick="sortBy('user')">User <span class="sort-arrow" id="arr-user"></span></th>
      </tr>
    </thead>
    <tbody id="tbody"></tbody>
  </table>
  <div id="emptyMsg" class="empty-msg" style="display:none">
    <div class="big">📄</div>
    <div>No results for this search</div>
  </div>
</div>

<!-- ── New rows banner ───────────────────────────────────────────────── -->
<div class="new-banner" id="newBanner" onclick="jumpToTop()">
  ↑ <span id="newCount">0</span> new rows — click to view
</div>

<script>
// ── State ─────────────────────────────────────────────────────────────
var ALL = [];
var CUR = [];
var fileOffset = 0;
var liveOn = true;
var pollTimer = null;
var sortKey = 'ts';
var sortDir = -1;
var pendingNew = [];
var newRowCount = 0;
var isLoading = false;
var grepMode = false;

var POLL_INTERVAL = 3000;
var MAX_ROWS = 5000;

// ── Helpers ───────────────────────────────────────────────────────────
function esc(s) {
  return String(s)
    .replace(/&/g,'&amp;')
    .replace(/</g,'&lt;')
    .replace(/>/g,'&gt;')
    .replace(/"/g,'&quot;')
    .replace(/'/g,'&#39;');
}

function hl(text, q) {
  if (!q) return esc(text);
  var re = new RegExp('(' + q.replace(/[.*+?^${}()|[\]\\]/g,'\\$&') + ')', 'gi');
  return esc(text).replace(re, '<span class="hl">$1</span>');
}

function pillClass(c) {
  var known = ['TCP_HIT','TCP_MISS','TCP_DENIED','TCP_TUNNEL','TCP_MEM_HIT',
               'TCP_REFRESH_HIT','TCP_REFRESH_MISS','TCP_MISS_ABORTED',
               'TCP_REFRESH_UNMODIFIED','TCP_REFRESH_MODIFIED','NONE_NONE'];
  return known.indexOf(c) !== -1 ? c : 'pill-other';
}

function httpClass(h) {
  if (!h || h === '-') return 'hx';
  var n = parseInt(h);
  if (n >= 200 && n < 300) return 'h2';
  if (n >= 300 && n < 400) return 'h3';
  if (n >= 400 && n < 500) return 'h4';
  if (n >= 500) return 'h5';
  return 'hx';
}

function fmtBytes(b) {
  b = parseInt(b) || 0;
  if (b >= 1048576) return (b/1048576).toFixed(1) + ' MB';
  if (b >= 1024)    return Math.round(b/1024) + ' KB';
  return b + ' B';
}

function buildIndex(rows) {
  return rows.map(function(r) {
    r._idx = (r.ts + ' ' + r.client + ' ' + r.cache_code + ' ' + r.http_code + ' ' +
              r.method + ' ' + r.url + ' ' + r.user).toLowerCase();
    return r;
  });
}

// ── Initial load ──────────────────────────────────────────────────────
function reload() {
  if (isLoading) return;
  closeGrep(true);
  isLoading = true;
  clearPoll();
  ALL = []; CUR = []; fileOffset = 0;
  newRowCount = 0;
  document.getElementById('tbody').innerHTML =
    '<tr><td colspan="9" style="text-align:center;padding:40px;color:#90a4ae">Loading...</td></tr>';
  document.getElementById('errorMsg').innerHTML = '';

  var lines = document.getElementById('fLines').value;
  var t0 = performance.now();

  fetch('api.php?lines=' + lines)
    .then(function(r){ return r.json(); })
    .then(function(data) {
      if (data.error) { showError(data.error); isLoading = false; return; }

      ALL = buildIndex(data.rows || []);
      fileOffset = data.offset || 0;

      var elapsed = (performance.now() - t0).toFixed(0);
      document.getElementById('sTime').textContent = elapsed + ' ms';
      document.getElementById('sPath').textContent = data.log_file || '/var/log/squid/access.log';

      applyFilters();
      isLoading = false;
      if (liveOn) startPoll();
    })
    .catch(function(e) {
      showError('Cannot reach api.php — ' + e.message);
      isLoading = false;
    });
}

// ── Grep full-log search ──────────────────────────────────────────────
function toggleGrep() {
  if (grepMode) {
    closeGrep(false);
  } else {
    grepSearch();
  }
}

function grepSearch() {
  var q = document.getElementById('q').value.trim();
  if (!q) { reload(); return; }

  if (isLoading) return;
  isLoading = true;
  clearPoll();
  ALL = []; CUR = [];
  newRowCount = 0;
  grepMode = true;

  var btn = document.getElementById('btnGrep');
  btn.innerHTML = '<span class="spinner"></span> Searching...';

  document.getElementById('tbody').innerHTML =
    '<tr><td colspan="9" style="text-align:center;padding:40px;color:#90a4ae">Searching entire log file...</td></tr>';
  document.getElementById('errorMsg').innerHTML = '';

  var t0 = performance.now();

  fetch('api.php?grep=' + encodeURIComponent(q))
    .then(function(r){ return r.json(); })
    .then(function(data) {
      if (data.error) { showError(data.error); isLoading = false; resetGrepBtn(); return; }

      ALL = buildIndex(data.rows || []);
      fileOffset = data.offset || 0;

      var elapsed = (performance.now() - t0).toFixed(0);
      document.getElementById('sTime').textContent = elapsed + ' ms';
      document.getElementById('sPath').textContent = data.log_file || '/var/log/squid/access.log';

      // Show grep banner
      var banner = document.getElementById('grepBanner');
      document.getElementById('grepTerm').textContent = q;
      document.getElementById('grepCount').textContent = ALL.length.toLocaleString();
      banner.style.display = 'flex';

      applyFilters();
      isLoading = false;
      setGrepBtnOn();
      // No polling in grep mode
    })
    .catch(function(e) {
      showError('Cannot reach api.php — ' + e.message);
      isLoading = false;
      resetGrepBtn();
      grepMode = false;
    });
}

function setGrepBtnOn() {
  var btn = document.getElementById('btnGrep');
  btn.classList.add('grep-on');
  btn.innerHTML = '✕ Live mode';
  btn.title = 'Exit full-log search, back to live view';
}

function resetGrepBtn() {
  var btn = document.getElementById('btnGrep');
  btn.classList.remove('grep-on');
  btn.innerHTML = '🔎 Full log';
  btn.title = 'Search entire log file';
}

function closeGrep(silent) {
  grepMode = false;
  document.getElementById('grepBanner').style.display = 'none';
  resetGrepBtn();
  if (!silent) reload();
}

// ── Polling ───────────────────────────────────────────────────────────
function startPoll() {
  clearPoll();
  pollTimer = setInterval(poll, POLL_INTERVAL);
}

function clearPoll() {
  if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
}

function poll() {
  if (!liveOn || grepMode) return;

  var tableWrap = document.getElementById('tableWrap');
  var scrollPos = tableWrap.scrollTop;

  fetch('api.php?since=' + fileOffset)
    .then(function(r){ return r.json(); })
    .then(function(data) {
      if (!data.rows || data.rows.length === 0) return;

      var newRows = buildIndex(data.rows);
      fileOffset = data.offset;

      // Dedup against the most recent rows already in ALL, in case
      // of overlap from log rotation or offset edge cases.
      var recentIdx = {};
      for (var i = 0; i < Math.min(ALL.length, newRows.length + 50); i++) {
        recentIdx[ALL[i]._idx] = true;
      }
      newRows = newRows.filter(function(r){ return !recentIdx[r._idx]; });

      ALL = newRows.concat(ALL);
      if (ALL.length > MAX_ROWS) ALL = ALL.slice(0, MAX_ROWS);
      newRowCount += newRows.length;

      applyFilters();

      if (scrollPos > 60) {
        tableWrap.scrollTop = scrollPos;
        showNewBanner();
      }
    })
    .catch(function(){});
}

function toggleLive() {
  liveOn = !liveOn;
  var badge = document.getElementById('liveBadge');
  var dot   = document.getElementById('liveDot');
  var lbl   = document.getElementById('liveLabel');
  if (liveOn) {
    badge.className = 'live-badge';
    dot.className   = 'dot pulse';
    lbl.textContent = 'LIVE';
    if (!grepMode) startPoll();
  } else {
    badge.className = 'live-badge paused';
    dot.className   = 'dot paused';
    lbl.textContent = 'PAUSED';
    clearPoll();
  }
}

// ── Filters & Render ──────────────────────────────────────────────────
function applyFilters(newCount) {
  var q  = (document.getElementById('q').value || '').toLowerCase().trim();
  var fc = document.getElementById('fCache').value;
  var fh = document.getElementById('fHTTP').value;
  var t0 = performance.now();

  var res = ALL;
  // In grep mode, don't re-filter by search text (already done server-side)
  if (!grepMode && q) res = res.filter(function(r){ return r._idx.indexOf(q) !== -1; });
  if (fc) res = res.filter(function(r){ return r.cache_code === fc; });
  if (fh) res = res.filter(function(r){ return r.http_code === fh; });

  CUR = res;
  var elapsed = (performance.now() - t0).toFixed(1);
  document.getElementById('sTime').textContent = elapsed + ' ms';

  updateStats();
  renderTable(grepMode ? q : q, newCount || 0);
}

function updateStats() {
  var RENDER_CAP = 1000;
  var shown = Math.min(CUR.length, RENDER_CAP);
  document.getElementById('sShown').textContent = shown.toLocaleString();
  document.getElementById('sTotal').textContent = ALL.length.toLocaleString();
  document.getElementById('sCapNote').style.display = (CUR.length > RENDER_CAP) ? '' : 'none';
  document.getElementById('sHit').textContent =
    ALL.filter(function(r){return r.cache_code==='TCP_HIT'||r.cache_code==='TCP_MEM_HIT';}).length.toLocaleString();
  document.getElementById('sMiss').textContent =
    ALL.filter(function(r){return r.cache_code.indexOf('MISS')!==-1;}).length.toLocaleString();
  document.getElementById('sDeny').textContent =
    ALL.filter(function(r){return r.cache_code==='TCP_DENIED';}).length.toLocaleString();
}

function renderTable(q, animateFirst) {
  var tbody = document.getElementById('tbody');
  var empty = document.getElementById('emptyMsg');
  q = q || '';
  animateFirst = animateFirst || 0;

  if (!CUR.length) {
    tbody.innerHTML = '';
    empty.style.display = 'block';
    return;
  }
  empty.style.display = 'none';

  var slice = CUR.slice(0, 1000); // keep in sync with RENDER_CAP in updateStats()

  tbody.innerHTML = slice.map(function(r, i) {
    var rowClass = i < animateFirst ? 'new-row' : '';
    return '<tr class="' + rowClass + '">' +
      '<td class="col-ts">'     + hl(new Date(r.ts.replace(' ', 'T') + 'Z').toLocaleString(), q) + '</td>' +
      '<td class="col-client">' + hl(r.client, q)      + '</td>' +
      '<td><span class="pill ' + pillClass(r.cache_code) + '">' + hl(r.cache_code, q) + '</span></td>' +
      '<td class="' + httpClass(r.http_code) + '">'   + hl(r.http_code, q) + '</td>' +
      '<td class="col-method">' + hl(r.method, q)      + '</td>' +
      '<td class="col-url" title="' + esc(r.url) + '">' + hl(r.url, q) + '</td>' +
      '<td class="col-bytes">'  + fmtBytes(r.bytes)    + '</td>' +
      '<td class="col-elapsed">'+ hl(String(r.elapsed), q) + '</td>' +
      '<td class="col-user">'   + hl(r.user, q)        + '</td>' +
    '</tr>';
  }).join('');
}

// ── Sort ──────────────────────────────────────────────────────────────
function sortBy(key) {
  if (sortKey === key) sortDir *= -1;
  else { sortKey = key; sortDir = -1; }

  document.querySelectorAll('.sort-arrow').forEach(function(el){ el.textContent = ''; });
  var arr = document.getElementById('arr-' + key);
  if (arr) arr.textContent = sortDir === -1 ? '▼' : '▲';

  CUR.sort(function(a, b) {
    var va = a[key], vb = b[key];
    if (key === 'bytes' || key === 'elapsed') { va = parseInt(va)||0; vb = parseInt(vb)||0; return (va - vb) * sortDir; }
    if (key === 'http_code') { va = parseInt(va)||0; vb = parseInt(vb)||0; return (va - vb) * sortDir; }
    va = String(va); vb = String(vb);
    return va < vb ? -sortDir : va > vb ? sortDir : 0;
  });

  renderTable(document.getElementById('q').value.toLowerCase().trim());
}

// ── New rows banner ───────────────────────────────────────────────────
function showNewBanner() {
  var banner = document.getElementById('newBanner');
  document.getElementById('newCount').textContent = newRowCount;
  banner.style.display = 'block';
}

function jumpToTop() {
  newRowCount = 0;
  applyFilters(0);
  requestAnimationFrame(function() {
    document.getElementById('tableWrap').scrollTop = 0;
    document.getElementById('newBanner').style.display = 'none';
  });
}

// ── Error display ─────────────────────────────────────────────────────
function showError(msg) {
  document.getElementById('errorMsg').innerHTML =
    '<div class="error-msg">⚠️ ' + esc(msg) + '</div>';
  document.getElementById('tbody').innerHTML = '';
}

function changeInterval() {
  POLL_INTERVAL = parseInt(document.getElementById('fInterval').value);
  if (liveOn && !grepMode) startPoll();
}

// ── Theme ─────────────────────────────────────────────────────────────
function toggleTheme() {
  var dark = document.body.classList.toggle('dark');
  document.getElementById('btnTheme').textContent = dark ? '☀️' : '🌙';
  try { localStorage.setItem('logview_theme', dark ? 'dark' : 'light'); } catch(e){}
}

function initTheme() {
  var saved = '';
  try { saved = localStorage.getItem('logview_theme') || ''; } catch(e){}
  if (saved === 'dark') {
    document.body.classList.add('dark');
    document.getElementById('btnTheme').textContent = '☀️';
  }
}

// ── Events ────────────────────────────────────────────────────────────
document.getElementById('q').addEventListener('input', function(){
  if (!grepMode) applyFilters();
});
document.getElementById('fCache').addEventListener('change', function(){ applyFilters(); });
document.getElementById('fHTTP').addEventListener('change', function(){ applyFilters(); });

// ── Init ──────────────────────────────────────────────────────────────
initTheme();
reload();
</script>
</body>
</html>
