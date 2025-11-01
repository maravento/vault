#!/bin/bash
# maravento.com
#
# Net Report
# ------------
# Brief: Simple menu-driven nmap wrapper that produces timestamped HTML reports
#        in ~/Report (owned by the non-root local user). No automatic browser open.
#
# Requirements:
#   - Run as root (sudo) because scans use -sS and -O.
#   - Packages: nmap, xsltproc (script will check if missing).
#
# Outputs:
#   - /home/<user>/Report/scan_TIMESTAMP.html
#   - Only .html files remain in Report (script deletes intermediate .xml/.nmap/.gnmap).
#
# Menu options:
#   1) LAN Scan
#      nmap -sS -T4 -F -sV <detected-network>  -> output: scan_TIMESTAMP.html
#   2) Advanced LAN Scan
#      nmap -sS -T4 -F -sV -sC --max-retries 3 --host-timeout 5m <network>
#      -> output: scan_deep_TIMESTAMP.html
#   3) IP Scan
#      nmap -sS -T4 -F -sV --version-intensity 8 -sC -O --script vuln --traceroute \
#          -oA <base> --max-retries 3 --host-timeout 10m <target>
#      -> output: scan_ip_TIMESTAMP.html
#   4) Exit
#
# Usage:
#   sudo /path/to/netreport.sh

set -euo pipefail
IFS=$'\n\t'

timestamp() { date +%F-%H_%M_%S; }
now() { date '+%F %T'; }
log() { echo "ℹ️  $(now) - $*"; }
warn() { echo "⚠️  $(now) - $*" >&2; }
die() { echo "❌ $(now) - $*" >&2; exit 1; }

# root required (nmap syn scans and -O require root)
[ "$(id -u)" -eq 0 ] || die "Run as root (use sudo)"

# detect non-root local user (owner of the session)
local_user="${SUDO_USER:-$(logname 2>/dev/null || true)}"
# fallback to first logged user if empty
if [ -z "$local_user" ] || [ "$local_user" = "root" ]; then
  local_user="$(who | awk '{print $1; exit}')"
fi
local_user="${local_user:-root}"
log "Local user: $local_user"

# Report directory (owned by user)
report_dir="/home/${local_user}/Report"
mkdir -p "$report_dir"
chown "$local_user:$local_user" "$report_dir"
chmod 0755 "$report_dir"

# Log file for debugging
log_file="/tmp/netreport_debug.log"
> "$log_file"  # Clear previous log

# === Check dependencies once at start ===
required=(nmap xsltproc)
missing=()
for pkg in "${required[@]}"; do
    if ! command -v "$pkg" &>/dev/null; then
        missing+=("$pkg")
    fi
done

if [ "${#missing[@]}" -gt 0 ]; then
    die "Missing packages: ${missing[*]}. Please install them first."
else
    log "✅ Dependencies OK"
fi

# Create embedded custom XSL stylesheet
create_custom_xsl() {
  local xsl_file="$1"
  
  cat > "$xsl_file" << 'XSLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="html" encoding="UTF-8" indent="yes" doctype-system="about:legacy-compat"/>

<xsl:template match="/">
<html>
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>Nmap Scan Report - <xsl:value-of select="nmaprun/runstats/finished/@timestr"/></title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { 
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
      background: #f5f7fa;
      color: #2c3e50;
      line-height: 1.6;
      padding: 20px;
    }
    .container { max-width: 1200px; margin: 0 auto; background: white; box-shadow: 0 2px 10px rgba(0,0,0,0.1); border-radius: 8px; }
    .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; border-radius: 8px 8px 0 0; }
    .header h1 { font-size: 2em; margin-bottom: 10px; }
    .header .info { opacity: 0.9; font-size: 0.95em; }
    .summary { padding: 25px; background: #f8f9fa; border-bottom: 1px solid #e9ecef; }
    .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-top: 15px; }
    .summary-item { background: white; padding: 15px; border-radius: 6px; border-left: 4px solid #667eea; }
    .summary-item strong { display: block; color: #667eea; font-size: 0.85em; text-transform: uppercase; margin-bottom: 5px; }
    .summary-item span { font-size: 1.3em; font-weight: bold; color: #2c3e50; }
    .content { padding: 25px; }
    .host { margin-bottom: 30px; border: 1px solid #e9ecef; border-radius: 6px; overflow: hidden; }
    .host-header { background: #667eea; color: white; padding: 15px 20px; }
    .host-header h2 { font-size: 1.4em; }
    .host-info { padding: 20px; background: #f8f9fa; border-bottom: 1px solid #e9ecef; }
    .host-info-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 15px; }
    .info-item { display: flex; align-items: center; }
    .info-item strong { min-width: 100px; color: #667eea; }
    .ports { padding: 20px; }
    .ports h3 { margin-bottom: 15px; color: #2c3e50; border-bottom: 2px solid #667eea; padding-bottom: 8px; }
    .port-table { width: 100%; border-collapse: collapse; margin-top: 15px; }
    .port-table th { background: #667eea; color: white; padding: 12px; text-align: left; font-weight: 600; font-size: 0.9em; }
    .port-table td { padding: 12px; border-bottom: 1px solid #e9ecef; }
    .port-table tr:hover { background: #f8f9fa; }
    .port-open { color: #27ae60; font-weight: bold; }
    .port-closed { color: #e74c3c; }
    .port-filtered { color: #f39c12; }
    .script-output { background: #2c3e50; color: #ecf0f1; padding: 15px; border-radius: 6px; margin-top: 10px; font-family: 'Courier New', monospace; font-size: 0.9em; overflow-x: auto; white-space: pre-wrap; word-wrap: break-word; }
    .badge { display: inline-block; padding: 4px 10px; border-radius: 12px; font-size: 0.85em; font-weight: 600; }
    .badge-success { background: #d4edda; color: #155724; }
    .badge-danger { background: #f8d7da; color: #721c24; }
    .badge-warning { background: #fff3cd; color: #856404; }
    .footer { padding: 20px; text-align: center; background: #f8f9fa; border-top: 1px solid #e9ecef; color: #6c757d; font-size: 0.9em; }
    .no-data { padding: 40px; text-align: center; color: #6c757d; font-style: italic; }
    @media (max-width: 768px) {
      .summary-grid, .host-info-grid { grid-template-columns: 1fr; }
      .port-table { font-size: 0.85em; }
      .port-table th, .port-table td { padding: 8px; }
    }
  </style>
</head>
<body>
<div class="container">
  
  <!-- Header -->
  <div class="header">
    <h1>🔍 Nmap Scan Report</h1>
    <div class="info">
      <div>Command: <xsl:value-of select="nmaprun/@args"/></div>
      <div>Scan started: <xsl:value-of select="nmaprun/@startstr"/></div>
      <div>Nmap version: <xsl:value-of select="nmaprun/@version"/></div>
    </div>
  </div>
  
  <!-- Summary -->
  <div class="summary">
    <h2>📊 Scan Summary</h2>
    <div class="summary-grid">
      <div class="summary-item">
        <strong>Total Hosts</strong>
        <span><xsl:value-of select="count(nmaprun/host)"/></span>
      </div>
      <div class="summary-item">
        <strong>Hosts Up</strong>
        <span><xsl:value-of select="count(nmaprun/host[status[@state='up']])"/></span>
      </div>
      <div class="summary-item">
        <strong>Open Ports</strong>
        <span><xsl:value-of select="count(nmaprun/host/ports/port[state[@state='open']])"/></span>
      </div>
      <div class="summary-item">
        <strong>Duration</strong>
        <span><xsl:value-of select="format-number(nmaprun/runstats/finished/@elapsed, '#.##')"/>s</span>
      </div>
    </div>
  </div>
  
  <!-- Hosts -->
  <div class="content">
    <xsl:choose>
      <xsl:when test="count(nmaprun/host) = 0">
        <div class="no-data">
          <h3>No hosts found</h3>
          <p>The scan did not discover any active hosts in the specified range.</p>
        </div>
      </xsl:when>
      <xsl:otherwise>
        <xsl:for-each select="nmaprun/host">
          <div class="host">
            
            <!-- Host Header -->
            <div class="host-header">
              <h2>
                <xsl:choose>
                  <xsl:when test="address[@addrtype='ipv4']">
                    <xsl:value-of select="address[@addrtype='ipv4']/@addr"/>
                  </xsl:when>
                  <xsl:when test="address[@addrtype='ipv6']">
                    <xsl:value-of select="address[@addrtype='ipv6']/@addr"/>
                  </xsl:when>
                  <xsl:otherwise>Unknown</xsl:otherwise>
                </xsl:choose>
                <xsl:if test="hostnames/hostname[@name!='']">
                  (<xsl:value-of select="hostnames/hostname/@name"/>)
                </xsl:if>
              </h2>
            </div>
            
            <!-- Host Info -->
            <div class="host-info">
              <div class="host-info-grid">
                <div class="info-item">
                  <strong>Status:</strong>
                  <xsl:choose>
                    <xsl:when test="status[@state='up']">
                      <span class="badge badge-success">UP</span>
                    </xsl:when>
                    <xsl:otherwise>
                      <span class="badge badge-danger">DOWN</span>
                    </xsl:otherwise>
                  </xsl:choose>
                </div>
                
                <xsl:if test="address[@addrtype='mac']">
                  <div class="info-item">
                    <strong>MAC:</strong>
                    <span><xsl:value-of select="address[@addrtype='mac']/@addr"/>
                    <xsl:if test="address[@addrtype='mac']/@vendor">
                      (<xsl:value-of select="address[@addrtype='mac']/@vendor"/>)
                    </xsl:if>
                    </span>
                  </div>
                </xsl:if>
                
                <xsl:if test="os/osmatch">
                  <div class="info-item">
                    <strong>OS:</strong>
                    <span><xsl:value-of select="os/osmatch[1]/@name"/> (<xsl:value-of select="os/osmatch[1]/@accuracy"/>%)</span>
                  </div>
                </xsl:if>
                
                <xsl:if test="uptime">
                  <div class="info-item">
                    <strong>Uptime:</strong>
                    <span><xsl:value-of select="format-number(uptime/@seconds div 86400, '#.#')"/> days</span>
                  </div>
                </xsl:if>
              </div>
            </div>
            
            <!-- Ports -->
            <xsl:if test="ports/port">
              <div class="ports">
                <h3>🔌 Open Ports (<xsl:value-of select="count(ports/port[state[@state='open']])"/>)</h3>
                <table class="port-table">
                  <thead>
                    <tr>
                      <th>Port</th>
                      <th>State</th>
                      <th>Service</th>
                      <th>Version</th>
                    </tr>
                  </thead>
                  <tbody>
                    <xsl:for-each select="ports/port[state[@state='open']]">
                      <tr>
                        <td><strong><xsl:value-of select="@portid"/>/<xsl:value-of select="@protocol"/></strong></td>
                        <td>
                          <xsl:attribute name="class">
                            <xsl:choose>
                              <xsl:when test="state[@state='open']">port-open</xsl:when>
                              <xsl:when test="state[@state='closed']">port-closed</xsl:when>
                              <xsl:otherwise>port-filtered</xsl:otherwise>
                            </xsl:choose>
                          </xsl:attribute>
                          <xsl:value-of select="state/@state"/>
                        </td>
                        <td><xsl:value-of select="service/@name"/></td>
                        <td>
                          <xsl:value-of select="service/@product"/>
                          <xsl:if test="service/@version">
                            <xsl:text> </xsl:text><xsl:value-of select="service/@version"/>
                          </xsl:if>
                          <xsl:if test="service/@extrainfo">
                            <br/><small><xsl:value-of select="service/@extrainfo"/></small>
                          </xsl:if>
                        </td>
                      </tr>
                      
                      <!-- Script Output for this port -->
                      <xsl:if test="script">
                        <tr>
                          <td colspan="4">
                            <xsl:for-each select="script">
                              <div style="margin: 10px 0;">
                                <strong>Script: <xsl:value-of select="@id"/></strong>
                                <div class="script-output"><xsl:value-of select="@output"/></div>
                              </div>
                            </xsl:for-each>
                          </td>
                        </tr>
                      </xsl:if>
                    </xsl:for-each>
                  </tbody>
                </table>
              </div>
            </xsl:if>
            
            <!-- Host Scripts -->
            <xsl:if test="hostscript/script">
              <div class="ports">
                <h3>📝 Host Scripts</h3>
                <xsl:for-each select="hostscript/script">
                  <div style="margin: 15px 0;">
                    <strong><xsl:value-of select="@id"/></strong>
                    <div class="script-output"><xsl:value-of select="@output"/></div>
                  </div>
                </xsl:for-each>
              </div>
            </xsl:if>
            
          </div>
        </xsl:for-each>
      </xsl:otherwise>
    </xsl:choose>
  </div>
  
  <!-- Footer -->
  <div class="footer">
    <p>Report generated by Net Report | Nmap <xsl:value-of select="nmaprun/@version"/></p>
    <p>Scan completed: <xsl:value-of select="nmaprun/runstats/finished/@timestr"/></p>
  </div>
  
</div>
</body>
</html>
</xsl:template>

</xsl:stylesheet>
XSLEOF
}

# spinner while PID runs
show_spinner_for_pid() {
  local pid=$1
  local spin='|/-\\'
  local i=0
  printf "[-] Working..."
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i+1) %4 ))
    printf "\r[-] Working... %s" "${spin:$i:1}"
    sleep 0.2
  done
  wait "$pid" || true
  printf "\r[-] Done.           \n"
}

# convert XML -> HTML with improved error handling
xml_to_html() {
  local xml="$1" 
  local html="$2" 
  local xsl="/tmp/netreport-custom.xsl"
  local xsl_error="/tmp/xsltproc_error.log"
  
  log "Converting XML to HTML: $xml -> $html"
  
  # Verify XML file exists and is not empty
  if [ ! -f "$xml" ]; then
    warn "XML file does not exist: $xml"
    return 1
  fi
  
  if [ ! -s "$xml" ]; then
    warn "XML file is empty: $xml"
    return 1
  fi
  
  # Create custom XSL if not present
  if [ ! -f "$xsl" ]; then
    log "Creating custom XSL stylesheet..."
    create_custom_xsl "$xsl"
  fi
  
  # Try conversion with custom XSL
  log "Converting with custom XSL..."
  if xsltproc -o "$html" "$xsl" "$xml" 2>"$xsl_error"; then
    log "✅ Conversion successful"
    rm -f "$xsl_error"
    return 0
  else
    warn "Custom XSL conversion failed:"
    cat "$xsl_error" | head -5 | while read -r line; do warn "  $line"; done
    cat "$xsl_error" >> "$log_file"
  fi
  
  # Fallback: try default nmap XSL
  log "Attempting conversion with default nmap XSL..."
  if xsltproc "$xml" -o "$html" 2>"$xsl_error"; then
    log "✅ Conversion successful with default XSL"
    rm -f "$xsl_error"
    return 0
  else
    warn "Default XSL conversion failed:"
    cat "$xsl_error" | head -5 | while read -r line; do warn "  $line"; done
    cat "$xsl_error" >> "$log_file"
  fi
  
  # Last resort: create basic HTML wrapper
  warn "All XSL conversions failed, creating basic HTML wrapper"
  {
    echo '<!DOCTYPE html>'
    echo '<html><head><meta charset="UTF-8">'
    echo '<title>Nmap Scan Report</title>'
    echo '<style>body{font-family:monospace;padding:20px;background:#f5f5f5}pre{background:#fff;padding:15px;border:1px solid #ddd;overflow:auto}</style>'
    echo '</head><body><h1>Nmap Scan Report</h1><pre>'
    # Escape XML special characters for HTML display
    sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' "$xml"
    echo '</pre></body></html>'
  } > "$html"
  
  return 0
}

# Clean intermediate files from a given base path
cleanup_intermediate_files() {
  local base="$1"
  log "Cleaning intermediate files: ${base}.*"
  rm -f "${base}.xml" "${base}.nmap" "${base}.gnmap" 2>/dev/null || true
}

# Ensure only .html files remain in Report directory
prune_report_dir_keep_html() {
  log "Pruning non-HTML files from $report_dir"
  find "$report_dir" -maxdepth 1 -type f ! -name '*.html' -print0 2>/dev/null | xargs -0 -r rm -f -- 2>/dev/null || true
}

# Verify and finalize HTML report
finalize_html_report() {
  local html_file="$1"
  
  if [ ! -f "$html_file" ]; then
    die "HTML report was not created: $html_file"
  fi
  
  if [ ! -s "$html_file" ]; then
    die "HTML report is empty: $html_file"
  fi
  
  # Set proper ownership and permissions
  chown "$local_user:$local_user" "$html_file" 2>/dev/null || true
  chmod 0644 "$html_file"
  
  local file_size=$(du -h "$html_file" | cut -f1)
  log "✅ Report saved: $html_file (size: $file_size)"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📄 Report: $html_file"
  echo "📊 Size: $file_size"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
}

# MENU
TS=$(timestamp)
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "       Net Report - Network Scanner"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1) LAN Scan"
echo "2) Advanced LAN Scan"
echo "3) IP Scan"
echo "4) Exit"
echo ""
read -rp "Select [1-4]: " opt
echo ""

case "$opt" in
  1)
    # Option 1: LAN Scan => scan_TIMESTAMP.html
    log "=== Option 1: LAN Scan ==="
    net=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | head -n1 || echo "192.168.0.0/24")
    xml_file="${report_dir}/scan_${TS}.xml"
    html_file="${report_dir}/scan_${TS}.html"
    
    log "Starting LAN Scan on $net"
    
    # Run nmap in background
    nmap -sS -T4 -F -sV "$net" -oX "$xml_file" > /tmp/netreport_nmap_out 2>&1 &
    pid=$!
    show_spinner_for_pid "$pid"
    
    # Convert and finalize
    xml_to_html "$xml_file" "$html_file" || die "Failed to convert XML to HTML"
    finalize_html_report "$html_file"
    cleanup_intermediate_files "${report_dir}/scan_${TS}"
    prune_report_dir_keep_html
    ;;
    
  2)
    # Option 2: Advanced LAN Scan => scan_deep_TIMESTAMP.html
    log "=== Option 2: Advanced LAN Scan ==="
    net=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | head -n1 || echo "192.168.0.0/24")
    xml_file="${report_dir}/scan_deep_${TS}.xml"
    html_file="${report_dir}/scan_deep_${TS}.html"
    
    log "Starting Advanced LAN Scan on $net"
    log "This may take several minutes..."
    
    # Run nmap in background
    nmap -sS -T4 -F -sV -sC --max-retries 3 --host-timeout 5m "$net" -oX "$xml_file" > /tmp/netreport_nmap_out 2>&1 &
    pid=$!
    show_spinner_for_pid "$pid"
    
    # Convert and finalize
    xml_to_html "$xml_file" "$html_file" || die "Failed to convert XML to HTML"
    finalize_html_report "$html_file"
    cleanup_intermediate_files "${report_dir}/scan_deep_${TS}"
    prune_report_dir_keep_html
    ;;
    
  3)
    # Option 3: IP Scan (Complete) => scan_ip_TIMESTAMP.html
    log "=== Option 3: IP/Host Scan (Complete) ==="
    read -rp "Target IP/Host: " target
    [ -n "$target" ] || die "No target specified"
    
    # Validate target format (basic check)
    if ! [[ "$target" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.\-]+$ ]]; then
      die "Invalid target format: $target"
    fi
    
    base="${report_dir}/scan_ip_${TS}"
    xml_file="${base}.xml"
    html_file="${report_dir}/scan_ip_${TS}.html"
    
    log "Starting complete IP Scan on: $target"
    log "This scan includes vulnerability detection and may take 10-15 minutes..."
    
    # Complete scan matching Windows version EXACTLY
    # -Pn: Skip host discovery (CRITICAL for gateways that filter pings)
    # Same options as Windows version that works
    nmap -Pn -sS -T4 -F -sV --version-intensity 8 -sC -O \
         --script vuln --traceroute \
         -oA "$base" \
         --max-retries 3 --host-timeout 10m \
         "$target" 2>&1 | tee /tmp/netreport_nmap_out &
    pid=$!
    show_spinner_for_pid "$pid"
    
    # Verify XML was created
    if [ ! -f "$xml_file" ]; then
      warn "XML file not found: $xml_file"
      
      # Check if .nmap file exists as fallback
      if [ -f "${base}.nmap" ]; then
        warn "Found .nmap file, converting to HTML..."
        {
          echo '<!DOCTYPE html>'
          echo '<html><head><meta charset="UTF-8">'
          echo '<title>Nmap Scan Report - '$target'</title>'
          echo '<style>body{font-family:monospace;padding:20px;background:#f5f5f5}pre{background:#fff;padding:15px;border:1px solid #ddd;overflow:auto;line-height:1.4}</style>'
          echo '</head><body><h1>Nmap Scan Report: '$target'</h1>'
          echo '<p><strong>Note:</strong> XML output not available, displaying text format.</p><pre>'
          cat "${base}.nmap"
          echo '</pre></body></html>'
        } > "$html_file"
        
        finalize_html_report "$html_file"
        cleanup_intermediate_files "$base"
        prune_report_dir_keep_html
        exit 0
      else
        die "No nmap output files found. Check /tmp/netreport_nmap_out and $log_file"
      fi
    fi
    
    # Verify XML is not empty
    if [ ! -s "$xml_file" ]; then
      die "XML file is empty: $xml_file. Check $log_file for details"
    fi
    
    log "XML file created successfully ($(du -h "$xml_file" | cut -f1))"
    
    # Convert to HTML
    if ! xml_to_html "$xml_file" "$html_file"; then
      die "Failed to convert XML to HTML. Check $log_file for details"
    fi
    
    # Finalize and cleanup
    finalize_html_report "$html_file"
    cleanup_intermediate_files "$base"
    prune_report_dir_keep_html
    ;;
    
  5)
    # Option 4: IP Scan (Fast - Top 1000) => scan_ip_fast_TIMESTAMP.html
    log "=== Option 4: IP/Host Scan (Fast) ==="
    read -rp "Target IP/Host: " target
    [ -n "$target" ] || die "No target specified"
    
    # Validate target format (basic check)
    if ! [[ "$target" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.\-]+$ ]]; then
      die "Invalid target format: $target"
    fi
    
    base="${report_dir}/scan_ip_fast_${TS}"
    xml_file="${base}.xml"
    html_file="${report_dir}/scan_ip_fast_${TS}.html"
    
    log "Starting FAST scan on: $target"
    log "Scanning top 1000 most common ports (5-10 minutes)..."
    
    # Fast scan: Top 1000 ports, skip host discovery for reliability
    # -Pn: Skip ping (avoids being filtered by gateway)
    # -T4: Aggressive timing
    # --top-ports 1000: Most common 1000 ports
    nmap -Pn -sS -T4 --top-ports 1000 -sV --version-intensity 6 -sC \
         --script vuln --traceroute \
         -oA "$base" \
         --max-retries 2 --host-timeout 10m \
         "$target" > /tmp/netreport_nmap_out 2>&1 &
    pid=$!
    show_spinner_for_pid "$pid"
    
    # Verify XML was created
    if [ ! -f "$xml_file" ]; then
      warn "XML file not found: $xml_file"
      
      # Check if .nmap file exists as fallback
      if [ -f "${base}.nmap" ]; then
        warn "Found .nmap file, converting to HTML..."
        {
          echo '<!DOCTYPE html>'
          echo '<html><head><meta charset="UTF-8">'
          echo '<title>Nmap Scan Report - '$target'</title>'
          echo '<style>body{font-family:monospace;padding:20px;background:#f5f5f5}pre{background:#fff;padding:15px;border:1px solid #ddd;overflow:auto;line-height:1.4}</style>'
          echo '</head><body><h1>Nmap Scan Report: '$target'</h1>'
          echo '<p><strong>Note:</strong> XML output not available, displaying text format.</p><pre>'
          cat "${base}.nmap"
          echo '</pre></body></html>'
        } > "$html_file"
        
        finalize_html_report "$html_file"
        cleanup_intermediate_files "$base"
        prune_report_dir_keep_html
        exit 0
      else
        die "No nmap output files found. Check /tmp/netreport_nmap_out and $log_file"
      fi
    fi
    
    # Verify XML is not empty
    if [ ! -s "$xml_file" ]; then
      die "XML file is empty: $xml_file. Check $log_file for details"
    fi
    
    log "XML file created successfully ($(du -h "$xml_file" | cut -f1))"
    
    # Convert to HTML
    if ! xml_to_html "$xml_file" "$html_file"; then
      die "Failed to convert XML to HTML. Check $log_file for details"
    fi
    
    # Finalize and cleanup
    finalize_html_report "$html_file"
    cleanup_intermediate_files "$base"
    prune_report_dir_keep_html
    ;;
    
  4)
    log "Exit requested"
    echo "Goodbye!"
    exit 0
    ;;
    
  *)
    die "Invalid option: $opt"
    ;;
esac

log "=== Scan completed successfully ==="
log "Debug log saved at: $log_file"
echo ""
