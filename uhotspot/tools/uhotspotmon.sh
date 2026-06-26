#!/bin/bash
# maravento.com
#
################################################################################
#
# UniFi Hotspot Log Viewer module installation/uninstallation script for Webmin
#
# Description:
#   This script installs or uninstalls the UniFi Hotspot Log Viewer module
#   for Webmin. Provides real-time log monitoring for the uhotspotd daemon
#   with live polling, filtering, and full-log search.
#
# Features:
#   - Real-time log viewer with AJAX polling (no tail -f)
#   - Live/Pause toggle
#   - Full-log grep search
#   - Filter by level (INFO/WARNING/ERROR)
#   - Text filter with highlighting
#   - Cycle stats dashboard (vouchers, authorized, pending, etc.)
#   - Service status indicator
#   - Multi-language support (English and Spanish)
#
# Usage:
#   sudo ./uhotspotmon.sh [OPTIONS]
#
# Options:
#   install      Install the module
#   uninstall    Uninstall the module
#   -h, --help   Show help message
#
################################################################################

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

set -e

MODNAME="uhotspot"
MODDIR="/usr/share/webmin/$MODNAME"
ETCDIR="/etc/webmin/$MODNAME"

install_module() {
    echo ""
    echo "=========================================="
    echo "Installing UniFi Hotspot Log Viewer Module"
    echo "=========================================="
    echo ""

    echo "Creating module structure..."

    mkdir -p "$MODDIR/images"
    mkdir -p "$MODDIR/lang"
    mkdir -p "$ETCDIR"

    # ============================================================
    # 1. api.cgi (bash — AJAX endpoint for log polling)
    # ============================================================
    cat > "$MODDIR/api.cgi" <<'APICGI'
#!/bin/bash
# api.cgi — AJAX endpoint for uhotspotd log viewer
# Reads /var/log/uhotspot.log via byte offset (never stalls like tail -f)
#
# Params (via QUERY_STRING):
#   action=tail&pos=N&lines=N  — read from byte offset (polling)
#   action=grep&q=TERM         — full-file grep search
#   action=status              — service status

LOG_FILE="/var/log/uhotspot.log"
MAX_GREP=3000

echo "Content-Type: application/json"
echo "Cache-Control: no-store"
echo ""

# Parse QUERY_STRING
declare -A params
IFS='&' read -ra pairs <<< "$QUERY_STRING"
for pair in "${pairs[@]}"; do
    IFS='=' read -r key val <<< "$pair"
    val=$(printf '%b' "${val//%/\\x}" 2>/dev/null || echo "$val")
    params["$key"]="$val"
done

action="${params[action]:-tail}"

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/}"
    printf '%s' "$s"
}

# ── Status ────────────────────────────────────────────────────
if [[ "$action" == "status" ]]; then
    active=0
    pid=""
    uptime=""
    mem=""
    cpu=""
    status_out=$(systemctl status uhotspotd.service 2>&1 || true)
    if echo "$status_out" | grep -q 'Active: active (running)'; then
        active=1
    fi
    pid=$(echo "$status_out" | grep -oP 'Main PID:\s+\K\d+' || true)
    uptime=$(echo "$status_out" | grep -oP 'Active:.*;\s+\K.+' | sed 's/\s*$//' || true)
    mem=$(echo "$status_out" | grep -oP 'Memory:\s+\K[^\(]+' | sed 's/\s*$//' || true)
    cpu=$(echo "$status_out" | grep -oP 'CPU:\s+\K.+' | sed 's/\s*$//' || true)
    printf '{"active":%d,"pid":"%s","uptime":"%s","mem":"%s","cpu":"%s"}' \
        "$active" "$(json_escape "$pid")" "$(json_escape "$uptime")" \
        "$(json_escape "$mem")" "$(json_escape "$cpu")"
    exit 0
fi

# ── File checks ───────────────────────────────────────────────
if [[ ! -f "$LOG_FILE" ]]; then
    echo '{"error":"Log file not found","rows":[]}'
    exit 0
fi

file_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)

# ── Grep ──────────────────────────────────────────────────────
if [[ "$action" == "grep" ]]; then
    term="${params[q]:-}"
    if [[ -z "$term" ]]; then
        echo '{"error":"Empty search term","rows":[]}'
        exit 0
    fi
    # Sanitize
    if [[ ! "$term" =~ ^[[:alnum:][:space:].\-:/@_]+$ ]]; then
        echo '{"error":"Invalid search term","rows":[]}'
        exit 0
    fi

    output=$(timeout 20 grep -Fia "$term" "$LOG_FILE" 2>/dev/null | tail -n "$MAX_GREP" || true)

    printf '{"rows":['
    first=1
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Skip separator lines
        [[ "$line" == ─* ]] && continue

        ts="" level="" msg=""
        if [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2})\ (INFO|WARNING|ERROR):\ (.*) ]]; then
            ts="${BASH_REMATCH[1]}"
            level="${BASH_REMATCH[2]}"
            msg="${BASH_REMATCH[3]}"
        elif [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2})\ (.*) ]]; then
            ts="${BASH_REMATCH[1]}"
            level="RELOAD"
            msg="${BASH_REMATCH[2]}"
        else
            continue
        fi

        [[ $first -eq 0 ]] && printf ','
        first=0
        printf '{"ts":"%s","level":"%s","msg":"%s"}' \
            "$(json_escape "$ts")" "$(json_escape "$level")" "$(json_escape "$msg")"
    done <<< "$output"

    printf '],"offset":%d,"grep":true}\n' "$file_size"
    exit 0
fi

# ── Tail (polling by byte offset) ────────────────────────────
pos="${params[pos]:-0}"
lines="${params[lines]:-200}"

# Validate
[[ "$pos" =~ ^[0-9]+$ ]] || pos=0
[[ "$lines" =~ ^[0-9]+$ ]] || lines=200
(( lines > 5000 )) && lines=5000
(( lines < 50 )) && lines=50

# First load or log rotated: read last N lines
if (( pos == 0 )) || (( pos > file_size )); then
    data=$(tail -n "$lines" "$LOG_FILE" 2>/dev/null || true)
    pos=$file_size
    rotated=true
else
    # No new data
    if (( pos >= file_size )); then
        printf '{"rows":[],"pos":%d}\n' "$file_size"
        exit 0
    fi
    # Read from last position
    bytes_to_read=$(( file_size - pos ))
    data=$(tail -c +"$(( pos + 1 ))" "$LOG_FILE" 2>/dev/null | head -c "$bytes_to_read" || true)
    pos=$file_size
    rotated=false
fi

printf '{"rows":['
first=1
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" == ─* ]] && continue

    ts="" level="" msg=""
    if [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2})\ (INFO|WARNING|ERROR):\ (.*) ]]; then
        ts="${BASH_REMATCH[1]}"
        level="${BASH_REMATCH[2]}"
        msg="${BASH_REMATCH[3]}"
    elif [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2})\ (.*) ]]; then
        ts="${BASH_REMATCH[1]}"
        level="RELOAD"
        msg="${BASH_REMATCH[2]}"
    else
        continue
    fi

    [[ $first -eq 0 ]] && printf ','
    first=0
    printf '{"ts":"%s","level":"%s","msg":"%s"}' \
        "$(json_escape "$ts")" "$(json_escape "$level")" "$(json_escape "$msg")"
done <<< "$data"

printf '],"pos":%d,"rotated":%s}\n' "$pos" "$rotated"
APICGI

    chmod 755 "$MODDIR/api.cgi"

    # ============================================================
    # 2. index.cgi (Perl — main page with Webmin header/footer)
    # ============================================================
    cat > "$MODDIR/index.cgi" <<'INDEXCGI'
#!/usr/bin/perl
# UniFi Hotspot Log Viewer — Main interface
use strict;
use warnings;

do '../web-lib.pl';
do '../ui-lib.pl';
&init_config();
&ReadParse();

our $module_name;
our %text;

&load_language($module_name);

print "Cache-Control: no-cache, no-store, must-revalidate, max-age=0\r\n";
print "Pragma: no-cache\r\n";

&ui_print_header(undef, $text{'index_title'}, "", undef, 1, 1);

print <<'HTMLBLOCK';
<style>
/* ── Variables — Light (default) ───────────────────────────── */
#uhmod{
  --bg:       #ffffff;
  --bg2:      #f8f9fa;
  --bg3:      #f1f3f5;
  --border:   #dee2e6;
  --border2:  #e9ecef;
  --text:     #212529;
  --text2:    #495057;
  --text3:    #868e96;
  --ts-color: #6c757d;
  --msg-color:#212529;
  --mc-color: #1565c0;
  --ip-color: #6a1b9a;
  --kw-color: #1b5e20;
  --hl-bg:    #fff176;
  --hl-color: #333;
  --row-hover:#f1f3f5;
  --row-new:  #d4edda;
  --th-bg:    #f1f3f5;
  --th-color: #495057;
  --scroll-track:#f1f3f5;
  --scroll-thumb:#ced4da;
  --sb-text:  #6c757d;
  --cb-bg:    #f8f9fa;
  --stats-bg: #f1f3f5;
  --grep-bg:  #e8f4fd;
  --grep-border:#90caf9;
  --grep-text:#0d47a1;
  --cap-color:#e65100;
  --st-color: #2e7d32;
}
/* ── Variables — Dark ───────────────────────────────────────── */
#uhmod.dark{
  --bg:       #0d1117;
  --bg2:      #161b22;
  --bg3:      #1c2128;
  --border:   #21262d;
  --border2:  #30363d;
  --text:     #e6edf3;
  --text2:    #c9d1d9;
  --text3:    #8b949e;
  --ts-color: #4a6880;
  --msg-color:#c9d1d9;
  --mc-color: #79c0ff;
  --ip-color: #d2a8ff;
  --kw-color: #7ee787;
  --hl-bg:    #3d2e00;
  --hl-color: #ffd700;
  --row-hover:#161b22;
  --row-new:  #1a3a1a;
  --th-bg:    #161b22;
  --th-color: #8b949e;
  --scroll-track:#0d1117;
  --scroll-thumb:#30363d;
  --sb-text:  #8b949e;
  --cb-bg:    #111827;
  --stats-bg: #111827;
  --grep-bg:  #0d2137;
  --grep-border:#1565c0;
  --grep-text:#90caf9;
  --cap-color:#ffb74d;
  --st-color: #66bb6a;
}

#uhmod *{box-sizing:border-box}
#uhmod{font-family:'Segoe UI',system-ui,sans-serif;display:flex;flex-direction:column;height:calc(100vh - 120px);min-height:500px;background:var(--bg)}

/* ── Toolbar (always dark) ──────────────────────────────────── */
.uh-toolbar{background:#1e2a35;padding:10px 14px;display:flex;align-items:center;gap:8px;flex-wrap:wrap;flex-shrink:0;border-bottom:3px solid #3498db;border-radius:6px 6px 0 0}
.uh-toolbar .title{font-size:13px;font-weight:700;color:#fff;display:flex;align-items:center;gap:6px;white-space:nowrap}
.uh-toolbar .title .icon{background:rgba(255,255,255,.1);border-radius:5px;padding:3px 6px;font-size:12px}
.uh-search{position:relative;flex:1;min-width:200px;display:flex;gap:5px;align-items:center}
.uh-search input{flex:1;background:#253545;border:1px solid #3a4f63;color:#e6eef8;padding:7px 10px 7px 10px;border-radius:6px;font-size:12px;outline:none}
.uh-search input::placeholder{color:#607d8b}
.uh-search input:focus{border-color:#3498db}
.uh-bgrep{background:#1565c0;color:#fff;padding:6px 12px;border-radius:6px;font-size:11px;font-weight:600;cursor:pointer;border:none;white-space:nowrap}
.uh-bgrep:hover{background:#1976d2}
.uh-bgrep.grep-on{background:#e65100;animation:uhP 2s infinite}
.uh-bgrep.grep-on:hover{background:#bf360c}
@keyframes uhP{0%,100%{box-shadow:0 0 0 2px #ffb74d}50%{box-shadow:0 0 0 4px rgba(230,81,0,.3)}}
.uh-toolbar select{background:#253545;border:1px solid #3a4f63;color:#e6eef8;padding:7px 8px;border-radius:6px;font-size:11px;outline:none;cursor:pointer}
.uh-toolbar select option{background:#1e2a35}
.uh-btn{padding:6px 12px;border-radius:6px;font-size:11px;font-weight:600;cursor:pointer;border:none;white-space:nowrap;background:#37474f;color:#e6eef8}
.uh-btn:hover{background:#455a64}
.uh-btn-dm{padding:5px 10px;border-radius:6px;font-size:13px;font-weight:600;cursor:pointer;border:1px solid #3a4f63;background:#253545;color:#e6eef8;line-height:1;transition:background .2s}
.uh-btn-dm:hover{background:#37474f}
.uh-live{display:flex;align-items:center;gap:5px;background:#1a3a1a;border:1px solid #2e7d32;padding:4px 10px;border-radius:99px;font-size:10px;font-weight:700;color:#66bb6a;white-space:nowrap;cursor:pointer;user-select:none}
.uh-live.paused{background:#3a1a1a;border-color:#7d2e2e;color:#ef9a9a}
.uh-live .dot{width:6px;height:6px;border-radius:50%;background:#66bb6a}
.uh-live .dot.pulse{animation:uhD 1.2s infinite}
.uh-live.paused .dot{background:#ef9a9a;animation:none}
@keyframes uhD{0%,100%{opacity:1}50%{opacity:.25}}

/* ── Grep banner ────────────────────────────────────────────── */
.uh-grepbar{background:var(--grep-bg);border-bottom:2px solid var(--grep-border);padding:5px 14px;font-size:11px;color:var(--grep-text);display:none;align-items:center;gap:8px;flex-shrink:0}
.uh-grepbar b{color:var(--grep-text)}
.uh-grepbar .cg{margin-left:auto;cursor:pointer;font-size:13px;color:var(--grep-text);background:none;border:none;font-weight:700}

/* ── Stats bar ──────────────────────────────────────────────── */
.uh-stats{background:var(--stats-bg);padding:5px 14px;display:flex;gap:14px;align-items:center;font-size:10px;color:var(--sb-text);flex-shrink:0;flex-wrap:wrap;border-bottom:1px solid var(--border)}
.uh-stats b{color:var(--text2)}
.uh-stats .sd{width:7px;height:7px;border-radius:50%;display:inline-block;margin-right:3px;vertical-align:middle}
.uh-stats .sd.on{background:#28a745}
.uh-stats .sd.off{background:#dc3545}
.uh-stats .cap{color:var(--cap-color)}
.uh-stats .st{color:var(--st-color);font-weight:700}
.uh-stats .lp{color:var(--text3);margin-left:auto;font-size:10px}

/* ── Cycle pills bar ────────────────────────────────────────── */
.uh-cbar{background:var(--cb-bg);padding:5px 14px;display:flex;gap:6px;align-items:center;font-size:11px;flex-shrink:0;flex-wrap:wrap;border-bottom:1px solid var(--border)}
.uh-cbar:empty{display:none;padding:0}
.uh-cp{padding:3px 10px;border-radius:12px;font-weight:600;font-size:11px}
.uh-cp-ok{background:#d4edda;color:#155724;border:1px solid #c3e6cb}
.uh-cp-w{background:#fff3cd;color:#856404;border:1px solid #ffeeba}
.uh-cp-i{background:#d1ecf1;color:#0c5460;border:1px solid #bee5eb}
.uh-cp-d{background:#e2e3e5;color:#383d41;border:1px solid #d6d8db}
#uhmod.dark .uh-cp-ok{background:#1a3a1a;color:#66bb6a;border-color:#2e7d32}
#uhmod.dark .uh-cp-w{background:#3a2a00;color:#ffb74d;border-color:#f57f17}
#uhmod.dark .uh-cp-i{background:#1a2a3a;color:#90caf9;border-color:#1565c0}
#uhmod.dark .uh-cp-d{background:#1a1d2e;color:#8b949e;border-color:#30363d}

/* ── Table ──────────────────────────────────────────────────── */
.uh-tw{flex:1;overflow:auto;background:var(--bg);border-radius:0 0 6px 6px}
.uh-tw table{width:100%;border-collapse:collapse;font-size:12.5px}
.uh-tw thead{position:sticky;top:0;z-index:5}
.uh-tw thead th{background:var(--th-bg);color:var(--th-color);font-weight:600;padding:9px 12px;text-align:left;border-bottom:2px solid var(--border);white-space:nowrap;font-size:11px;text-transform:uppercase;letter-spacing:.5px}
.uh-tw tbody tr{border-bottom:1px solid var(--border2);transition:background .1s}
.uh-tw tbody tr:hover{background:var(--row-hover)}
.uh-tw tbody tr.nr{animation:uhS .4s ease}
@keyframes uhS{from{background:var(--row-new);opacity:0;transform:translateX(-3px)}to{background:transparent;opacity:1;transform:translateX(0)}}
.uh-tw td{padding:7px 12px;white-space:nowrap;color:var(--text)}
.uh-tw td.cm{white-space:normal;word-break:break-all;max-width:700px;color:var(--msg-color)}

/* ── Cell styles ────────────────────────────────────────────── */
.ct{color:var(--ts-color);font-size:11px;font-family:'Consolas','Liberation Mono',monospace}

/* Level badges */
.cl{display:inline-block;padding:2px 8px;border-radius:10px;font-weight:700;font-size:10px;text-transform:uppercase;letter-spacing:.4px;min-width:60px;text-align:center}
.cl.lI{background:#d1ecf1;color:#0c5460;border:1px solid #bee5eb}
.cl.lW{background:#fff3cd;color:#856404;border:1px solid #ffeeba}
.cl.lE{background:#f8d7da;color:#721c24;border:1px solid #f5c6cb}
.cl.lR{background:#e2e3e5;color:#383d41;border:1px solid #d6d8db}
#uhmod.dark .cl.lI{background:#1a2a3a;color:#90caf9;border-color:#1565c0}
#uhmod.dark .cl.lW{background:#3a2a00;color:#ffc107;border-color:#d29922}
#uhmod.dark .cl.lE{background:#3a1a1a;color:#f85149;border-color:#6e1a1a}
#uhmod.dark .cl.lR{background:#1c2128;color:#8b949e;border-color:#30363d}

.hl{background:var(--hl-bg);border-radius:2px;color:var(--hl-color)}
.mc{color:var(--mc-color);font-weight:600}
.ip{color:var(--ip-color)}
.kw{color:var(--kw-color);font-weight:600}
.uh-empty{text-align:center;padding:50px 20px;color:var(--text3);background:var(--bg)}

/* ── New rows banner ────────────────────────────────────────── */
.uh-nb{position:fixed;bottom:14px;right:14px;background:#28a745;color:#fff;padding:7px 14px;border-radius:7px;font-size:11px;font-weight:600;box-shadow:0 2px 12px rgba(0,0,0,.2);cursor:pointer;display:none;z-index:100;border:1px solid #218838}
.uh-nb:hover{background:#218838}
.uh-sp{display:inline-block;width:10px;height:10px;border:2px solid rgba(255,255,255,.3);border-top-color:#fff;border-radius:50%;animation:uhSp .6s linear infinite;vertical-align:middle}
@keyframes uhSp{to{transform:rotate(360deg)}}
.uh-tw::-webkit-scrollbar{width:6px;height:6px}
.uh-tw::-webkit-scrollbar-track{background:var(--scroll-track)}
.uh-tw::-webkit-scrollbar-thumb{background:var(--scroll-thumb);border-radius:3px}
</style>

<div id="uhmod">
<div class="uh-toolbar">
  <div class="title"><span class="icon">&#9685;</span> uhotspotd</div>
  <div class="uh-search">
    <span class="sicon">&#128269;</span>
    <input id="uhQ" type="text" placeholder="Filter by MAC, IP, message..." onkeydown="if(event.key==='Enter')uhGS()">
    <button class="uh-bgrep" id="uhBG" onclick="uhTG()" title="Search entire log file">Full log</button>
  </div>
  <select id="uhLv" onchange="uhAF()"><option value="">All levels</option><option value="INFO">INFO</option><option value="WARNING">WARNING</option><option value="ERROR">ERROR</option><option value="RELOAD">RELOAD</option></select>
  <select id="uhLn" onchange="uhRL()"><option value="200">Last 200</option><option value="500" selected>Last 500</option><option value="1000">Last 1000</option><option value="2000">Last 2000</option></select>
  <select id="uhIv" onchange="uhCI()"><option value="1000">1s</option><option value="3000">3s</option><option value="5000" selected>5s</option><option value="10000">10s</option><option value="30000">30s</option></select>
  <button class="uh-btn" onclick="uhRL()" title="Reload log">Reload</button>
  <button class="uh-btn-dm" id="uhDM" onclick="uhTDM()" title="Toggle dark mode">&#9790;</button>
  <div class="uh-live" id="uhLB" onclick="uhTL()" title="Click to pause/resume"><span class="dot pulse" id="uhDt"></span><span id="uhLL">LIVE</span></div>
</div>
<div class="uh-grepbar" id="uhGB">Full-log search: <b id="uhGT"></b> — <span id="uhGC">0</span> results <button class="cg" onclick="uhCG()">&#10005; Back to live</button></div>
<div class="uh-stats">
  <span><span class="sd" id="uhSD"></span><span id="uhSL">…</span></span>
  <span style="color:#37474f">│</span>
  Showing <b id="uhSh">0</b> of <b id="uhTo">0</b>
  <span id="uhCN" class="cap" style="display:none"> (max 1000)</span>
  <span style="color:#37474f">│</span>
  <span class="st" id="uhST">—</span>
  <span class="lp">/var/log/uhotspot.log</span>
</div>
<div class="uh-cbar" id="uhCB"></div>
<div class="uh-tw" id="uhTW">
  <table><thead><tr><th style="width:145px">Timestamp</th><th style="width:70px">Level</th><th>Message</th></tr></thead><tbody id="uhTB"></tbody></table>
  <div id="uhEM" class="uh-empty" style="display:none">No log entries match</div>
</div>
<div class="uh-nb" id="uhNB" onclick="uhJT()">^ <span id="uhNC">0</span> new rows — click to view</div>
</div>

<script>
(function(){
var ALL=[],CUR=[],fOff=0,live=true,pTmr=null,grep=false,loading=false,nrc=0;
var PI=5000,MR=5000,RC=1000;

// Dark mode
var dm=false;
function uhTDM(){
  dm=!dm;
  var mod=document.getElementById('uhmod');
  var btn=document.getElementById('uhDM');
  if(dm){mod.classList.add('dark');btn.textContent='\u2600';}
  else{mod.classList.remove('dark');btn.textContent='\u263D';}
  try{localStorage.setItem('uh_dm',dm?'1':'0')}catch(e){}
}
try{if(localStorage.getItem('uh_dm')==='1'){dm=true;document.getElementById('uhmod').classList.add('dark');document.getElementById('uhDM').textContent='\u2600';}}catch(e){}

function esc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;')}
function hl(t,q){if(!q)return esc(t);try{var r=new RegExp('('+q.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')+')','gi');return esc(t).replace(r,'<span class="hl">$1</span>')}catch(e){return esc(t)}}
function cm(m,q){var s=q?hl(m,q):esc(m);s=s.replace(/([0-9a-f]{2}(?::[0-9a-f]{2}){5})/gi,'<span class="mc">$1</span>');s=s.replace(/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/g,'<span class="ip">$1</span>');s=s.replace(/\b(authorized|unauthorized|expired|revoked|pending|skipping|reload|voucher|evicting|managed)\b/gi,'<span class="kw">$1</span>');return s}
function bi(rows){return rows.map(function(r){r._i=(r.ts+' '+r.level+' '+r.msg).toLowerCase();return r})}
function mf(r){var lv=document.getElementById('uhLv').value;if(lv&&r.level!==lv)return false;var q=(document.getElementById('uhQ').value||'').toLowerCase().trim();if(!grep&&q&&r._i.indexOf(q)===-1)return false;return true}

function uhAF(an){
  var q=(document.getElementById('uhQ').value||'').toLowerCase().trim();
  var t0=performance.now();CUR=ALL.filter(mf);
  document.getElementById('uhST').textContent=(performance.now()-t0).toFixed(1)+' ms';
  var sh=Math.min(CUR.length,RC);
  document.getElementById('uhSh').textContent=sh;
  document.getElementById('uhTo').textContent=ALL.length;
  document.getElementById('uhCN').style.display=CUR.length>RC?'':'none';
  rt(grep?q:q,an||0);
}

function rt(q,an){
  var tb=document.getElementById('uhTB'),em=document.getElementById('uhEM');q=q||'';an=an||0;
  if(!CUR.length){tb.innerHTML='';em.style.display='block';return}
  em.style.display='none';
  var sl=CUR.slice(0,RC);
  tb.innerHTML=sl.map(function(r,i){
    var c=i<an?'nr':'';
    var lc=r.level==='INFO'?'lI':r.level==='WARNING'?'lW':r.level==='ERROR'?'lE':'lR';
    return '<tr class="'+c+'"><td class="ct">'+esc(r.ts)+'</td><td class="cl '+lc+'">'+esc(r.level)+'</td><td class="cm">'+cm(r.msg,q)+'</td></tr>'
  }).join('');
}

function ucs(){
  var bar=document.getElementById('uhCB');
  for(var i=0;i<ALL.length;i++){
    var m=ALL[i].msg.match(/vouchers=(\d+)\s*\|\s*authorized=(\d+)\s*\|\s*pending=(\d+)\s*\|\s*new_pending=(\d+)\s*\|\s*new_auth=(\d+)\s*\|\s*revoked=(\d+)\s*\|\s*managed_authorized=(\d+)/);
    if(m){bar.innerHTML='<span class="uh-cp uh-cp-i">Vouchers '+m[1]+'</span><span class="uh-cp uh-cp-ok">Authorized '+m[2]+'</span><span class="uh-cp uh-cp-w">Pending '+m[3]+'</span><span class="uh-cp uh-cp-d">New Pending '+m[4]+'</span><span class="uh-cp uh-cp-ok">New Auth '+m[5]+'</span><span class="uh-cp '+(parseInt(m[6])>0?'uh-cp-w':'uh-cp-d')+'">Revoked '+m[6]+'</span><span class="uh-cp uh-cp-d">Managed '+m[7]+'</span>';return}
  }
}

window.uhRL=function(){
  if(loading)return;uhCG(true);loading=true;cP();ALL=[];CUR=[];fOff=0;nrc=0;
  document.getElementById('uhTB').innerHTML='<tr><td colspan="3" style="text-align:center;padding:40px;color:#90a4ae">Loading…</td></tr>';
  var ln=document.getElementById('uhLn').value;
  fetch('api.cgi?action=tail&pos=0&lines='+ln).then(function(r){return r.json()}).then(function(d){
    if(d.error){loading=false;return}ALL=bi(d.rows||[]);fOff=d.pos||0;uhAF();ucs();loading=false;if(live)sP();
  }).catch(function(){loading=false});
};

function poll(){
  if(!live||grep)return;
  var tw=document.getElementById('uhTW'),sp=tw.scrollTop;
  fetch('api.cgi?action=tail&pos='+fOff+'&lines=200').then(function(r){return r.json()}).then(function(d){
    if(!d.rows||!d.rows.length)return;
    var nr=bi(d.rows);fOff=d.pos;
    if(!nr.length)return;
    ALL=nr.concat(ALL);if(ALL.length>MR)ALL=ALL.slice(0,MR);nrc+=nr.length;
    uhAF(nr.length);ucs();if(sp>50){document.getElementById('uhNC').textContent=nrc;document.getElementById('uhNB').style.display='block'}
  }).catch(function(){});
}
function sP(){cP();pTmr=setInterval(poll,PI)}
function cP(){if(pTmr){clearInterval(pTmr);pTmr=null}}

window.uhTL=function(){
  live=!live;var el=document.getElementById('uhLB'),dt=document.getElementById('uhDt'),ll=document.getElementById('uhLL');
  if(live){el.className='uh-live';dt.className='dot pulse';ll.textContent='LIVE';if(!grep)sP()}
  else{el.className='uh-live paused';dt.className='dot';ll.textContent='PAUSED';cP()}
};
window.uhCI=function(){PI=parseInt(document.getElementById('uhIv').value);if(live&&!grep)sP()};

window.uhTG=function(){if(grep)uhCG(false);else uhGS()};
window.uhGS=function(){
  var q=document.getElementById('uhQ').value.trim();if(!q){uhRL();return}
  if(loading)return;loading=true;cP();ALL=[];CUR=[];nrc=0;grep=true;
  var btn=document.getElementById('uhBG');btn.innerHTML='<span class="uh-sp"></span> Searching…';
  document.getElementById('uhTB').innerHTML='<tr><td colspan="3" style="text-align:center;padding:40px;color:#90a4ae">Searching entire log…</td></tr>';
  fetch('api.cgi?action=grep&q='+encodeURIComponent(q)).then(function(r){return r.json()}).then(function(d){
    if(d.error){loading=false;rgB();return}ALL=bi(d.rows||[]);fOff=d.offset||0;
    document.getElementById('uhGT').textContent=q;document.getElementById('uhGC').textContent=ALL.length;
    document.getElementById('uhGB').style.display='flex';uhAF();ucs();loading=false;sgB();
  }).catch(function(){loading=false;rgB();grep=false});
};
function sgB(){var b=document.getElementById('uhBG');b.classList.add('grep-on');b.innerHTML='&#10005; Live mode'}
function rgB(){var b=document.getElementById('uhBG');b.classList.remove('grep-on');b.innerHTML='Full log'}
window.uhCG=function(s){grep=false;document.getElementById('uhGB').style.display='none';rgB();if(!s)uhRL()};
window.uhJT=function(){nrc=0;uhAF(0);requestAnimationFrame(function(){document.getElementById('uhTW').scrollTop=0;document.getElementById('uhNB').style.display='none'})};
window.uhTDM=uhTDM;

function pS(){
  fetch('api.cgi?action=status').then(function(r){return r.json()}).then(function(d){
    var dt=document.getElementById('uhSD'),lb=document.getElementById('uhSL');
    if(d.active){dt.className='sd on';lb.innerHTML='PID '+d.pid+(d.uptime?' · '+d.uptime:'')+(d.mem?' · '+d.mem:'')}
    else{dt.className='sd off';lb.textContent='stopped'}
  }).catch(function(){});
}

document.getElementById('uhQ').addEventListener('input',function(){if(!grep)uhAF()});
document.getElementById('uhLv').addEventListener('change',function(){uhAF()});

pS();setInterval(pS,30000);uhRL();
})();
</script>
HTMLBLOCK

&ui_print_footer("/", $text{'index'});
INDEXCGI

    chmod 755 "$MODDIR/index.cgi"

    # ============================================================
    # 3. module.info
    # ============================================================
    cat > "$MODDIR/module.info" <<'EOF'
desc=UniFi Hotspot Log Viewer
longdesc=Real-time log viewer for the uhotspotd daemon
category=net
os_support=*-linux
version=1.0
depends=webmin
EOF

    cat > "$MODDIR/module.info.es" <<'EOF'
desc=Visor de Log del Hotspot UniFi
longdesc=Visor de log en tiempo real para el demonio uhotspotd
category=net
os_support=*-linux
version=1.0
depends=webmin
EOF

    # ============================================================
    # 4. Language files
    # ============================================================
    cat > "$MODDIR/lang/en" <<'EOF'
index_title=UniFi Hotspot Log Viewer
index=Webmin Index
EOF

    cat > "$MODDIR/lang/es" <<'EOF'
index_title=Visor de Log del Hotspot UniFi
index=Índice de Webmin
EOF

    # ============================================================
    # 5. Icon (base64) — UH (UniFi Hotspot) 48x48
    # ============================================================
    cat > /tmp/uh_icon.gif.b64 << 'ICONEOF'
R0lGODdhMAAwAIUAAP////v8/vv8/fj6/Ovw9+rv9uPq8+Hn8tfh78LR5rnK4rTH4LLF37DD3qO62aO52aG42IKhy32dyXiZx3eZx3SWxW6Sw22QwmOJvmCHvT5trzpqrTNlqjJkqi5hqCpepyBXox1UoRxToRpSoAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACwAAAAAMAAwAEAI+QBHCBxIsKDBgwgTKlzIsGFDDQAiPiB4ISIACgIhSix4IGIBhwQ1Apg4sGJEjCNEkhzYEcBHkDBjypxJs6bNmzgdqqRoEeVOgi1fxoxgEQKHDxMCRFQw8CdLjzmjSp1KtarVq1izLnQ6wuTFjBZXCgwqk6tXnxbTqhUK8oNFBgQlWMQAdiNQqDQzLDAwQACBBBNAhAzLEa/Ww4gTK17MuLHjx5AjS568lXDJnnVHFnZZ1rLAs5nFjiAb0yzmlJ7HGgZp+mRmtWnZOtxg0QFBCxYrhN4s22FLAyIGNrDYYfddzjJDMIAdEYGHpqlHr6ZMvbr169iza5cZEAA7
ICONEOF
    base64 -d /tmp/uh_icon.gif.b64 > "$MODDIR/images/icon.gif" 2>/dev/null || true
    rm -f /tmp/uh_icon.gif.b64

    # ============================================================
    # 6. Library (required by Webmin config system)
    # ============================================================
    cat > "$MODDIR/uhotspot-lib.pl" <<'EOF'
#!/usr/bin/perl
# uhotspot-lib.pl

do '../web-lib.pl';
do '../ui-lib.pl';
&init_config();

1;
EOF
    chmod 755 "$MODDIR/uhotspot-lib.pl"

    # ============================================================
    # 7. config.info (one setting: log file path)
    # ============================================================
    cat > "$MODDIR/config.info" <<'EOF'
log_file=Log file path,0,/var/log/uhotspot.log
EOF

    cat > "$MODDIR/config.info.es" <<'EOF'
log_file=Ruta del archivo de log,0,/var/log/uhotspot.log
EOF

    cat > "$ETCDIR/config" <<'EOF'
log_file=/var/log/uhotspot.log
EOF

    # ============================================================
    # 8. Permissions & registration
    # ============================================================
    chown -R root:root "$MODDIR" "$ETCDIR"
    chmod -R 755 "$MODDIR"
    chmod 644 "$MODDIR"/*.info* "$MODDIR/lang/"* 2>/dev/null || true
    chmod 755 "$MODDIR"/*.cgi "$MODDIR/uhotspot-lib.pl" 2>/dev/null || true
    chmod 644 "$MODDIR/images/"* 2>/dev/null || true

    if [[ -f /etc/webmin/webmin.acl ]] && ! grep -q "$MODNAME" /etc/webmin/webmin.acl; then
        sed -i.bak "s/\\(^root:.*\\)/\\1 $MODNAME/" /etc/webmin/webmin.acl
        rm -f /etc/webmin/webmin.acl.bak
        echo "✓ Module added to webmin.acl"
    fi

    rm -f /var/webmin/module.infos.cache

    echo "Restarting Webmin service..."
    systemctl restart webmin.service 2>/dev/null || /etc/webmin/restart 2>/dev/null || true

    echo ""
    echo "=========================================="
    echo "✓ UniFi Hotspot Log Viewer installed!"
    echo "=========================================="
    echo ""
    echo "Module location: $MODDIR"
    echo "Category: Networking"
    echo "URL: https://localhost:10000/$MODNAME/"
    echo ""
    echo "Please log out and log back into Webmin."
    echo ""
}

uninstall_module() {
    echo ""
    echo "=========================================="
    echo "Uninstalling UniFi Hotspot Log Viewer"
    echo "=========================================="
    echo ""

    if [ ! -d "$MODDIR" ]; then
        echo "⚠  Module is not installed."
        return 1
    fi

    rm -rf "$MODDIR"
    rm -rf "$ETCDIR"
    echo "✓ Module directories removed"

    if [[ -f /etc/webmin/webmin.acl ]] && grep -q "$MODNAME" /etc/webmin/webmin.acl; then
        sed -i.bak "s/ $MODNAME//g" /etc/webmin/webmin.acl
        rm -f /etc/webmin/webmin.acl.bak
        echo "✓ Module removed from webmin.acl"
    fi

    rm -f /var/webmin/module.infos.cache
    systemctl restart webmin.service 2>/dev/null || /etc/webmin/restart 2>/dev/null || true

    echo ""
    echo "=========================================="
    echo "✓ Module uninstalled"
    echo "=========================================="
    echo ""
}

show_menu() {
    clear
    echo "============================================================"
    echo "      UNIFI HOTSPOT LOG VIEWER - WEBMIN MODULE"
    echo "              Installation Menu"
    echo "============================================================"
    echo ""
    echo "  1) Install module"
    echo "  2) Uninstall module"
    echo "  3) Exit"
    echo ""
    echo -n "Select an option [1-3]: "
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  install      Install the module"
    echo "  uninstall    Uninstall the module"
    echo "  -h, --help   Show this help message"
    echo ""
}

main() {
    if [ ! -d "/usr/share/webmin" ] && [ ! -d "/etc/webmin" ]; then
        echo "Error: Webmin is not installed on this system"
        exit 1
    fi

    if [ $# -gt 0 ]; then
        case "$1" in
            install)    install_module; exit 0 ;;
            uninstall)  uninstall_module; exit 0 ;;
            -h|--help)  show_usage; exit 0 ;;
            *)          echo "Error: Invalid option '$1'"; show_usage; exit 1 ;;
        esac
    fi

    while true; do
        show_menu
        read -r option
        case $option in
            1) install_module; echo ""; read -p "Press Enter to continue..." ;;
            2) uninstall_module; echo ""; read -p "Press Enter to continue..." ;;
            3) echo ""; exit 0 ;;
            *) echo "Invalid option."; sleep 2 ;;
        esac
    done
}

main "$@"
