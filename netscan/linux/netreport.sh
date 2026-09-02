#!/bin/bash
# maravento.com
#
################################################################################
#
# Net Report
# ------------
# Brief: Simple menu-driven nmap wrapper that produces timestamped HTML reports
# in ~/Report (owned by the non-root local user). No automatic browser open.
#
# Requirements:
# - Run as root (sudo) because scans use -sS and -O.
# - Packages: nmap, xsltproc, iproute2, util-linux (script will check if missing).
#
# Outputs:
# - /home/<user>/Report/scan_TIMESTAMP.html
# - Intermediate .xml/.nmap/.gnmap files are deleted after each scan.
#
# Log file:
# /var/log/netreport.log -- truncated on every run (single-run tool, no rotation).
#
# Menu options:
# 1) LAN Scan
# Lists available interfaces and asks user to select one.
# nmap -sS -T4 -F -sV <selected-network>
# -> output: scan_TIMESTAMP.html
# 2) Advanced LAN Scan
# Lists available interfaces and asks user to select one.
# nmap -sS -T4 -p- -sV -sC --max-retries 3 --host-timeout 5m <network>
# -> output: scan_deep_TIMESTAMP.html
# 3) IP/Host Scan
# Lists available interfaces, asks user to select one, performs a quick
# ping sweep to show active hosts, then asks for the target IP or hostname.
# nmap -Pn -sS -T4 -p- -sV --version-intensity 8 -sC -O --script vuln --traceroute \
# -oA <base> --max-retries 3 --host-timeout 10m <target>
# -> output: scan_ip_TIMESTAMP.html
# 4) Exit
#
# Usage:
# sudo /path/to/netreport.sh
#
################################################################################

set -euo pipefail

# VALIDATION -- one variable per thing validated; use directly with =~
_UH_IPV4='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])$'
_UH_FQDN='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'

timestamp() { date +%F-%H_%M_%S; }

# logging
log_file="/var/log/netreport.log"
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" | tee -a "$log_file" 2>/dev/null || true
}

## root check
if [ "$(id -u)" != "0" ]; then
    log "ERROR: This script must be run as root -- abort"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$SCRIPT_LOCK")
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    log "ERROR: script $(basename "$0") is already running -- abort"
    exit 1
fi

# Single-run tool, not a daemon -- the log only ever needs to hold the
# current execution, so it is truncated on every start instead of rotated.
truncate -s 0 "$log_file" 2>/dev/null || true

# LOCAL USER detection
detect_local_user() {
    local uid_min uid_max
    local user uid best_user="" best_uid=999999

    uid_min=$(awk '/^UID_MIN/{print $2}' /etc/login.defs 2>/dev/null)
    uid_max=$(awk '/^UID_MAX/{print $2}' /etc/login.defs 2>/dev/null)
    uid_min=${uid_min:-1000}
    uid_max=${uid_max:-60000}

    while IFS=: read -r user _ uid _ _ _ shell; do
        [ "$user" = "root" ] && continue
        [ -z "$uid" ] && continue
        [ "$uid" -lt "$uid_min" ] && continue
        [ "$uid" -gt "$uid_max" ] && continue

        case "$shell" in
            */false|*/nologin) continue ;;
        esac

        id -nG "$user" 2>/dev/null | grep -qw sudo || continue

        if [ "$uid" -lt "$best_uid" ]; then
            best_uid="$uid"
            best_user="$user"
        fi
    done </etc/passwd

    [ -n "$best_user" ] || return 1
    echo "$best_user"
}

if ! local_user=$(detect_local_user); then
    log "ERROR: no valid local user found -- abort"
    exit 1
fi
echo "Using local user: $local_user"

# Report directory (owned by user)
report_dir="/home/${local_user}/Report"
mkdir -p "$report_dir"
chown "$local_user:$local_user" "$report_dir"
chmod 0755 "$report_dir"

# Private temp directory -- isolated from /tmp symlink attacks
SCRIPT_TMPDIR=$(mktemp -d)
trap 'rm -rf "$SCRIPT_TMPDIR"' EXIT

# DEPENDENCIES
for dep in nmap xsltproc iproute2 util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: dependency '$dep' is not installed -- abort"
        exit 1
    fi
done

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
    <h1> Nmap Scan Report</h1>
    <div class="info">
      <div>Command: <xsl:value-of select="nmaprun/@args"/></div>
      <div>Scan started: <xsl:value-of select="nmaprun/@startstr"/></div>
      <div>Nmap version: <xsl:value-of select="nmaprun/@version"/></div>
    </div>
  </div>

  <!-- Summary -->
  <div class="summary">
    <h2> Scan Summary</h2>
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
                <h3> Open Ports (<xsl:value-of select="count(ports/port[state[@state='open']])"/>)</h3>
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
                <h3> Host Scripts</h3>
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
    local exit_code
    printf "[-] Working..."
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r[-] Working... %s" "${spin:$i:1}"
        sleep 0.2
    done
    if wait "$pid"; then
        exit_code=0
    else
        exit_code=$?
    fi
    printf "\r[-] Done. \n"
    if [ "$exit_code" -ne 0 ]; then
        log "WARNING: nmap (PID $pid) exited with code $exit_code"
    fi
    return 0
}

# convert XML -> HTML with improved error handling
xml_to_html() {
    local xml="$1"
    local html="$2"
    local xsl="$SCRIPT_TMPDIR/netreport-custom.xsl"
    local xsl_error="$SCRIPT_TMPDIR/xsltproc_error.log"
    local default_xsl="/usr/share/nmap/nmap.xsl"

    log "INFO: Converting XML to HTML: $xml -> $html"

    # Verify XML file exists and is not empty
    if [ ! -f "$xml" ]; then
        log "WARNING: XML file does not exist: $xml"
        return 1
    fi

    if [ ! -s "$xml" ]; then
        log "WARNING: XML file is empty: $xml"
        return 1
    fi

    # Create custom XSL if not present
    if [ ! -f "$xsl" ]; then
        log "INFO: Creating custom XSL stylesheet..."
        create_custom_xsl "$xsl"
    fi

    # Try conversion with custom XSL
    log "INFO: Converting with custom XSL..."
    if xsltproc -o "$html" "$xsl" "$xml" 2>"$xsl_error"; then
        log "INFO: Conversion successful"
        rm -f "$xsl_error"
        return 0
    else
        log "WARNING: Custom XSL conversion failed:"
        head -5 "$xsl_error" | while read -r line; do log "WARNING: $line"; done
    fi

    # Fallback: try default nmap XSL
    if [ -f "$default_xsl" ]; then
        log "INFO: Attempting conversion with default nmap XSL..."
        if xsltproc -o "$html" "$default_xsl" "$xml" 2>"$xsl_error"; then
            log "INFO: Conversion successful with default XSL"
            rm -f "$xsl_error"
            return 0
        else
            log "WARNING: Default XSL conversion failed:"
            head -5 "$xsl_error" | while read -r line; do log "WARNING: $line"; done
        fi
    else
        log "WARNING: default nmap XSL not found -- fallback"
    fi

    # Last resort: create basic HTML wrapper
    log "WARNING: all XSL conversions failed -- fallback"
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
    log "INFO: Cleaning intermediate files: ${base}.*"
    rm -f "${base}.xml" "${base}.nmap" "${base}.gnmap" 2>/dev/null || true
}

# Verify and finalize HTML report
finalize_html_report() {
    local html_file="$1"

    if [ ! -f "$html_file" ]; then
        log "ERROR: HTML report was not created: $html_file"
        exit 1
    fi

    if [ ! -s "$html_file" ]; then
        log "ERROR: HTML report is empty: $html_file"
        exit 1
    fi

    # Set proper ownership and permissions
    chown "$local_user:$local_user" "$html_file" 2>/dev/null || true
    chmod 0644 "$html_file"

    local file_size=$(du -h "$html_file" | cut -f1)
    log "INFO: Report saved: $html_file (size: $file_size)"
    echo ""
    echo "----------------------------------------"
    echo "Report: $html_file"
    echo "Size: $file_size"
    echo "----------------------------------------"
    echo ""
}

# Prompt for a valid network interface and derive its network CIDR
select_interface() {
    SEL_IFACE=""
    SEL_NET=""
    echo "Available network interfaces:"
    local iface_list
    iface_list=$(ip -4 addr show scope global | awk '/inet /{ip=$2} /inet /{iface=$NF; printf " %-12s %s\n", iface, ip}')
    if [ -z "$iface_list" ]; then
        log "ERROR: no interface with a global IPv4 address -- abort"
        exit 1
    fi
    echo "$iface_list"
    echo ""
    DEFAULT_IFACE=$(printf '%s\n' "$iface_list" | awk 'NR==1{print $1}')
    while true; do
                read -rp "Select interface (default: ${DEFAULT_IFACE}): " SEL_IFACE
                SEL_IFACE="${SEL_IFACE:-$DEFAULT_IFACE}"
                SEL_IFACE="${SEL_IFACE#"${SEL_IFACE%%[![:space:]]*}"}"
                SEL_IFACE="${SEL_IFACE%"${SEL_IFACE##*[![:space:]]}"}"
                [ -n "$SEL_IFACE" ] || { log "WARNING: no interface specified -- retry"; continue; }
                if ! ip link show "$SEL_IFACE" &>/dev/null; then
                        log "WARNING: Interface '$SEL_IFACE' does not exist. Try again."
                        continue
                fi
                SEL_NET=$(ip -4 addr show dev "$SEL_IFACE" scope global | sed -n 's/.*inet \([0-9.]\{1,\}\/[0-9]\{1,\}\).*/\1/p' | head -n1)
                if [ -z "$SEL_NET" ]; then
                        log "WARNING: No IPv4 address found on '$SEL_IFACE'. Try again."
                        continue
                fi
                break
        done
}

log "netreport start..."

# MENU
TS=$(timestamp)
echo ""
echo "----------------------------------------"
echo "Net Report - Network Scanner"
echo "----------------------------------------"
echo ""
echo "1) LAN Scan"
echo "2) Advanced LAN Scan"
echo "3) IP/Host Scan"
echo "4) Exit"
echo ""
while true; do
    read -rp "Select [1-4] (default: 4): " opt
    opt="${opt:-4}"
    [[ "$opt" =~ ^[1-4]$ ]] && break
    log "WARNING: invalid option '$opt' -- retry"
done
echo ""

case "$opt" in
    1)
        # Option 1: LAN Scan => scan_TIMESTAMP.html
        log "INFO: === Option 1: LAN Scan ==="
        select_interface
        iface="$SEL_IFACE"
        net="$SEL_NET"
        log "INFO: Using network: $net on $iface"
        xml_file="${report_dir}/scan_${TS}.xml"
        html_file="${report_dir}/scan_${TS}.html"

        log "INFO: Starting LAN Scan on $net"

        # Run nmap in background
        nmap -sS -T4 -F -sV "$net" -oX "$xml_file" > "$SCRIPT_TMPDIR/nmap_out" 2>&1 &
        pid=$!
        show_spinner_for_pid "$pid"

        # Convert and finalize
        xml_to_html "$xml_file" "$html_file" || { log "ERROR: Failed to convert XML to HTML"; exit 1; }
        finalize_html_report "$html_file"
        cleanup_intermediate_files "${report_dir}/scan_${TS}"
        ;;

    2)
        # Option 2: Advanced LAN Scan => scan_deep_TIMESTAMP.html
        log "INFO: === Option 2: Advanced LAN Scan ==="
        select_interface
        iface="$SEL_IFACE"
        net="$SEL_NET"
        log "INFO: Using network: $net on $iface"
        xml_file="${report_dir}/scan_deep_${TS}.xml"
        html_file="${report_dir}/scan_deep_${TS}.html"

        log "INFO: Starting Advanced LAN Scan on $net"
        log "INFO: This may take several minutes..."

        # Run nmap in background
        nmap -sS -T4 -p- -sV -sC --max-retries 3 --host-timeout 5m "$net" -oX "$xml_file" > "$SCRIPT_TMPDIR/nmap_out" 2>&1 &
        pid=$!
        show_spinner_for_pid "$pid"

        # Convert and finalize
        xml_to_html "$xml_file" "$html_file" || { log "ERROR: Failed to convert XML to HTML"; exit 1; }
        finalize_html_report "$html_file"
        cleanup_intermediate_files "${report_dir}/scan_deep_${TS}"
        ;;

    3)
        # Option 3: IP/Host Scan => scan_ip_TIMESTAMP.html
        log "INFO: === Option 3: IP/Host Scan ==="
        select_interface
        iface="$SEL_IFACE"
        net="$SEL_NET"
        log "INFO: Discovering active hosts on $net ..."
        echo ""
        nmap -sn "$net" 2>/dev/null | awk '/report for/{ip=$5} /MAC/{printf " %-18s %s %s %s\n", ip, $3, $4, $5}' | sort -t. -k4 -n
        echo ""
        while true; do
            read -rp "Target IP or hostname: " target
            target="${target#"${target%%[![:space:]]*}"}"
            target="${target%"${target##*[![:space:]]}"}"
            [ -n "$target" ] && break
            log "WARNING: No target specified. Try again."
        done

        # Validate target format (IPv4 or FQDN)
        if ! [[ "$target" =~ $_UH_IPV4 ]] && ! [[ "$target" =~ $_UH_FQDN ]]; then
            log "ERROR: Invalid target format: $target"
            exit 1
        fi

        base="${report_dir}/scan_ip_${TS}"
        xml_file="${base}.xml"
        html_file="${report_dir}/scan_ip_${TS}.html"

        log "INFO: Starting IP/Host Scan on: $target"
        log "INFO: all ports, with vulnerability detection"
        log "INFO: May take 20-30 minutes..."

        # Full scan: all 65535 ports, OS detection, version intensity, vuln scripts and traceroute
        nmap -Pn -sS -T4 -p- -sV --version-intensity 8 -sC -O \
             --script vuln --traceroute \
             -oA "$base" \
             --max-retries 3 --host-timeout 10m \
             "$target" > "$SCRIPT_TMPDIR/nmap_out" 2>&1 &
        pid=$!
        show_spinner_for_pid "$pid"

        # Verify XML was created
        if [ ! -f "$xml_file" ]; then
            log "WARNING: XML file not found: $xml_file"

            # Check if .nmap file exists as fallback
            if [ -f "${base}.nmap" ]; then
                log "WARNING: Found .nmap file, converting to HTML..."
                target_html=$(printf '%s' "$target" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                {
                    echo '<!DOCTYPE html>'
                    echo '<html><head><meta charset="UTF-8">'
                    echo '<title>Nmap Scan Report - '"$target_html"'</title>'
                    echo '<style>body{font-family:monospace;padding:20px;background:#f5f5f5}pre{background:#fff;padding:15px;border:1px solid #ddd;overflow:auto;line-height:1.4}</style>'
                    echo '</head><body><h1>Nmap Scan Report: '"$target_html"'</h1>'
                    echo '<p><strong>Note:</strong> XML output not available, displaying text format.</p><pre>'
                    cat "${base}.nmap"
                    echo '</pre></body></html>'
                } > "$html_file"

                finalize_html_report "$html_file"
                cleanup_intermediate_files "$base"
                log "netreport done at: $(date)"
                exit 0
            else
                cp -f "$SCRIPT_TMPDIR/nmap_out" "${base}_nmap_out.log" 2>/dev/null || true
                log "ERROR: no nmap output found -- abort"
                exit 1
            fi
        fi

        # Verify XML is not empty
        if [ ! -s "$xml_file" ]; then
            log "ERROR: XML file is empty: $xml_file"
            exit 1
        fi

        log "XML file created successfully ($(du -h "$xml_file" | cut -f1))"

        # Convert to HTML
        if ! xml_to_html "$xml_file" "$html_file"; then
            log "ERROR: Failed to convert XML to HTML"
            exit 1
        fi

        # Finalize and cleanup
        finalize_html_report "$html_file"
        cleanup_intermediate_files "$base"
        ;;

    4)
        log "INFO: exit requested"
        echo "Goodbye!"
        log "netreport done at: $(date)"
        exit 0
        ;;
esac

log "netreport done at: $(date)"
echo ""
