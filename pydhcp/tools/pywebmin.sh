#!/bin/bash
# maravento.com
#
################################################################################
#
# PyDHCP module installation/uninstallation script for Webmin
#
# Description:
#   Installs or uninstalls the PyDHCP module for Webmin.
#   Provides a web interface to manage the pydhcpd daemon:
#   service control, active leases table, and configuration editor.
#
# Usage:
#   sudo ./pywebmin.sh [OPTIONS]
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

MODNAME="pydhcp"
MODDIR="/usr/share/webmin/$MODNAME"
ETCDIR="/etc/webmin/$MODNAME"

install_module() {
    echo ""
    echo "=========================================="
    echo "Installing PyDHCP Webmin Module"
    echo "=========================================="
    echo ""

    echo "Creating PyDHCP module structure..."
    mkdir -p "$MODDIR/images"
    mkdir -p "$MODDIR/lang"
    mkdir -p "$MODDIR/help"
    mkdir -p "$ETCDIR"

    # ── module.info ────────────────────────────────────────────────────────────
    cat > "$MODDIR/module.info" <<'EOF'
desc=PyDHCP Server
longdesc=Manage the pydhcpd DHCP server daemon
category=servers
os_support=*-linux
version=1.0
depends=webmin
EOF

    cat > "$MODDIR/module.info.es" <<'EOF'
desc=Servidor PyDHCP
longdesc=Administra el demonio DHCP pydhcpd
category=servers
os_support=*-linux
version=1.0
depends=webmin
EOF

    # ── lang/en ────────────────────────────────────────────────────────────────
    cat > "$MODDIR/lang/en" <<'EOF'
index_title=PyDHCP Server
index_status=Service Status
index_leases=Active Leases
index_config=Configuration
index_no_leases=No active leases found.
index_not_installed=pydhcpd is not installed. Run install.sh first.
btn_start=Start
btn_stop=Stop
btn_restart=Restart
btn_reload=Reload
btn_save=Save Configuration
btn_refresh=Refresh
table_ip=IP Address
table_mac=MAC Address
table_hostname=Hostname
table_expires=Expires
table_binding=State
status_active=Active
status_inactive=Inactive
status_unknown=Unknown
config_title=Edit pydhcpd.conf
config_saved=Configuration saved. Reload the daemon to apply changes.
config_error=Error saving configuration.
EOF

    # ── lang/es ────────────────────────────────────────────────────────────────
    cat > "$MODDIR/lang/es" <<'EOF'
index_title=Servidor PyDHCP
index_status=Estado del Servicio
index_leases=Concesiones Activas
index_config=Configuración
index_no_leases=No se encontraron concesiones activas.
index_not_installed=pydhcpd no está instalado. Ejecute install.sh primero.
btn_start=Iniciar
btn_stop=Detener
btn_restart=Reiniciar
btn_reload=Recargar
btn_save=Guardar Configuración
btn_refresh=Actualizar
table_ip=Dirección IP
table_mac=Dirección MAC
table_hostname=Nombre de host
table_expires=Expira
table_binding=Estado
status_active=Activo
status_inactive=Inactivo
status_unknown=Desconocido
config_title=Editar pydhcpd.conf
config_saved=Configuración guardada. Recargue el demonio para aplicar los cambios.
config_error=Error al guardar la configuración.
EOF

    # ── index.cgi ──────────────────────────────────────────────────────────────
    cat > "$MODDIR/index.cgi" <<'INDEXCGI'
#!/usr/bin/perl
use strict;
use warnings;

do '../web-lib.pl';
do '../ui-lib.pl';
&init_config();
&ReadParse();

our ($module_name, %text, %in);
&load_language($module_name);

my $DAEMON_BIN  = "/etc/pydhcp/pydhcpd.py";
my $LEASES_FILE = "/etc/pydhcp/pydhcpd.leases";
my $CONF_FILE   = "/etc/pydhcp/pydhcpd.conf";
my $SERVICE     = "pydhcpd";

# ── Actions ────────────────────────────────────────────────────────────────────
if ($in{'action'}) {
    my $act = $in{'action'};
    if ($act eq 'start')   { system("systemctl start   $SERVICE 2>&1"); }
    elsif ($act eq 'stop')    { system("systemctl stop    $SERVICE 2>&1"); }
    elsif ($act eq 'restart') { system("systemctl restart $SERVICE 2>&1"); }
    elsif ($act eq 'reload')  { system("systemctl reload  $SERVICE 2>&1"); }
    sleep 1;
    my $ts = time();
    &redirect("index.cgi?nocache=$ts");
}

print "Cache-Control: no-cache, no-store, must-revalidate\r\n";
print "Pragma: no-cache\r\n";
print "Expires: Thu, 01 Jan 1970 00:00:00 GMT\r\n";

&ui_print_header(undef, $text{'index_title'}, "", undef, 1, 1);

# ── CSS ────────────────────────────────────────────────────────────────────────
print <<'EOCSS';
<style>
.pyd-section {
    margin: 20px 0;
    background: #fff;
    border: 1px solid #dee2e6;
    border-radius: 6px;
    overflow: hidden;
    box-shadow: 0 1px 3px rgba(0,0,0,0.08);
}
.pyd-section-title {
    background: linear-gradient(to bottom, #f8f9fa, #e9ecef);
    padding: 10px 16px;
    font-weight: 600;
    font-size: 14px;
    border-bottom: 1px solid #dee2e6;
    color: inherit;
}
.pyd-status-bar {
    display: flex;
    align-items: center;
    gap: 20px;
    padding: 14px 16px;
    flex-wrap: wrap;
}
.pyd-badge {
    display: inline-block;
    padding: 4px 14px;
    border-radius: 12px;
    font-size: 13px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.4px;
}
.pyd-active   { background:#d4edda; color:#155724; border:1px solid #c3e6cb; }
.pyd-inactive { background:#f8d7da; color:#721c24; border:1px solid #f5c6cb; }
.pyd-unknown  { background:#e2e3e5; color:#383d41; border:1px solid #d6d8db; }
.pyd-btn {
    padding: 6px 16px;
    border-radius: 4px;
    border: 1px solid transparent;
    cursor: pointer;
    font-size: 13px;
    font-weight: 500;
    transition: all 0.15s;
    text-decoration: none;
    display: inline-block;
}
.pyd-btn-start   { background:#28a745; color:#fff; border-color:#28a745; }
.pyd-btn-start:hover  { background:#218838; }
.pyd-btn-stop    { background:#dc3545; color:#fff; border-color:#dc3545; }
.pyd-btn-stop:hover   { background:#c82333; }
.pyd-btn-restart { background:#ffc107; color:#212529; border-color:#ffc107; }
.pyd-btn-restart:hover { background:#e0a800; }
.pyd-btn-reload  { background:#17a2b8; color:#fff; border-color:#17a2b8; }
.pyd-btn-reload:hover  { background:#138496; }
.pyd-btn-refresh { background:#6c757d; color:#fff; border-color:#6c757d; }
.pyd-btn-refresh:hover { background:#5a6268; }
.pyd-table {
    width: 100%;
    border-collapse: collapse;
}
.pyd-table th {
    background: #f8f9fa;
    padding: 10px 14px;
    text-align: left;
    font-weight: 600;
    font-size: 13px;
    border-bottom: 2px solid #dee2e6;
    color: inherit;
}
.pyd-table td {
    padding: 9px 14px;
    border-bottom: 1px solid #f1f3f5;
    font-size: 13px;
    color: inherit;
}
.pyd-table tr:last-child td { border-bottom: none; }
.pyd-table tr:hover td { background: #f8f9fa; }
.pyd-empty {
    padding: 20px 16px;
    color: #6c757d;
    font-style: italic;
    font-size: 13px;
}
.pyd-link {
    display: inline-block;
    margin: 14px 16px;
    font-size: 13px;
    color: #007bff;
    text-decoration: none;
}
.pyd-link:hover { text-decoration: underline; }
.pyd-warning {
    padding: 14px 16px;
    background: #fff3cd;
    color: #856404;
    border-left: 4px solid #ffc107;
    font-size: 13px;
}
</style>
EOCSS

# ── Check installation ─────────────────────────────────────────────────────────
if (!-f $DAEMON_BIN) {
    print "<div class='pyd-section'><div class='pyd-warning'>$text{'index_not_installed'}</div></div>\n";
    &ui_print_footer("", "");
    exit 0;
}

# ── Service status ─────────────────────────────────────────────────────────────
my $status_raw = `systemctl is-active $SERVICE 2>/dev/null`;
chomp $status_raw;
my ($status_label, $status_class);
if ($status_raw eq 'active') {
    $status_label = $text{'status_active'};
    $status_class = 'pyd-active';
} elsif ($status_raw eq 'inactive' || $status_raw eq 'failed') {
    $status_label = $text{'status_inactive'};
    $status_class = 'pyd-inactive';
} else {
    $status_label = $text{'status_unknown'};
    $status_class = 'pyd-unknown';
}

print "<div class='pyd-section'>\n";
print "<div class='pyd-section-title'>$text{'index_status'}</div>\n";
print "<div class='pyd-status-bar'>\n";
print "<span class='pyd-badge $status_class'>$status_label</span>\n";
print "<a class='pyd-btn pyd-btn-start'   href='index.cgi?action=start'>$text{'btn_start'}</a>\n";
print "<a class='pyd-btn pyd-btn-stop'    href='index.cgi?action=stop'>$text{'btn_stop'}</a>\n";
print "<a class='pyd-btn pyd-btn-restart' href='index.cgi?action=restart'>$text{'btn_restart'}</a>\n";
print "<a class='pyd-btn pyd-btn-reload'  href='index.cgi?action=reload'>$text{'btn_reload'}</a>\n";
print "<a class='pyd-btn pyd-btn-refresh' href='index.cgi'>$text{'btn_refresh'}</a>\n";
print "</div></div>\n";

# ── Active leases ──────────────────────────────────────────────────────────────
print "<div class='pyd-section'>\n";
print "<div class='pyd-section-title'>$text{'index_leases'}</div>\n";

my @leases = parse_leases($LEASES_FILE);
if (@leases) {
    print "<table class='pyd-table'>\n";
    print "<tr><th>$text{'table_ip'}</th><th>$text{'table_mac'}</th>";
    print "<th>$text{'table_hostname'}</th><th>$text{'table_expires'}</th>";
    print "<th>$text{'table_binding'}</th></tr>\n";
    for my $l (@leases) {
        print "<tr>";
        print "<td>$l->{ip}</td>";
        print "<td>$l->{mac}</td>";
        print "<td>" . ($l->{hostname} || '<span style="color:#aaa">—</span>') . "</td>";
        print "<td>$l->{ends}</td>";
        print "<td>$l->{binding}</td>";
        print "</tr>\n";
    }
    print "</table>\n";
} else {
    print "<div class='pyd-empty'>$text{'index_no_leases'}</div>\n";
}

print "</div>\n";

# ── Link to config editor ──────────────────────────────────────────────────────
print "<a class='pyd-link' href='config.cgi'>&#9881; $text{'index_config'}</a>\n";

&ui_print_footer("", "");

# ── Lease parser ───────────────────────────────────────────────────────────────
sub parse_leases {
    my ($file) = @_;
    my @result;
    return @result unless -f $file;
    open(my $fh, '<', $file) or return @result;
    my $raw = do { local $/; <$fh> };
    close($fh);

    while ($raw =~ /lease\s+([\d.]+)\s*\{(.*?)\}/gs) {
        my ($ip, $body) = ($1, $2);
        my ($mac)      = $body =~ /hardware\s+ethernet\s+([\da-f:]+)\s*;/i;
        my ($hostname) = $body =~ /client-hostname\s+"([^"]+)"\s*;/;
        my ($ends)     = $body =~ /ends\s+\d+\s+([\d\/]+\s[\d:]+)\s*;/;
        my ($binding)  = $body =~ /binding\s+state\s+(\w+)\s*;/;
        next unless $mac && $ends;
        push @result, {
            ip       => $ip,
            mac      => lc($mac),
            hostname => $hostname || '',
            ends     => $ends,
            binding  => $binding || 'active',
        };
    }
    return sort { $a->{ip} cmp $b->{ip} } @result;
}
INDEXCGI

    # ── config.cgi ────────────────────────────────────────────────────────────
    cat > "$MODDIR/config.cgi" <<'CONFIGCGI'
#!/usr/bin/perl
use strict;
use warnings;

do '../web-lib.pl';
do '../ui-lib.pl';
&init_config();
&ReadParse();

our ($module_name, %text, %in);
&load_language($module_name);

my $CONF_FILE = "/etc/pydhcp/pydhcpd.conf";

print "Cache-Control: no-cache\r\n";
&ui_print_header(undef, $text{'config_title'}, "", undef, 1, 1);

my $message = "";

# Save action
if ($in{'action'} eq 'save' && defined $in{'conf_content'}) {
    my $content = $in{'conf_content'};
    $content =~ s/\r\n/\n/g;
    if (open(my $fh, '>', $CONF_FILE)) {
        print $fh $content;
        close($fh);
        $message = "<div style='margin:10px 0;padding:10px 14px;background:#d4edda;color:#155724;border-radius:4px;border:1px solid #c3e6cb;font-size:13px;'>$text{'config_saved'}</div>\n";
    } else {
        $message = "<div style='margin:10px 0;padding:10px 14px;background:#f8d7da;color:#721c24;border-radius:4px;border:1px solid #f5c6cb;font-size:13px;'>$text{'config_error'}: $!</div>\n";
    }
}

# Read current config
my $conf_content = "";
if (-f $CONF_FILE) {
    open(my $fh, '<', $CONF_FILE) or die "Cannot open $CONF_FILE: $!";
    $conf_content = do { local $/; <$fh> };
    close($fh);
}

# Escape for HTML
(my $escaped = $conf_content) =~ s/&/&amp;/g;
$escaped =~ s/</&lt;/g;
$escaped =~ s/>/&gt;/g;

print $message;
print <<EOFORM;
<form method="post" action="config.cgi">
<input type="hidden" name="action" value="save">
<textarea name="conf_content"
    style="width:100%;height:520px;font-family:monospace;font-size:13px;
           padding:10px;border:1px solid #ced4da;border-radius:4px;
           background:#fdfdfd;color:inherit;resize:vertical;">$escaped</textarea>
<br>
<input type="submit" value="$text{'btn_save'}"
    style="margin-top:10px;padding:8px 22px;background:#28a745;color:#fff;
           border:none;border-radius:4px;cursor:pointer;font-size:14px;font-weight:500;">
&nbsp;
<a href="index.cgi"
    style="padding:8px 18px;background:#6c757d;color:#fff;border-radius:4px;
           text-decoration:none;font-size:14px;font-weight:500;">&#8592; Back</a>
</form>
EOFORM

&ui_print_footer("index.cgi", $text{'index_title'});
CONFIGCGI

    # ── help/intro.en.html ────────────────────────────────────────────────────
    cat > "$MODDIR/help/intro.en.html" <<'EOF'
<header>PyDHCP Server</header>

<h3>Introduction</h3>
<p>The PyDHCP module lets you manage the pydhcpd daemon from Webmin.
It provides service control, a live view of active DHCP leases, and a built-in editor for the daemon configuration file.</p>

<h3>Service Control</h3>
<p><b>Start / Stop / Restart:</b> Control the pydhcpd systemd service.</p>
<p><b>Reload:</b> Sends SIGHUP to pydhcpd, reloading the configuration without dropping active leases.</p>

<h3>Active Leases</h3>
<p>Shows all entries currently in <code>/etc/pydhcp/pydhcpd.leases</code>: IP address, MAC address, hostname (if reported by the client), expiry time, and binding state.</p>

<h3>Configuration</h3>
<p>Opens <code>/etc/pydhcp/pydhcpd.conf</code> for editing directly in the browser. After saving, click Reload to apply changes without restarting the daemon.</p>

<footer>
EOF

    # ── help/intro.es.html ────────────────────────────────────────────────────
    cat > "$MODDIR/help/intro.es.html" <<'EOF'
<header>Servidor PyDHCP</header>

<h3>Introducción</h3>
<p>El módulo PyDHCP permite administrar el demonio pydhcpd desde Webmin.
Ofrece control del servicio, una vista en tiempo real de las concesiones DHCP activas y un editor integrado para el archivo de configuración del demonio.</p>

<h3>Control del Servicio</h3>
<p><b>Iniciar / Detener / Reiniciar:</b> Controla el servicio systemd pydhcpd.</p>
<p><b>Recargar:</b> Envía SIGHUP a pydhcpd, recargando la configuración sin interrumpir las concesiones activas.</p>

<h3>Concesiones Activas</h3>
<p>Muestra todas las entradas actuales en <code>/etc/pydhcp/pydhcpd.leases</code>: dirección IP, dirección MAC, nombre de host (si lo reporta el cliente), hora de expiración y estado de la concesión.</p>

<h3>Configuración</h3>
<p>Abre <code>/etc/pydhcp/pydhcpd.conf</code> para edición directamente en el navegador. Después de guardar, haga clic en Recargar para aplicar los cambios sin reiniciar el demonio.</p>

<footer>
EOF

    # ── CHANGELOG ─────────────────────────────────────────────────────────────
    cat > "$MODDIR/CHANGELOG" <<'EOF'
Version 1.0 (2025)
- Initial release
- Service control: start, stop, restart, reload (SIGHUP)
- Active leases table from /etc/pydhcp/pydhcpd.leases
- Built-in editor for /etc/pydhcp/pydhcpd.conf
- Multi-language support (English and Spanish)
- Detects pydhcpd installation status
EOF

    # ── icon (reuse servicemon base64 gif, neutral gear icon) ────────────────
    cat > /tmp/pydhcp_icon.gif.b64 <<'ICONEOF'
R0lGODlhMAAwAPAAAAAAAAAAACH5BAEAAAAALAAAAAAwADAAAAKrhI+py+0Po5wqJEszCpyf7mkUiAGkOJJqiUKr2krvGS/zDdYGzusmj6vdLjPfynb0/XIVmnLZQTKfsOZU95I6W8NNUQj8yq5hcWRbzk62xOA5BIX/Pj0XML6rP9JuvJ3v4cTGAChncpFR+JSXtshIlgSm5mWWWPlYJdLVFqmxSdlpOQmayRU6isXnGHfnqEhVyBITazgbuxiFWXKlxFJ6uGpVGywsS3yMHFMAADs=
ICONEOF
    base64 -d /tmp/pydhcp_icon.gif.b64 > "$MODDIR/images/icon.gif" 2>/dev/null || true
    rm -f /tmp/pydhcp_icon.gif.b64

    # ── Permissions ───────────────────────────────────────────────────────────
    chown -R root:root "$MODDIR" "$ETCDIR"
    chmod -R 755 "$MODDIR"
    chmod 644 "$MODDIR"/module.info* "$MODDIR/lang/"* "$MODDIR/help/"* "$MODDIR/CHANGELOG" 2>/dev/null || true
    chmod 755 "$MODDIR"/*.cgi 2>/dev/null || true
    chmod 644 "$MODDIR/images/"* 2>/dev/null || true

    # ── Register in webmin.acl ────────────────────────────────────────────────
    if [ -f /etc/webmin/webmin.acl ]; then
        if ! grep -q "$MODNAME" /etc/webmin/webmin.acl 2>/dev/null; then
            sed -i.bak "s/\(^root:.*\)/\1 $MODNAME/" /etc/webmin/webmin.acl
            rm -f /etc/webmin/webmin.acl.bak
            echo "✓ Module added to webmin.acl"
        fi
    else
        echo "⚠ Warning: /etc/webmin/webmin.acl not found, skipping ACL update"
    fi

    rm -f /var/webmin/module.infos.cache

    echo "Restarting Webmin service..."
    systemctl restart webmin.service 2>/dev/null || /etc/webmin/restart 2>/dev/null || true

    echo ""
    echo "=========================================="
    echo "PyDHCP module installed successfully!"
    echo "=========================================="
    echo ""
    echo "Module location : $MODDIR"
    echo "Config location : $ETCDIR"
    echo ""
    echo "Please log out and log back into Webmin to see the new module."
    echo "You can find it under the 'Servers' category."
    echo "https://localhost:10000/pydhcp/"
    echo ""
}

uninstall_module() {
    echo ""
    echo "=========================================="
    echo "Uninstalling PyDHCP Webmin Module"
    echo "=========================================="
    echo ""

    if [ ! -d "$MODDIR" ]; then
        echo "⚠  Module is not installed."
        echo ""
        return 1
    fi

    echo "Removing module directories..."
    rm -rf "$MODDIR"
    rm -rf "$ETCDIR"
    echo "✓ Module directories removed"

    if [ -f /etc/webmin/webmin.acl ]; then
        if grep -q "$MODNAME" /etc/webmin/webmin.acl 2>/dev/null; then
            sed -i.bak "s/ $MODNAME//g" /etc/webmin/webmin.acl
            rm -f /etc/webmin/webmin.acl.bak
            echo "✓ Module removed from webmin.acl"
        fi
    else
        echo "⚠ Warning: /etc/webmin/webmin.acl not found, skipping ACL update"
    fi

    rm -f /var/webmin/module.infos.cache
    echo "✓ Module cache cleared"

    echo "Restarting Webmin service..."
    systemctl restart webmin.service 2>/dev/null || /etc/webmin/restart 2>/dev/null || true

    echo ""
    echo "=========================================="
    echo "PyDHCP module uninstalled successfully!"
    echo "=========================================="
    echo ""
}

show_menu() {
    clear
    echo "============================================================"
    echo "              PyDHCP - WEBMIN MODULE"
    echo "                 Installation Menu"
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
    echo "  install      Install the PyDHCP Webmin module"
    echo "  uninstall    Uninstall the PyDHCP Webmin module"
    echo "  -h, --help   Show this help message"
    echo ""
    echo "If no option is provided, interactive menu will be shown."
    echo ""
    echo "Examples:"
    echo "  $0 install"
    echo "  $0 uninstall"
    echo "  $0"
    echo ""
}

main() {
    if [ ! -d "/usr/share/webmin" ] && [ ! -d "/etc/webmin" ]; then
        echo "Error: Webmin is not installed on this system"
        exit 1
    fi

    if [ $# -gt 0 ]; then
        case "$1" in
            install)
                install_module
                exit 0
                ;;
            uninstall)
                uninstall_module
                exit 0
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "Error: Invalid option '$1'"
                echo ""
                show_usage
                exit 1
                ;;
        esac
    fi

    while true; do
        show_menu
        read -r option
        case $option in
            1)
                install_module
                echo ""
                read -p "Press Enter to continue..."
                ;;
            2)
                uninstall_module
                echo ""
                read -p "Press Enter to continue..."
                ;;
            3)
                echo ""
                echo "Exiting..."
                echo ""
                exit 0
                ;;
            *)
                echo ""
                echo "Invalid option. Please select 1, 2, or 3."
                echo ""
                sleep 2
                ;;
        esac
    done
}

main "$@"
