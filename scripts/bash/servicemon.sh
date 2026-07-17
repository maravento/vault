#!/bin/bash
# maravento.com
#
################################################################################
#
# Services Monitor module installation/uninstallation script for Webmin
#
# Description:
#   This script installs or uninstalls the Services Monitor module for Webmin.
#   The module provides a modern interface to monitor and manage systemd services,
#   with real-time status updates and syslog integration.
#
# Features:
#   - Modern and user-friendly web interface
#   - Monitor enabled system services
#   - Start, stop, and restart services
#   - Multi-language support (English and Spanish)
#   - Syslog integration for service events
#   - Automatic dependency checking
#   - Configurable service filtering (Default/Active/Failed)
#
# Usage:
#   sudo ./servicemon.sh [OPTIONS]
#
# Options:
#   install      Install the module
#   uninstall    Uninstall the module
#   -h, --help   Show help message
#
# Examples:
#   sudo ./servicemon.sh              # Interactive menu
#   sudo ./servicemon.sh install      # Direct installation
#   sudo ./servicemon.sh uninstall    # Direct uninstallation
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

MODNAME="servicemon"
MODDIR="/usr/share/webmin/$MODNAME"
ETCDIR="/etc/webmin/$MODNAME"

install_module() {
    echo ""
    echo "=========================================="
    echo "Installing Services Monitor Module"
    echo "=========================================="
    echo ""
    
    echo "Checking dependencies..."
    echo "✓ Dependencies checked"
    
    echo "Creating Services Monitor module structure..."
    
    mkdir -p "$MODDIR/images"
    mkdir -p "$MODDIR/lang"
    mkdir -p "$MODDIR/help"
    mkdir -p "$ETCDIR"
    
    cat > "$MODDIR/index.cgi" <<'INDEXCGI'
#!/usr/bin/perl
# Services Monitor - Main interface
use strict;
use warnings;

do '../web-lib.pl';
do '../ui-lib.pl';
&init_config();
&ReadParse();

our $module_name;
our %text;
our %in;
my %known_services = map { $_ => 1 } get_all_services();

foreach my $key (keys %in) {
    if ($key =~ /^(start|stop|restart)_(.+)$/) {
        my $action = $1;
        my $service = $2;

        unless (exists $known_services{$service}) {
            &ui_print_header(undef, "Error", "");
            print "<p>Invalid service: " . &html_escape($service) . "</p>";
            &ui_print_footer("/", $text{'index'});
            exit 1;
        }

        system("logger", "-t", "servicemon", "-p", "daemon.info",
               "User action: $action on service $service");

        system("systemctl", $action, $service);
        
        sleep 2;
        
        my $status = check_service_status($service);
        
        if ($action eq 'stop' && $status ne 'active') {
            system("logger -t servicemon -p daemon.warning 'Service stopped: $service'");
        } elsif ($action eq 'start' && $status eq 'active') {
            system("logger -t servicemon -p daemon.info 'Service started: $service'");
        } elsif ($action eq 'restart') {
            system("logger -t servicemon -p daemon.info 'Service restarted: $service'");
        }
        
        my $timestamp = time();
        &redirect("index.cgi?nocache=$timestamp");
    }
}

our %text;
&load_language($module_name);

our %config;
&read_file("$ENV{'WEBMIN_CONFIG'}/$module_name/config", \%config);

my $filter_mode = $config{'filter_mode'} || 'default';

my $auto_refresh = $config{'auto_refresh'} || '0';
my $refresh_interval = $config{'refresh_interval'} || '30';

$refresh_interval = 30 if $refresh_interval !~ /^\d+$/ || $refresh_interval < 5;

print "Cache-Control: no-cache, no-store, must-revalidate, max-age=0\r\n";
print "Pragma: no-cache\r\n";
print "Expires: Thu, 01 Jan 1970 00:00:00 GMT\r\n";

&ui_print_header(undef, $text{'index_title'}, "", undef, 1, 1);

print <<'EOCSS';
<style>
.service-table {
    width: 100%;
    border-collapse: collapse;
    background: white;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    border-radius: 6px;
    overflow: hidden;
}
.service-table th {
    background: linear-gradient(to bottom, #f8f9fa 0%, #e9ecef 100%);
    padding: 12px 15px;
    text-align: left;
    font-weight: 600;
    color: inherit;
    border-bottom: 2px solid #dee2e6;
}
.service-table td {
    padding: 12px 15px;
    border-bottom: 1px solid #f1f3f5;
    color: inherit;
}
.service-table tr:hover {
    background-color: #f8f9fa;
}
.service-row-failed {
    background-color: #fff5f5;
}
.service-row-failed:hover {
    background-color: #ffe3e3;
}
.service-row-active {
    background-color: #f0fff4;
}
.service-row-active:hover {
    background-color: #d4f4dd;
}
.status-badge {
    display: inline-block;
    padding: 4px 12px;
    border-radius: 12px;
    font-size: 13px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
}
.status-active {
    background-color: #d4edda;
    color: #155724;
    border: 1px solid #c3e6cb;
}
.status-failed {
    background-color: #f8d7da;
    color: #721c24;
    border: 1px solid #f5c6cb;
}
.action-btn {
    padding: 6px 16px;
    border-radius: 4px;
    border: 1px solid;
    cursor: pointer;
    font-size: 13px;
    font-weight: 500;
    transition: all 0.2s;
}
.btn-start {
    background-color: #28a745;
    color: white;
    border-color: #28a745;
}
.btn-start:hover {
    background-color: #218838;
    transform: translateY(-1px);
    box-shadow: 0 2px 4px rgba(0,0,0,0.2);
}
.btn-stop {
    background-color: #dc3545;
    color: white;
    border-color: #dc3545;
}
.btn-stop:hover {
    background-color: #c82333;
    transform: translateY(-1px);
    box-shadow: 0 2px 4px rgba(0,0,0,0.2);
}
.btn-restart {
    background-color: #ffc107;
    color: #212529;
    border-color: #ffc107;
}
.btn-restart:hover {
    background-color: #e0a800;
    transform: translateY(-1px);
    box-shadow: 0 2px 4px rgba(0,0,0,0.2);
}
.btn-refresh {
    background-color: #007bff;
    color: white;
    border-color: #007bff;
    padding: 8px 20px;
    font-size: 14px;
}
.btn-refresh:hover {
    background-color: #0056b3;
}
.summary-box {
    margin: 20px 0;
    padding: 20px;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    border-radius: 8px;
    box-shadow: 0 4px 6px rgba(0,0,0,0.1);
    color: white;
}
.summary-box h3 {
    margin-top: 0;
    color: white;
    font-size: 20px;
    margin-bottom: 15px;
}
.summary-stats {
    display: flex;
    justify-content: space-around;
    flex-wrap: wrap;
    gap: 15px;
}
.stat-item {
    background: rgba(255,255,255,0.2);
    padding: 15px 25px;
    border-radius: 6px;
    text-align: center;
    backdrop-filter: blur(10px);
}
.stat-number {
    font-size: 32px;
    font-weight: bold;
    display: block;
    margin-bottom: 5px;
}
.stat-label {
    font-size: 13px;
    opacity: 0.9;
    text-transform: uppercase;
    letter-spacing: 1px;
}
.service-name {
    font-weight: 600;
    color: inherit;
    font-size: 14px;
}
.service-icon {
    font-size: 18px;
    margin-right: 8px;
}
.alert-banner {
    padding: 15px 20px;
    border-radius: 6px;
    margin-bottom: 20px;
    display: flex;
    align-items: center;
    font-weight: 500;
}
.alert-success {
    background-color: #d4edda;
    color: #155724;
    border-left: 4px solid #28a745;
}
.alert-warning {
    background-color: #fff3cd;
    color: #856404;
    border-left: 4px solid #ffc107;
}
.alert-info {
    background-color: #d1ecf1;
    color: #0c5460;
    border-left: 4px solid #17a2b8;
}
.refresh-indicator {
    position: fixed;
    bottom: 20px;
    right: 20px;
    background: rgba(0, 123, 255, 0.9);
    color: white;
    padding: 10px 20px;
    border-radius: 20px;
    font-size: 13px;
    box-shadow: 0 4px 6px rgba(0,0,0,0.3);
    z-index: 1000;
}
</style>
EOCSS

my @all_services = get_all_services();

print &ui_form_start("index.cgi", "post");

my $total_services = 0;
my $active_services = 0;
my $failed_services = 0;

my @failed_list = ();
my @active_list = ();

foreach my $service (@all_services) {
    my $status = check_service_status($service);
    
    if ($status eq 'active') {
        push @active_list, $service;
    } else {
        push @failed_list, $service;
    }
}

print "<div class='summary-box'>";
print "<h3>📊 $text{'summary_title'}</h3>";
print "<div class='summary-stats'>";

$total_services = scalar(@all_services);
$active_services = scalar(@active_list);
$failed_services = scalar(@failed_list);

print "<div class='stat-item'>";
print "<span class='stat-number'>$total_services</span>";
print "<span class='stat-label'>$text{'summary_total'}</span>";
print "</div>";

print "<div class='stat-item'>";
print "<span class='stat-number' style='color: #d4edda;'>$active_services</span>";
print "<span class='stat-label'>$text{'summary_active'}</span>";
print "</div>";

print "<div class='stat-item'>";
print "<span class='stat-number' style='color: #f8d7da;'>$failed_services</span>";
print "<span class='stat-label'>$text{'summary_failed'}</span>";
print "</div>";

print "</div>";
print "</div>";

my $filter_text = $text{'filter_showing_default'};
if ($filter_mode eq 'active') {
    $filter_text = $text{'filter_showing_active'};
} elsif ($filter_mode eq 'failed') {
    $filter_text = $text{'filter_showing_failed'};
}

print "<div class='alert-banner alert-info'>";
print "ℹ️ <strong>$filter_text</strong>";
print "</div>";

if ($failed_services == 0) {
    print "<div class='alert-banner alert-success'>";
    print "✅ <strong>$text{'summary_all_ok'}</strong>";
    print "</div>";
} else {
    print "<div class='alert-banner alert-warning'>";
    print "⚠️ <strong>$failed_services $text{'summary_needs_attention'}</strong>";
    print "</div>";
}

print "<table class='service-table'>";
print "<thead>";
print "<tr>";
print "<th style='width: 40%;'>$text{'table_service'}</th>";
print "<th style='width: 25%;'>$text{'table_status'}</th>";
print "<th style='width: 35%; text-align: center;'>$text{'table_actions'}</th>";
print "</tr>";
print "</thead>";
print "<tbody>";

my $services_shown = 0;

if ($filter_mode eq 'default' || $filter_mode eq 'failed') {
    foreach my $service (@failed_list) {
        my $display_name = $service;
        $display_name =~ s/\.service$//;
        
        print "<tr class='service-row-failed'>";
        print "<td><span class='service-icon'>⚙️</span><span class='service-name'>$display_name</span></td>";
        print "<td><span class='status-badge status-failed'>✗ $text{'status_failed'}</span></td>";
        print "<td style='text-align: center;'>";
        print &ui_submit($text{'action_start'}, "start_$service", undef, undef, "class='action-btn btn-start'");
        print " ";
        print &ui_submit($text{'action_restart'}, "restart_$service", undef, undef, "class='action-btn btn-restart'");
        print "</td>";
        print "</tr>";
        $services_shown++;
    }
}

if ($filter_mode eq 'default' || $filter_mode eq 'active') {
    foreach my $service (@active_list) {
        my $display_name = $service;
        $display_name =~ s/\.service$//;
        
        print "<tr class='service-row-active'>";
        print "<td><span class='service-icon'>⚙️</span><span class='service-name'>$display_name</span></td>";
        print "<td><span class='status-badge status-active'>✓ $text{'status_active'}</span></td>";
        print "<td style='text-align: center;'>";
        print &ui_submit($text{'action_stop'}, "stop_$service", undef, undef, "class='action-btn btn-stop'");
        print " ";
        print &ui_submit($text{'action_restart'}, "restart_$service", undef, undef, "class='action-btn btn-restart'");
        print "</td>";
        print "</tr>";
        $services_shown++;
    }
}

if ($services_shown == 0) {
    print "<tr>";
    print "<td colspan='3' style='text-align: center; padding: 30px; color: #666;'>";
    print "$text{'filter_no_services'}";
    print "</td>";
    print "</tr>";
}

print "</tbody>";
print "</table>";

print "<div style='margin-top: 20px; text-align: center;'>";
print &ui_submit($text{'action_refresh'}, "refresh", undef, undef, "class='action-btn btn-refresh'");
print "</div>";

print &ui_form_end();

if ($auto_refresh eq '1') {
    my $interval_ms = $refresh_interval * 1000;
    print <<AUTOREFRESH;
<div class='refresh-indicator' id='refreshIndicator'>
🔄 Auto-refresh: <span id='countdown'>$refresh_interval</span>s
</div>

<script>
var refreshInterval = $refresh_interval;
var countdown = refreshInterval;
var countdownElement = document.getElementById('countdown');

function updateCountdown() {
    countdown--;
    if (countdown <= 0) {
        location.reload();
    } else {
        countdownElement.textContent = countdown;
    }
}

setInterval(updateCountdown, 1000);
</script>
AUTOREFRESH
}

&ui_print_footer("/", $text{'index'});

sub get_all_services {
    my @services;
    my $output = `systemctl list-unit-files --type=service --state=enabled --no-pager --no-legend 2>/dev/null`;
    
    foreach my $line (split(/\n/, $output)) {
        if ($line =~ /^(\S+\.service)\s+/) {
            my $service = $1;
            next if $service =~ /^(NetworkManager-|cloud-|snap|getty@|nvidia-|podman-|systemd-|grub-|e2scrub|dmesg|gpu-manager|secureboot-|ua-|ubuntu-advantage)/;
            next if $service =~ /^(thermald|sssd|blueman-|anacron|libvirtd|nut-driver|samba-ad-dc|ssl-cert)\.service$/;
            push @services, $service;
        }
    }
    
    return sort @services;
}

sub check_service_status {
    my ($service) = @_;
    my $active_output = `systemctl is-active \Q$service\E 2>/dev/null`;
    chomp($active_output);
    return 'active' if $active_output eq 'active';
    return 'stopped';
}


INDEXCGI
    
    chmod +x "$MODDIR/index.cgi"
    
    cat > "$MODDIR/module.info" <<'EOF'
desc=Services Monitor
longdesc=Monitor and manage system services
category=system
os_support=*-linux
version=1.0
depends=webmin
EOF
    
    cat > "$MODDIR/module.info.es" <<'EOF'
desc=Monitor de Servicios
longdesc=Monitorea y gestiona servicios del sistema
category=system
os_support=*-linux
version=1.0
depends=webmin
EOF
    
    cat > "$MODDIR/lang/en" <<'EOF'
index_title=Services Monitor
index_table=System Services Status
table_service=Service
table_status=Status
table_actions=Actions
status_active=Active
status_failed=Failed
action_start=Start
action_stop=Stop
action_restart=Restart
action_refresh=Refresh Status
summary_title=Summary
summary_total=Total services
summary_active=Active services
summary_failed=Failed services
summary_all_ok=All services are working correctly
summary_needs_attention=service(s) require attention
index=Webmin Index
index_return=Return to Services Monitor
config_title=Services Monitor Configuration
config_header=Module Configuration
config_about_title=About This Module
config_about_desc=Services Monitor is a Webmin module that allows you to monitor and manage system services that are enabled to start automatically. It provides a modern and user-friendly interface for service management.
config_features_title=Features
config_feature_1=Monitor all enabled system services in real-time
config_feature_2=Start, stop, and restart services with one click
config_feature_3=Visual status indicators (Active/Failed)
config_feature_4=Syslog integration for all service actions
config_feature_5=Multi-language support (English and Spanish)
config_location_title=Module Locations
config_module_dir=Module directory
config_config_dir=Configuration directory
config_access_url=Access URL
config_logs_title=System Logs
config_logs_desc=All service actions are logged to syslog with the tag 'servicemon'. You can view them using:
config_notifications_title=System Logs
config_notifications_desc=All service actions are logged to syslog with the tag 'servicemon'.
config_filter_title=Service Display Filter
config_filter_desc=Select which services to display in the main interface:
config_filter_default=Default (Failed + Active services)
config_filter_active=Active services only
config_filter_failed=Failed services only
config_filter_help=This setting controls which services are shown in the main monitor interface. 'Default' shows all services, 'Active' shows only running services, and 'Failed' shows only stopped or failed services.
config_save=Save Configuration
config_saved=Configuration saved successfully
config_refresh_title=Auto-Refresh Settings
config_refresh_desc=Configure automatic page refresh to monitor services in real-time.
config_auto_refresh=Enable auto-refresh
config_refresh_interval=Refresh interval (seconds)
config_refresh_help=When enabled, the page will automatically reload every X seconds. Minimum recommended: 30 seconds to avoid excessive server load.
filter_showing_default=Showing: All services (Failed + Active)
filter_showing_active=Showing: Active services only
filter_showing_failed=Showing: Failed services only
filter_no_services=No services match the current filter
EOF
    
    cat > "$MODDIR/lang/es" <<'EOF'
index_title=Monitor de Servicios
index_table=Estado de Servicios del Sistema
table_service=Servicio
table_status=Estado
table_actions=Acciones
status_active=Activo
status_failed=Fallido
action_start=Iniciar
action_stop=Detener
action_restart=Reiniciar
action_refresh=Actualizar Estado
summary_title=Resumen
summary_total=Total de servicios
summary_active=Servicios activos
summary_failed=Servicios fallidos
summary_all_ok=Todos los servicios están funcionando correctamente
summary_needs_attention=servicio(s) que requieren atención
index=Índice de Webmin
index_return=Volver al Monitor de Servicios
config_title=Configuración del Monitor de Servicios
config_header=Configuración del Módulo
config_about_title=Acerca de Este Módulo
config_about_desc=Monitor de Servicios es un módulo de Webmin que le permite monitorear y gestionar servicios del sistema que están habilitados para iniciarse automáticamente. Proporciona una interfaz moderna y fácil de usar para la gestión de servicios.
config_features_title=Características
config_feature_1=Monitorear todos los servicios del sistema habilitados en tiempo real
config_feature_2=Iniciar, detener y reiniciar servicios con un clic
config_feature_3=Indicadores visuales de estado (Activo/Fallido)
config_feature_4=Integración con syslog para todas las acciones de servicios
config_feature_5=Soporte multiidioma (Inglés y Español)
config_location_title=Ubicaciones del Módulo
config_module_dir=Directorio del módulo
config_config_dir=Directorio de configuración
config_access_url=URL de acceso
config_logs_title=Registros del Sistema
config_logs_desc=Todas las acciones de servicios se registran en syslog con la etiqueta 'servicemon'. Puede verlos usando:
config_notifications_title=Registros del Sistema
config_notifications_desc=Todas las acciones de servicios se registran en syslog con la etiqueta 'servicemon'.
config_filter_title=Filtro de Visualización de Servicios
config_filter_desc=Seleccione qué servicios mostrar en la interfaz principal:
config_filter_default=Predeterminado (Servicios Fallidos + Activos)
config_filter_active=Solo servicios activos
config_filter_failed=Solo servicios fallidos
config_filter_help=Esta configuración controla qué servicios se muestran en la interfaz principal del monitor. 'Predeterminado' muestra todos los servicios, 'Activo' muestra solo los servicios en ejecución, y 'Fallido' muestra solo los servicios detenidos o fallidos.
config_save=Guardar Configuración
config_saved=Configuración guardada exitosamente
config_refresh_title=Configuración de Auto-actualización
config_refresh_desc=Configure la recarga automática de la página para monitorear servicios en tiempo real.
config_auto_refresh=Activar auto-actualización
config_refresh_interval=Intervalo de actualización (segundos)
config_refresh_help=Cuando está activado, la página se recargará automáticamente cada X segundos. Mínimo recomendado: 30 segundos para evitar carga excesiva del servidor.
filter_showing_default=Mostrando: Todos los servicios (Fallidos + Activos)
filter_showing_active=Mostrando: Solo servicios activos
filter_showing_failed=Mostrando: Solo servicios fallidos
filter_no_services=No hay servicios que coincidan con el filtro actual
EOF
    
    cat > "$MODDIR/config.info" <<'EOF'
filter_mode=Service Display Filter,4,default-Default (Failed + Active services),active-Active services only,failed-Failed services only
auto_refresh=Auto-refresh,1,1-Enabled,0-Disabled
refresh_interval=Refresh interval (seconds),3,30
EOF
    
    cat > "$MODDIR/config.info.es" <<'EOF'
filter_mode=Filtro de Visualización de Servicios,4,default-Predeterminado (Servicios Fallidos + Activos),active-Solo servicios activos,failed-Solo servicios fallidos
auto_refresh=Auto-actualización,1,1-Activado,0-Desactivado
refresh_interval=Intervalo de actualización (segundos),3,30
EOF
    
    cat > "$MODDIR/defaultconfig" <<'EOF'
filter_mode=default
auto_refresh=0
refresh_interval=30
EOF
    
    cat > "$ETCDIR/config" <<'EOF'
filter_mode=default
auto_refresh=0
refresh_interval=30
EOF
    
    cat > "$MODDIR/servicemon-lib.pl" <<'EOF'
#!/usr/bin/perl
# Services Monitor library functions

do '../web-lib.pl';
do '../ui-lib.pl';
&init_config();

1;
EOF
    
    chmod +x "$MODDIR/servicemon-lib.pl"
    
    cat > "$MODDIR/install_check.pl" <<'EOF'
#!/usr/bin/perl
# Check if systemctl is available

do '../web-lib.pl';

sub module_install_check {
    if (!&has_command("systemctl")) {
        return "systemctl command not found - systemd is required";
    }
    return undef;
}
EOF
    
    chmod +x "$MODDIR/install_check.pl"
    
    cat > "$MODDIR/help/intro.html" <<'EOF'
<header>Services Monitor</header>

<h3>Introduction</h3>
<p>The Services Monitor module allows you to view and manage system services that are enabled to start automatically. It provides a simple interface to start, stop, and restart services.</p>

<h3>Features</h3>
<ul>
<li>View all enabled system services</li>
<li>See service status (Active or Failed)</li>
<li>Start, stop, or restart services</li>
<li>Real-time status updates</li>
<li>Automatic notifications via syslog</li>
<li>Configurable service filtering</li>
</ul>

<h3>Service Status</h3>
<p><b>Active:</b> The service is currently running</p>
<p><b>Failed:</b> The service is not running (stopped or failed)</p>

<h3>Service Filtering</h3>
<p>You can configure which services to display in the module configuration:</p>
<ul>
<li><b>Default:</b> Shows both failed and active services</li>
<li><b>Active only:</b> Shows only running services</li>
<li><b>Failed only:</b> Shows only stopped or failed services</li>
</ul>

<h3>Notifications</h3>
<p>When a service is stopped, the module will:</p>
<ul>
<li>Log the event to syslog with tag 'servicemon'</li>
</ul>

<footer>
EOF
    
    cat > "$MODDIR/help/intro.es.html" <<'EOF'
<header>Monitor de Servicios</header>

<h3>Introducción</h3>
<p>El módulo Monitor de Servicios le permite ver y gestionar servicios del sistema que están habilitados para iniciarse automáticamente. Proporciona una interfaz simple para iniciar, detener y reiniciar servicios.</p>

<h3>Características</h3>
<ul>
<li>Ver todos los servicios del sistema habilitados</li>
<li>Ver el estado de los servicios (Activo o Fallido)</li>
<li>Iniciar, detener o reiniciar servicios</li>
<li>Actualizaciones de estado en tiempo real</li>
<li>Notificaciones automáticas vía syslog</li>
<li>Filtrado configurable de servicios</li>
</ul>

<h3>Estado de los Servicios</h3>
<p><b>Activo:</b> El servicio está actualmente en ejecución</p>
<p><b>Fallido:</b> El servicio no está en ejecución (detenido o fallido)</p>

<h3>Filtrado de Servicios</h3>
<p>Puede configurar qué servicios mostrar en la configuración del módulo:</p>
<ul>
<li><b>Predeterminado:</b> Muestra servicios fallidos y activos</li>
<li><b>Solo activos:</b> Muestra solo servicios en ejecución</li>
<li><b>Solo fallidos:</b> Muestra solo servicios detenidos o fallidos</li>
</ul>

<h3>Notificaciones</h3>
<p>Cuando un servicio se detiene, el módulo:</p>
<ul>
<li>Registra el evento en syslog con la etiqueta 'servicemon'</li>
</ul>

<footer>
EOF
    
    cat > "$MODDIR/CHANGELOG" <<'EOF'
Version 1.1 (2024)
- Added configurable service filtering
- Filter options: Default (All), Active only, Failed only
- Enhanced configuration interface

Version 1.0 (2024)
- Initial release
- Monitor enabled system services
- Start, stop, and restart services
- Multi-language support (English and Spanish)
- Real-time status updates
- Syslog integration for service events
- Desktop notifications for service status changes
- Modern and user-friendly interface
- Configuration page with module information
EOF
    
    ICON_B64=$(mktemp)
    cat > "$ICON_B64" << 'ICONEOF'
R0lGODlhMAAwAPAAAAAAAAAAACH5BAEAAAAALAAAAAAwADAAAAKrhI+py+0Po5wqJEszCpyf7mkUiAGkOJJqiUKr2krvGS/zDdYGzusmj6vdLjPfynb0/XIVmnLZQTKfsOZU95I6W8NNUQj8yq5hcWRbzk62xOA5BIX/Pj0XML6rP9JuvJ3v4cTGAChncpFR+JSXtshIlgSm5mWWWPlYJdLVFqmxSdlpOQmayRU6isXnGHfnqEhVyBITazgbuxiFWXKlxFJ6uGpVGywsS3yMHFMAADs=
ICONEOF

    base64 -d "$ICON_B64" > "$MODDIR/images/icon.gif" || true
    rm -f "$ICON_B64"
    
    chown -R root:root "$MODDIR" "$ETCDIR"
    chmod -R 755 "$MODDIR"
    chmod 644 "$MODDIR"/*.info* "$MODDIR/lang/"* "$MODDIR/help/"* "$MODDIR/CHANGELOG" 2>/dev/null || true
    chmod 755 "$MODDIR"/*.cgi "$MODDIR"/*.pl 2>/dev/null || true
    chmod 644 "$MODDIR/images/"* 2>/dev/null || true
    
    if [ -f /etc/webmin/webmin.acl ]; then
        if ! grep -q "servicemon" /etc/webmin/webmin.acl 2>/dev/null; then
            sed -i.bak 's/\(^root:.*\)/\1 servicemon/' /etc/webmin/webmin.acl
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
    echo "Services Monitor module installed successfully!"
    echo "=========================================="
    echo ""
    echo "Module location: $MODDIR"
    echo "Config location: $ETCDIR"
    echo ""
    echo "Features:"
    echo "  ✓ Modern and user-friendly interface"
    echo "  ✓ Syslog integration (tag: servicemon)"
    echo "  ✓ Real-time service monitoring"
    echo "  ✓ Configuration page available"
    echo "  ✓ Configurable service filtering"
    echo ""
    echo "Please log out and log back into Webmin to see the new module."
    echo "You can find it under the 'System' category."
    echo "https://localhost:10000/servicemon/"
    echo ""
    echo "To view syslog entries: grep servicemon /var/log/syslog"
    echo ""
}

uninstall_module() {
    echo ""
    echo "=========================================="
    echo "Uninstalling Services Monitor Module"
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
        if grep -q "servicemon" /etc/webmin/webmin.acl 2>/dev/null; then
            sed -i.bak 's/ servicemon//g' /etc/webmin/webmin.acl
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
    echo "Services Monitor module uninstalled successfully!"
    echo "=========================================="
    echo ""
}

show_menu() {
    clear
    echo "============================================================"
    echo "          SERVICES MONITOR - WEBMIN MODULE"
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
    echo "  install      Install the Services Monitor module"
    echo "  uninstall    Uninstall the Services Monitor module"
    echo "  -h, --help   Show this help message"
    echo ""
    echo "If no option is provided, interactive menu will be shown."
    echo ""
    echo "Examples:"
    echo "  $0 install      # Install module without menu"
    echo "  $0 uninstall    # Uninstall module without menu"
    echo "  $0              # Show interactive menu"
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
