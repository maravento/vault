#!/bin/bash
# maravento.com
# GPL-3.0 https://www.gnu.org/licenses/gpl.txt
#
# Squid Monitor module installation/uninstallation script for Webmin
#
# Description:
#   This script installs or uninstalls the Squid Monitor module for Webmin.
#   The module provides a interface to monitor Squid proxy logs,
#   focusing on blocked requests (TCP_DENIED) and ACL statistics.
#
# Features:
#   - Dashboard with real-time statistics
#   - Monitor TCP_DENIED requests from Squid logs
#   - Configurable ACL monitoring (add/remove ACL files to track)
#   - Support for file-based and regex-based ACLs
#   - Top blocked domains and clients
#   - Detailed blocked requests by client IP with ACL identification
#   - Hourly traffic graphs
#   - Multi-language support (English and Spanish)
#   - Auto-refresh capability
#   - Zero external dependencies (pure Perl parsing)
#   - Search bar
#
# Usage:
#   sudo ./squidmon.sh [OPTIONS]
#
# Options:
#   install      Install the module
#   uninstall    Uninstall the module
#   -h, --help   Show help message
#
# Examples:
#   sudo ./squidmon.sh              # Interactive menu
#   sudo ./squidmon.sh install      # Direct installation
#   sudo ./squidmon.sh uninstall    # Direct uninstallation

# check root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# check SO
UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
if [[ "$UBUNTU_ID" != "ubuntu" || "$UBUNTU_VERSION" != "24.04" ]]; then
    echo "This script requires Ubuntu 24.04. Use at your own risk"
    # exit 1
fi

set -e

MODNAME="squidmon"
MODDIR="/usr/share/webmin/$MODNAME"
ETCDIR="/etc/webmin/$MODNAME"

# ============================================================
# Function: Install Module
# ============================================================
install_module() {
    echo ""
    echo "=========================================="
    echo "Installing Proxy Monitor Module"
    echo "=========================================="
    echo ""
    
    # Check if Squid is installed
    if ! command -v squid &>/dev/null; then
        echo "Warning: Squid does not appear to be installed"
        echo "The module will be installed anyway, but may not function properly"
        read -p "Continue? (y/n): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Installation cancelled."
            exit 0
        fi
    fi
    
    echo "Creating Proxy Monitor module structure..."
    
    # Create directories
    mkdir -p "$MODDIR/images"
    mkdir -p "$MODDIR/lang"
    mkdir -p "$MODDIR/help"
    mkdir -p "$ETCDIR"
    
    # ============================================================
    # 1. index.cgi (main dashboard)
    # ============================================================
    cat > "$MODDIR/index.cgi" <<'INDEXCGI'
#!/usr/bin/perl
# Proxy Monitor - Main Dashboard
use strict;
use warnings;

do '../web-lib.pl';
do '../ui-lib.pl';
&init_config();
&ReadParse();

our $module_name;
our %text;
our %config;
our %in;

# Load language and config
&load_language($module_name);
&read_file("$ENV{'WEBMIN_CONFIG'}/$module_name/config", \%config);

# Get configuration values
my $log_file = $config{'squid_log'} || '/var/log/squid/access.log';
my $max_lines = $config{'max_lines'} || '50000';
my $acl_list = $config{'acl_list'} || '';
my $auto_refresh = $config{'auto_refresh'} || '0';
my $refresh_interval = $config{'refresh_interval'} || '60';
my $time_range = $config{'time_range'} || '24';

# Validate refresh interval
$refresh_interval = 60 if $refresh_interval !~ /^\d+$/ || $refresh_interval < 30;

# Parse ACL list - SUPPORT BOTH \n AND \t
my @monitored_acls = ();
if ($acl_list) {
    foreach my $acl_entry (split(/[\n\t]+/, $acl_list)) {
        $acl_entry =~ s/^\s+|\s+$//g;
        next if $acl_entry eq '';
        
        # Support regex: prefix for regex-based ACLs
        if ($acl_entry =~ /^regex:(.+)=(.+)$/) {
            my $regex_pattern = $1;
            my $label = $2;
            $regex_pattern =~ s/^\s+|\s+$//g;
            $label =~ s/^\s+|\s+$//g;
            push @monitored_acls, { 
                type => 'regex', 
                value => $regex_pattern, 
                label => $label 
            };
        }
        # File-based ACL
        elsif ($acl_entry =~ /^([^=]+)=(.+)$/) {
            my $path = $1;
            my $label = $2;
            $path =~ s/^\s+|\s+$//g;
            $label =~ s/^\s+|\s+$//g;
            push @monitored_acls, { 
                type => 'file', 
                value => $path, 
                label => $label 
            };
        }
    }
}

# Anti-cache headers
print "Cache-Control: no-cache, no-store, must-revalidate, max-age=0\r\n";
print "Pragma: no-cache\r\n";
print "Expires: Thu, 01 Jan 1970 00:00:00 GMT\r\n";

&ui_print_header(undef, $text{'index_title'}, "", undef, 1, 1);

my %client_acl_stats = ();
my %debug_info = ();

# Custom CSS
print <<'EOCSS';
<style>
body { background: #f5f7fa; }
.dashboard-container { max-width: 1400px; margin: 0 auto; padding: 20px; }
.stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin-bottom: 30px; }
.stat-card { background: white; border-radius: 8px; padding: 25px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); border-left: 4px solid; }
.stat-card h3 { margin: 0 0 10px 0; font-size: 14px; color: #666; text-transform: uppercase; letter-spacing: 0.5px; }
.stat-card .number { font-size: 36px; font-weight: bold; margin: 10px 0; }
.stat-card .label {
  font-size: 13px;
  color: #212529; /* black */
}
.card-blue {
  background: #1e3a8a;
  border-left-color: #3b82f6;
}
.card-blue h3, .card-blue .number, .card-blue .label {
  color: #ffffff;
}

.card-red {
  background: #7f1d1d;
  border-left-color: #dc2626;
}
.card-red h3, .card-red .number, .card-red .label {
  color: #ffffff;
}

.card-green {
  background: #065f46;
  border-left-color: #10b981;
}
.card-green h3, .card-green .number, .card-green .label {
  color: #ffffff;
}

.card-purple {
  background: #4c1d95;
  border-left-color: #8b5cf6;
}
.card-purple h3, .card-purple .number, .card-purple .label {
  color: #ffffff;
}
.content-card { background: white; border-radius: 8px; padding: 25px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); margin-bottom: 20px; }
.content-card h2 {
  background: #1f2937; /* gris oscuro */
  color: #ffffff;
  padding: 12px 16px;
  border-radius: 6px 6px 0 0;
  margin: 0 0 20px 0;
  font-size: 18px;
  border-bottom: none;
}
.table-responsive { overflow-x: auto; }
table.data-table { width: 100%; border-collapse: collapse; }
table.data-table th { background: #f9fafb; padding: 12px; text-align: left; font-weight: 600; color: #374151; border-bottom: 2px solid #e5e7eb; }
table.data-table td {
  padding: 12px;
  border-bottom: 1px solid #d1d5db;
  color: #212529; /* black */
}
table.data-table tr:hover { background: #f9fafb; }
.badge { display: inline-block; padding: 4px 12px; border-radius: 12px; font-size: 12px; font-weight: 600; }
.badge-blocked { background: #fee2e2; color: #991b1b; }
.badge-allowed { background: #d1fae5; color: #065f46; }
.icon { font-size: 20px; margin-right: 8px; }
.refresh-indicator { position: fixed; bottom: 20px; right: 20px; background: rgba(59, 130, 246, 0.95); color: white; padding: 12px 24px; border-radius: 25px; font-size: 13px; box-shadow: 0 4px 12px rgba(0,0,0,0.3); z-index: 1000; }
.alert { padding: 15px 20px; border-radius: 8px; margin-bottom: 20px; border-left: 4px solid; }
.alert-info { background: #dbeafe; color: #1e40af; border-left-color: #3b82f6; }
.alert-warning { background: #fef3c7; color: #92400e; border-left-color: #f59e0b; }
.alert-success { background: #d1fae5; color: #065f46; border-left-color: #10b981; }
.grid-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
.ip-row { cursor: pointer; transition: background 0.2s; }
.ip-row:hover { background: #f3f4f6 !important; }
.details-row td { background: #f9fafb !important; padding: 0 !important; }
.details-row table { margin: 10px; width: calc(100% - 20px); }
@media (max-width: 768px) { .grid-2 { grid-template-columns: 1fr; } }
/* Compatible with Legacy and Authentic themes */
.progress-bar.custom-fill {
    background: linear-gradient(90deg, #3b82f6, #60a5fa);
    height: 100%;
    transition: width 0.3s ease-in-out;
}

</style>
EOCSS

print "<div class='dashboard-container'>";

# Check if log file exists
if (!-f $log_file) {
    print "<div class='alert alert-warning'>";
    print "⚠️ <strong>$text{'error_log_not_found'}</strong><br>";
    print "$text{'error_log_path'}: <code>$log_file</code>";
    print "</div>";
    print "</div>";
    &ui_print_footer("/", $text{'index'});
    exit;
}

# Parse log file
my %stats = (
    total_requests => 0,
    blocked_requests => 0,
    allowed_requests => 0,
    unique_clients => 0,
    unique_domains => 0
);

my %blocked_domains = ();
my %allowed_domains = ();
my %blocked_clients = ();
my %hourly_blocked = ();
my %hourly_allowed = ();
my %clients_data = ();
my %acl_hits = ();
my %client_logs = ();

# Preload ACLs into REVERSE LOOKUP HASH for O(1) speed
my %domain_to_acl = (); # domain => ACL label (instant lookup)
my @regex_acls = ();    # Only store regex ACLs separately

# DEBUG: Show monitored ACLs
print "<!-- DEBUG: Show monitored ACLs -->\n";
foreach my $acl (@monitored_acls) {
    print "<!-- ACL: type=$acl->{type}, label=$acl->{label}, value=$acl->{value} -->\n";
    if ($acl->{type} eq 'file') {
        if (-f $acl->{value}) {
            my $line_count = 0;
            if (open(my $fh, '<', $acl->{value})) {
                while (<$fh>) { $line_count++; }
                close($fh);
            }
            print "<!-- FILE EXISTS: $line_count lines -->\n";
        } else {
            print "<!-- FILE NOT FOUND: $acl->{value} -->\n";
        }
    }
}
print "<!-- END DEBUG -->\n";

foreach my $acl (@monitored_acls) {
    $acl_hits{$acl->{label}} = 0;

    if ($acl->{type} eq 'file' && -f $acl->{value}) {
        if (open(my $fh, '<', $acl->{value})) {
            while (my $line = <$fh>) {
                chomp($line);
                $line =~ s/^\s+|\s+$//g;
                $line =~ s/^\.+//g;  # REMOVE LEADING DOTS
                next if $line eq '' || $line =~ /^#/;
                # REVERSE INDEX: domain points to ACL label
                $domain_to_acl{lc($line)} = $acl->{label};
            }
            close($fh);
        }
    } elsif ($acl->{type} eq 'regex') {
        push @regex_acls, $acl;
    }
}

# DEBUG: Show how many entries were loaded into domain_to_acl
my $total_domains = scalar(keys %domain_to_acl);
print "<!-- DEBUG: Total dominios cargados en domain_to_acl: $total_domains -->\n";
if ($total_domains > 0) {
    my @sample_domains = (keys %domain_to_acl)[0..4];
    print "<!-- Sample domains: " . join(", ", @sample_domains) . " -->\n";
}

# Parse last N lines of log
my $lines_to_read = int($max_lines);
my @log_lines = ();

if (open(my $fh, '<', $log_file)) {
    # Read file in reverse to get last N lines efficiently
    seek($fh, 0, 2);
    my $file_size = tell($fh);
    my $chunk_size = 8192;
    my $buffer = '';
    my $lines_found = 0;
    
    while ($file_size > 0 && $lines_found < $lines_to_read) {
        my $read_size = $chunk_size;
        $read_size = $file_size if $file_size < $chunk_size;
        $file_size -= $read_size;
        
        seek($fh, $file_size, 0);
        read($fh, my $chunk, $read_size);
        $buffer = $chunk . $buffer;
        
        my @lines = split(/\n/, $buffer);
        $buffer = shift(@lines) if $file_size > 0;
        
        unshift(@log_lines, @lines);
        $lines_found = scalar(@log_lines);
    }
    close($fh);
    
    # Keep only last N lines
    @log_lines = splice(@log_lines, -$lines_to_read) if scalar(@log_lines) > $lines_to_read;
}

# Calculate time threshold for filtering
my $time_threshold = time() - ($time_range * 3600);

# Preload ACLs into memory for fast lookup (only for Blocked Requests by IP)
my %acl_lookup = ();
foreach my $acl (@monitored_acls) {
    next unless $acl->{type} eq 'file' && -f $acl->{value};
    if (open(my $fh, '<', $acl->{value})) {
        while (my $line = <$fh>) {
            chomp($line);
            $line =~ s/^\s+|\s+$//g;
            next if $line eq '' || $line =~ /^#/;
            push @{ $acl_lookup{lc($line)} }, $acl->{label};
        }
        close($fh);
    }
}

# Parse each log line
foreach my $line (@log_lines) {
    # Squid log format: timestamp elapsed client action/code bytes method URL user hierarchy/peer type
    next if $line !~ /^(\d+\.\d+)\s+\S+\s+(\S+)\s+(\S+)\s+\S+\s+\S+\s+(https?:\/\/)?([^\s\/]+)([^\s]*)/;

    my $timestamp = int($1);
    my $client = $2;
    my $action_code = $3;
    my $domain = $5;
    my $proto = ($action_code =~ /^CONNECT/) ? 'https://' : ($4 || 'http://');
    my $url = $proto . ($5 // '') . ($6 // '');

    # Skip if outside time range
    next if $timestamp < $time_threshold;

    $stats{total_requests}++;

    # Extract hour for hourly stats
    my ($min, $hour, $day, $mon, $year) = (localtime($timestamp))[1,2,3,4,5];
    $mon += 1; $year += 1900;
    my $hour_key = sprintf("%04d-%02d-%02d %02d:00", $year, $mon, $day, $hour);

if ($action_code =~ /^TCP_DENIED/) {
    $stats{blocked_requests}++;
    $blocked_domains{$domain}++;
    $blocked_clients{$client}++;
    push @{$hourly_blocked{$hour_key}}, 1;

    $clients_data{$client}{blocked}++;
    $clients_data{$client}{total}++;

    my $domain_lc = lc($domain);
    my @matched_acls;

    # REMOVE PORT from domain if present
    my $domain_only = $domain_lc;
    $domain_only =~ s/:\d+$//;

    # INSTANT ACL LOOKUP
    if (exists $domain_to_acl{$domain_only}) {
        push @matched_acls, $domain_to_acl{$domain_only};
    }
    # Check subdomain matches
    elsif ($domain_only =~ /\./) {
        my @parts = split(/\./, $domain_only);
        for (my $i = 1; $i < scalar(@parts); $i++) {
            my $test_domain = join('.', @parts[$i..$#parts]);
            if (exists $domain_to_acl{$test_domain}) {
                push @matched_acls, $domain_to_acl{$test_domain};
                last;
            }
        }
    }

    # Check regex ACLs
    foreach my $acl (@regex_acls) {
        if ($url =~ /$acl->{value}/i) {
            push @matched_acls, $acl->{label};
        }
    }

    # UPDATE acl_hits for each matched ACL
    foreach my $acl (@matched_acls) {
        $acl_hits{$acl}++;
    }
    
    # If no ACL matched, count as Unknown ACL
    if (!@matched_acls) {
        $acl_hits{'Unknown ACL'}++;
    }

    my $acl_info = @matched_acls ? join(', ', @matched_acls) : '-';
    push @{$client_logs{$client}}, [$timestamp, 'Blocked', $domain, $acl_info];

    } else {
        $stats{allowed_requests}++;
        push @{$hourly_allowed{$hour_key}}, 1;

        $allowed_domains{$domain}++;
        $clients_data{$client}{allowed}++;
        $clients_data{$client}{total}++;
    }
}

# Calculate unique counts
$stats{unique_clients} = scalar(keys %clients_data);
$stats{unique_domains} = scalar(keys %blocked_domains);

# Statistics Cards
print "<div class='stats-grid'>";

print "<div class='stat-card card-blue'>";
print "<h3>📊 $text{'stat_total_requests'}</h3>";
print "<div class='number'>" . format_number($stats{total_requests}) . "</div>";
print "<div class='label'>$text{'stat_last'} $time_range $text{'stat_hours'}</div>";
print "</div>";

print "<div class='stat-card card-red'>";
print "<h3>🚫 $text{'stat_blocked'}</h3>";
print "<div class='number'>" . format_number($stats{blocked_requests}) . "</div>";
my $block_percent = $stats{total_requests} > 0 ? sprintf("%.1f", ($stats{blocked_requests} / $stats{total_requests}) * 100) : 0;
print "<div class='label'>$block_percent% $text{'stat_of_total'}</div>";
print "</div>";

print "<div class='stat-card card-green'>";
print "<h3>✅ $text{'stat_allowed'}</h3>";
print "<div class='number'>" . format_number($stats{allowed_requests}) . "</div>";
my $allow_percent = $stats{total_requests} > 0 ? sprintf("%.1f", ($stats{allowed_requests} / $stats{total_requests}) * 100) : 0;
print "<div class='label'>$allow_percent% $text{'stat_of_total'}</div>";
print "</div>";

print "<div class='stat-card card-purple'>";
print "<h3>👥 $text{'stat_clients'}</h3>";
print "<div class='number'>$stats{unique_clients}</div>";
print "<div class='label'>$text{'stat_unique_clients'}</div>";
print "</div>";

print "</div>"; # End stats-grid

# Chart
# Traffic Distribution Chart - Fixed colors and time context
print "<div class='content-card'>";
print "<h2>📊 $text{'traffic_distribution'}</h2>";

my $blocked = $stats{blocked_requests} || 0;
my $allowed = $stats{allowed_requests} || 0;
my $total = $blocked + $allowed;

# Show the time period
print "<div style='text-align: center; margin-bottom: 20px; padding: 10px; background: #f8fafc; border-radius: 6px;'>";
print "<strong style='color: #000000 !important; font-size: 14px;'>📅 Time Period: Last $time_range hours</strong>";
print "</div>";

if ($total > 0) {
    my $blocked_percent = sprintf("%.1f", ($blocked / $total) * 100);
    my $allowed_percent = sprintf("%.1f", ($allowed / $total) * 100);
    
    print "<table style='width: 100%; border-collapse: collapse; margin: 20px 0; color: #000000 !important;'>";
    
    # Header row - No background, just text
    print "<tr>";
    print "<th style='text-align: left; padding: 12px; width: 100px; color: #000000 !important; border: 1px solid #e5e7eb !important;'>Type</th>";
    print "<th style='text-align: center; padding: 12px; width: 80px; color: #000000 !important; border: 1px solid #e5e7eb !important;'>Count</th>";
    print "<th style='text-align: center; padding: 12px; width: 80px; color: #000000 !important; border: 1px solid #e5e7eb !important;'>Percent</th>";
    print "<th style='padding: 12px; color: #000000 !important; border: 1px solid #e5e7eb !important;'>Distribution</th>";
    print "</tr>";
    
    # Blocked row
    print "<tr style='background: #fef2f2;'>";
    print "<td style='padding: 12px; border: 1px solid #e5e7eb; color: #000000 !important; text-align: left;'><strong style='color: #dc2626 !important;'>🚫 Blocked</strong></td>";
    print "<td style='padding: 12px; border: 1px solid #e5e7eb; text-align: left; color: #000000 !important;'>" . format_number($blocked) . "</td>";
    print "<td style='padding: 12px; border: 1px solid #e5e7eb; text-align: left; color: #000000 !important;'><strong>$blocked_percent%</strong></td>";
    print "<td style='padding: 12px; border: 1px solid #e5e7eb; color: #000000 !important; text-align: left;'>";
    print "<div style='background: #dc2626; height: 25px; width: $blocked_percent%; border-radius: 4px;'></div>";
    print "</td>";
    print "</tr>";

    # Allowed row
    print "<tr style='background: #f0fdf4;'>";
    print "<td style='padding: 12px; border: 1px solid #e5e7eb; color: #000000 !important; text-align: left;'><strong style='color: #10b981 !important;'>✅ Allowed</strong></td>";
    print "<td style='padding: 12px; border: 1px solid #e5e7eb; text-align: left; color: #000000 !important;'>" . format_number($allowed) . "</td>";
    print "<td style='padding: 12px; border: 1px solid #e5e7eb; text-align: left; color: #000000 !important;'><strong>$allowed_percent%</strong></td>";
    print "<td style='padding: 12px; border: 1px solid #e5e7eb; color: #000000 !important; text-align: left;'>";
    print "<div style='background: #10b981; height: 25px; width: $allowed_percent%; border-radius: 4px;'></div>";
    print "</td>";
    print "</tr>";

    # Total row
    print "<tr style='background: #eff6ff;'>";
    print "<td style='padding: 12px; border: 1px solid #e5e7eb; color: #000000 !important; text-align: left;'><strong style='color: #3b82f6 !important;'>📊 Total</strong></td>";
    print "<td style='padding: 12px; border: 1px solid #e5e7eb; text-align: left; color: #000000 !important;'><strong>" . format_number($total) . "</strong></td>";
    print "<td style='padding: 12px; border: 1px solid #e5e7eb; text-align: left; color: #000000 !important;'><strong>100%</strong></td>";
    print "<td style='padding: 12px; border: 1px solid #e5e7eb; color: #000000 !important; text-align: left;'>";
    print "<div style='background: #3b82f6; height: 25px; width: 100%; border-radius: 4px;'></div>";
    print "</td>";
    print "</tr>";
    
    print "</table>";
    
    # Additional information about the period
    print "<div style='margin-top: 15px; padding: 10px; background: #fffbeb; border-radius: 6px; border-left: 4px solid #f59e0b;'>";
    print "<small style='color: #000000 !important;'>";
    print "ℹ️ <strong>Time Context:</strong> Showing data from the last <strong>$time_range hours</strong>. ";
    print "Analyzed " . format_number(scalar(@log_lines)) . " log lines from Squid access log.";
    print "</small>";
    print "</div>";
    
} else {
    print "<div style='text-align: center; padding: 40px; color: #000000 !important;'>";
    print "No traffic data available for the last $time_range hours";
    print "</div>";
}

print "</div>";

# ACL Statistics (if configured)
if (@monitored_acls > 0) {
    print "<div class='content-card'>";
    print "<h2>📋 $text{'acl_stats_title'}</h2>";
    
    if (scalar(keys %acl_hits) > 0) {
        print "<div class='table-responsive'>";
        print "<table class='data-table'>";
        print "<thead><tr>";
        print "<th>$text{'acl_name'}</th>";
        print "<th>$text{'acl_type'}</th>";
        print "<th>$text{'acl_blocks'}</th>";
        print "<th>$text{'acl_percentage'}</th>";
        print "<th style='width: 40%;'>$text{'acl_activity'}</th>";
        print "</tr></thead><tbody>";
        
        my $total_acl_blocks = 0;
        $total_acl_blocks += $_ for values %acl_hits;
        
        foreach my $acl_label (sort { $acl_hits{$b} <=> $acl_hits{$a} } keys %acl_hits) {
            my $hits = $acl_hits{$acl_label};
            my $percentage = $total_acl_blocks > 0 ? sprintf("%.1f", ($hits / $total_acl_blocks) * 100) : 0;
            
            # Find ACL type
            my $acl_type = 'file';
            foreach my $acl (@monitored_acls) {
                if ($acl->{label} eq $acl_label) {
                    $acl_type = $acl->{type};
                    last;
                }
            }
            
            print "<tr>";
            print "<td><strong>$acl_label</strong></td>";
            print "<td><span class='badge " . ($acl_type eq 'regex' ? 'badge-blocked' : 'badge-allowed') . "'>$acl_type</span></td>";
            print "<td>" . format_number($hits) . "</td>";
            print "<td>$percentage%</td>";
            print "<td>";
            print "<div class='progress' style='height: 10px; background-color: #d1d5db; border-radius: 5px; overflow: hidden;'>";
            print "<div class='progress-bar custom-fill' role='progressbar' style='width: $percentage%;'></div>";
            print "</div>";
            print "</td>";
            print "</tr>";
        }
        
        print "</tbody></table></div>";
    } else {
        print "<div class='alert alert-info'>";
        print "ℹ️ $text{'acl_no_blocks'}";
        print "</div>";
    }
    
    print "</div>";
}

# Two-column layout for Top Blocked Domains and Top Blocked Clients
print "<div class='grid-2'>";

# Top Blocked Domains
print "<div class='content-card'>";
print "<h2>🚫 $text{'top_blocked_title'}</h2>";

if (scalar(keys %blocked_domains) > 0) {
    print "<div class='table-responsive'>";
    print "<table class='data-table'>";
    print "<thead><tr>";
    print "<th>$text{'domain'}</th>";
    print "<th>$text{'blocks'}</th>";
    print "</tr></thead><tbody>";
    
    my $count = 0;
    foreach my $domain (sort { $blocked_domains{$b} <=> $blocked_domains{$a} } keys %blocked_domains) {
        last if ++$count > 10;
        print "<tr>";
        print "<td>$domain</td>";
        print "<td><span class='badge badge-blocked'>" . format_number($blocked_domains{$domain}) . "</span></td>";
        print "</tr>";
    }
    
    print "</tbody></table></div>";
} else {
    print "<div class='alert alert-success'>";
    print "✅ $text{'no_blocks'}";
    print "</div>";
}

print "</div>";

# Top Blocked Clients
print "<div class='content-card'>";
print "<h2>👥 $text{'top_clients_title'}</h2>";

if (scalar(keys %clients_data) > 0) {
    print "<div class='table-responsive'>";
    print "<table class='data-table'>";
    print "<thead><tr>";
    print "<th>$text{'client_ip'}</th>";
    print "<th>$text{'total'}</th>";
    print "<th>$text{'blocked'}</th>";
    print "<th>$text{'blocked_percent'}</th>";
    print "</tr></thead><tbody>";
    
    my $count = 0;
    foreach my $client (sort { $clients_data{$b}{total} <=> $clients_data{$a}{total} } keys %clients_data) {
        last if ++$count > 10;
        my $total = $clients_data{$client}{total} || 0;
        my $blocked = $clients_data{$client}{blocked} || 0;
        my $percent = $total > 0 ? sprintf("%.1f", ($blocked / $total) * 100) : 0;
        
        print "<tr>";
        print "<td><strong>$client</strong></td>";
        print "<td>" . format_number($total) . "</td>";
        print "<td><span class='badge badge-blocked'>" . format_number($blocked) . "</span></td>";
        print "<td>$percent%</td>";
        print "</tr>";
    }
    
    print "</tbody></table></div>";
} else {
    print "<div class='alert alert-info'>";
    print "ℹ️ $text{'no_clients'}";
    print "</div>";
}

print "</div>";

print "</div>"; # End grid-2

# === Traffic by Client IP (Optimized with ACL Menu) ===
print "<div class='content-card' id='traffic-by-ip'>";
print "<h2>📶 $text{'traffic_by_ip'}</h2>";

# PDF Button - General
print "<div style='margin-bottom: 20px; text-align: right;'>";
print "<form method='post' action='pdf_report.cgi' target='_blank' style='display: inline; background: #1f2937; padding: 15px; border-radius: 8px;'>";
print "<span style='color: white; margin-right: 10px;'>📊 Report Time Range:</span>";
print "<select name='time_range' style='margin-right: 10px; padding: 5px;'>";
print "<option value='24'>Last 24 Hours</option>";
print "<option value='168'>Last 7 Days</option>";
print "<option value='720'>Last 30 Days</option>";
print "</select>";
print "<input type='hidden' name='max_lines' value='$max_lines'>";
print "<input type='submit' value='📄 Generate PDF Report' style='background-color: #1f2937; color: #ffffff !important; border: 1px solid #ffffff !important; padding: 5px 10px; margin-right: 10px;'>";
print "</form>";
print "</div>";

# Filter form with ACL menu
my %input = %in;
my $show_acl = $input{'filter_acl'} || '';
my $show_blocked = $input{'filter_blocked'} || '';
my $show_allowed = $input{'filter_allowed'} || '';
my $search_query = $in{'search_query'} || '';

print "<form id='filter-form' method='get' action='#traffic-by-ip' style='margin-bottom: 20px; padding: 20px; background: #1f2937; border-radius: 8px; color: #ffffff; box-shadow: 0 0 6px rgba(0,0,0,0.3); border: 1px solid #ffffff; display: flex; align-items: center; gap: 15px; flex-wrap: wrap;'>";
print "<div><strong>Filters:</strong></div>";
print "<div>";
print "<label style='color: #ffffff;'>ACL: </label>";
print "<select name='filter_acl' style='width:200px;'>";
print "<option value=''>-- All ACLs --</option>";
foreach my $acl (@monitored_acls) {
    my $label = $acl->{label};
    my $sel = ($label eq $show_acl) ? "selected" : "";
    print "<option value='$label' $sel>$label</option>";
}
# Add Unknown ACL at the end if there are unclassified blocks
if ($acl_hits{'Unknown ACL'} && $acl_hits{'Unknown ACL'} > 0) {
    my $sel = ('Unknown ACL' eq $show_acl) ? "selected" : "";
    print "<option value='Unknown ACL' $sel>Unknown ACL</option>";
}
print "</select>";
print "</div>";

# Search box
print "<div>";
print "<label style='color: #ffffff; margin-left: 15px;'>Search: </label>";
print "<input type='text' name='search_query' value='$search_query' placeholder='IP or domain...' style='width: 250px; padding: 5px; margin-left: 5px;'>";
print "<input type='submit' name='search' value='Search' style='background-color: #1f2937; color: #ffffff !important; border: 1px solid #ffffff !important; padding: 5px 10px; margin-left: 5px;'>";
print "</div>";

print "<div>";
print "<input type='submit' name='filter_blocked' value='Show Blocked Only' style='background-color: #1f2937; color: #ffffff !important; border: 1px solid #ffffff !important; padding: 5px 10px; margin-right: 10px;'>";
print "<input type='submit' name='filter_allowed' value='Show Allowed Only' style='background-color: #1f2937; color: #ffffff !important; border: 1px solid #ffffff !important; padding: 5px 10px; margin-right: 10px;'>";
print "<a href='?' style='color: #ffffff !important; text-decoration: underline; padding: 5px 10px; display: inline-block;'>Clear Filters</a>";
print "</div>";
print "</form>";

# DEBUG: Show loaded ACL information
print "<!-- DEBUG: " . scalar(@monitored_acls) . " Monitored ACLs -->\n";
foreach my $acl (@monitored_acls) {
    print "<!-- ACL: $acl->{type} - $acl->{label} - $acl->{value} -->\n";
}

# Process logs for client data with improved ACL detection
foreach my $line (@log_lines) {
    next unless $line =~ /^(\d+\.\d+)\s+\S+\s+(\S+)\s+(\S+)\s+\S+\s+\S+\s+(https?:\/\/)?([^\s\/]+)([^\s]*)/;
    
    my $timestamp = int($1);
    my $client = $2;
    my $action_code = $3;
    my $domain = $5;
    my $proto = ($action_code =~ /^CONNECT/) ? 'https://' : ($4 || 'http://');
    my $url = $proto . ($5 // '') . ($6 // '');
    
    # Skip if outside time range
    next if $timestamp < $time_threshold;
    
    my $is_blocked = ($action_code =~ /^TCP_DENIED/) ? 'Blocked' : 'Allowed';
    
    # DEBUG: Request information
    $debug_info{total_requests}++;
    $debug_info{"$client-$is_blocked"}++;
    
    # Determine which ACL matched
    my $matched_acl = 'N/A';
    
    if ($is_blocked eq 'Blocked') {
        my $domain_lc = lc($domain);
        $debug_info{blocked_requests}++;
        
        # DEBUG
        $debug_info{domains}{$domain_lc}++;
        
        # REMOVE PORT from domain if it exists
        my $domain_only = $domain_lc;
        $domain_only =~ s/:\d+$//;  # Remove :port
        
        # 1. Search for EXACT match in file ACLs
        my $found_acl = '';
        if (exists $domain_to_acl{$domain_only}) {
            $found_acl = $domain_to_acl{$domain_only};
            $debug_info{exact_matches}++;
        }
        
        # 2. Search for a SUBDOMAIN match if an exact match was not found
        if (!$found_acl && $domain_only =~ /\./) {
            my @parts = split(/\./, $domain_only);
            # Test from the full domain to the TLD
            for (my $i = 1; $i < scalar(@parts); $i++) {
                my $test_domain = join('.', @parts[$i..$#parts]);
                if (exists $domain_to_acl{$test_domain}) {
                    $found_acl = $domain_to_acl{$test_domain};
                    $debug_info{subdomain_matches}++;
                    last;
                }
            }
        }
        
        # 3. Search in ACLs regex if not found in files
        if (!$found_acl) {
            foreach my $acl (@regex_acls) {
                if ($url =~ /$acl->{value}/i) {
                    $found_acl = $acl->{label};
                    $debug_info{regex_matches}++;
                    last;
                }
            }
        }
        
        $matched_acl = $found_acl || 'Unknown ACL';
        $acl_hits{$matched_acl}++;
        
    } else {
        # For allowed requests - DO NOT count as an ACL hit
        $matched_acl = 'Allowed Traffic';
        $debug_info{allowed_requests}++;
    }
    
    # Store ALL unfiltered statistics
        $client_acl_stats{$client}{$matched_acl}{$is_blocked}++;
        $client_acl_stats{$client}{total}{$is_blocked}++;
        push @{ $client_acl_stats{$client}{$matched_acl}{urls}{$is_blocked} }, $url;

        # DEBUG: Register the association
        $debug_info{acl_matches}{$matched_acl}++;
}

# DEBUG: Show diagnostic information
print "<!-- DEBUG INFO: -->\n";
print "<!-- Total requests: $debug_info{total_requests} -->\n";
print "<!-- Blocked: " . ($debug_info{blocked_requests} || 0) . " -->\n";
print "<!-- Allowed: " . ($debug_info{allowed_requests} || 0) . " -->\n";
print "<!-- Exact matches: " . ($debug_info{exact_matches} || 0) . " -->\n";
print "<!-- Subdomain matches: " . ($debug_info{subdomain_matches} || 0) . " -->\n";
print "<!-- Regex matches: " . ($debug_info{regex_matches} || 0) . " -->\n";

# Show blocked domains for debugging
if ($debug_info{domains}) {
    print "<!-- Blocked domains: " . join(', ', keys %{$debug_info{domains}}) . " -->\n";
}

# Show ACL matches for debugging
if ($debug_info{acl_matches}) {
    print "<!-- ACL Matches: -->\n";
    foreach my $acl (keys %{$debug_info{acl_matches}}) {
        print "<!--   $acl: $debug_info{acl_matches}{$acl} -->\n";
    }
}

# ============================================================
# SEARCH AND FILTERING
# ============================================================

my @clients_to_show = ();
my $search_is_ip = 0;  # Flag para saber si la búsqueda es una IP

# If there is an active search
if ($search_query && $search_query ne '') {
    $search_query = lc($search_query);  # Convertir a minúsculas para comparación
    
    # Detect if it is an IP address (simple pattern: xxx.xxx.xxx.xxx)
    if ($search_query =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
        $search_is_ip = 1;
    }
    
    foreach my $client (keys %client_acl_stats) {
        my $show_client = 0;
        
        # Search for a match in the client's IP address.
        if ($client =~ /\Q$search_query\E/i) {
            $show_client = 1;
        }
        
        # Only search URLs if it is NOT an IP address
        if (!$show_client && !$search_is_ip) {
            # Buscar en URLs bloqueadas del cliente
            foreach my $acl (keys %{$client_acl_stats{$client}}) {
                next if $acl eq 'total' || $acl eq 'urls';
                
                if (exists $client_acl_stats{$client}{$acl}{urls}{Blocked}) {
                    foreach my $url (@{$client_acl_stats{$client}{$acl}{urls}{Blocked}}) {
                        if ($url =~ /\Q$search_query\E/i) {
                            $show_client = 1;
                            last;
                        }
                    }
                }
                
                last if $show_client;
            }
            
            # Search within allowed client URLs
            if (!$show_client) {
                foreach my $acl (keys %{$client_acl_stats{$client}}) {
                    next if $acl eq 'total' || $acl eq 'urls';
                    
                    if (exists $client_acl_stats{$client}{$acl}{urls}{Allowed}) {
                        foreach my $url (@{$client_acl_stats{$client}{$acl}{urls}{Allowed}}) {
                            if ($url =~ /\Q$search_query\E/i) {
                                $show_client = 1;
                                last;
                            }
                        }
                    }
                    
                    last if $show_client;
                }
            }
        }
        
        push @clients_to_show, $client if $show_client;
    }
} else {
    # Without searching, show all
    @clients_to_show = keys %client_acl_stats;
}

# SHOW SEARCH INFORMATION
if ($search_query && $search_query ne '') {
    my $results_count = scalar(@clients_to_show);
    my $search_type = $search_is_ip ? "IP Address" : "Domain";
    print "<div style='margin-bottom: 15px; padding: 12px; background: #eff6ff; border-left: 4px solid #3b82f6; border-radius: 4px;'>";
    print "<strong style='color: #1e40af;'>🔍 Search Results ($search_type):</strong> ";
    print "Found <strong style='color: #1e40af;'>$results_count</strong> client(s) matching '<strong>$search_query</strong>'";
    print "</div>";
    
    if ($results_count == 0) {
        print "<div style='padding: 20px; text-align: center; background: #fff5f5; border-radius: 4px; border: 1px solid #fecaca;'>";
        print "<strong style='color: #dc2626;'>No results found</strong><br>";
        print "<small style='color: #991b1b;'>Try searching with a different IP address or domain</small>";
        print "</div>";
    }
}

# ============================================================
# SHOW FILTERED CUSTOMERS
# ============================================================

foreach my $client (sort @clients_to_show) {
    my %acl_stats = %{$client_acl_stats{$client}};
    my $total_blocked = $acl_stats{total}{Blocked} || 0;
    my $total_allowed = $acl_stats{total}{Allowed} || 0;
    my $total_requests = $total_blocked + $total_allowed;

    # PRE-CHECK if this client has at least one row that matches the filters
    my $client_has_matching_data = 0;
    foreach my $acl (keys %acl_stats) {
        next if $acl eq 'total';
        
        my $b = $acl_stats{$acl}{Blocked} || 0;
        my $a = $acl_stats{$acl}{Allowed} || 0;
        
        # If there is no ACL filter OR if the ACL matches
        if (!$show_acl || $show_acl eq '' || $acl eq $show_acl) {
            # Si no hay filtro de tipo O si los datos coinciden
            if ((!$show_blocked && !$show_allowed) || 
                ($show_blocked && !$show_allowed && $b > 0) ||
                ($show_allowed && !$show_blocked && $a > 0) ||
                ($show_blocked && $show_allowed && ($b > 0 || $a > 0))) {
                $client_has_matching_data = 1;
                last;
            }
        }
    }
    
    # If there is no matching data, skip this client
    next unless $client_has_matching_data;

    print "<details style='margin-bottom: 15px; border: 1px solid #ddd; border-radius: 5px;'>";
    print "<summary style='padding: 10px; background: #f8f9fa; cursor: pointer; color: #212529 !important;'>";
    print "<strong>$client</strong> — Total: <strong>$total_requests</strong> | ";
    print "Blocked: <span style='color: #dc3545 !important;'><strong>$total_blocked</strong></span> | ";
    print "Allowed: <span style='color: #28a745 !important;'><strong>$total_allowed</strong></span>";
    
    # PDF Button by IP
    print "<form method='post' action='pdf_report.cgi' target='_blank' style='display: inline; float: right;'>";
    print "<input type='hidden' name='client_ip' value='$client'>";
    print "<input type='hidden' name='time_range' value='$time_range'>";
    print "<input type='hidden' name='max_lines' value='$max_lines'>";
    print "<input type='submit' value='📄 PDF Report' style='background: #dc2626; color: #000000 !important; border: none; padding: 5px 10px; border-radius: 3px; cursor: pointer; font-weight: bold; font-family: Arial, sans-serif !important; font-size: 12px !important; margin-left: 10px;'>";
    print "</form>";
    
    print "</summary>";

    print "<div style='padding: 15px; background: white; color: #212529 !important;'>";
    print "<table style='width: 100%; border-collapse: collapse; color: #212529 !important;'>";
    print "<thead><tr style='background: #e9ecef;'>";
    print "<th style='padding: 8px; text-align: left; color: #212529 !important;'>ACL Match</th>";
    print "<th style='padding: 8px; text-align: center; color: #212529 !important;'>Blocked</th>";
    print "<th style='padding: 8px; text-align: center; color: #212529 !important;'>Allowed</th>";
    print "<th style='padding: 8px; text-align: center; color: #212529 !important;'>Total</th>";
    print "</tr></thead><tbody>";

    my $has_visible_rows = 0;
    foreach my $acl (sort keys %acl_stats) {
        next if $acl eq 'total';

        my $b = $acl_stats{$acl}{Blocked} || 0;
        my $a = $acl_stats{$acl}{Allowed} || 0;
        my $t = $b + $a;

        # APPLY ACL FILTERS
        if ($show_acl && $show_acl ne '' && $acl ne $show_acl) {
            next;
        }

        # APPLY FILTERS OF TYPE
        if ($show_blocked && !$show_allowed && $b == 0) {
            next;
        }
        if ($show_allowed && !$show_blocked && $a == 0) {
            next;
        }

        $has_visible_rows = 1;

        print "<tr>";
        print "<td style='padding: 8px;'><strong>$acl</strong></td>";
        print "<td style='padding: 8px; text-align: center; color: #dc3545;'><strong>$b</strong></td>";
        print "<td style='padding: 8px; text-align: center; color: #28a745;'><strong>$a</strong></td>";
        print "<td style='padding: 8px; text-align: center;'><strong>$t</strong></td>";
        print "</tr>";
        
        # Show blocked URLs for this ACL
        if ($b > 0 && exists $acl_stats{$acl}{urls}{Blocked}) {
            my @blocked_urls = @{ $acl_stats{$acl}{urls}{Blocked} };
            
            # If the search is for a DOMAIN, filter URLs
            # If the search is for an IP address, show all URLs associated with that IP address
            if ($search_query && $search_query ne '' && !$search_is_ip) {
                @blocked_urls = grep { /\Q$search_query\E/i } @blocked_urls;
            }
            
            if (@blocked_urls) {
                print "<tr style='background: #fff5f5;'>";
                print "<td colspan='4' style='padding: 10px; font-size: 12px;'>";
                print "<strong style='color: #dc3545;'>Blocked URLs:</strong><br>";
                my %url_count = ();
                foreach my $url (@blocked_urls) {
                    $url_count{$url}++;
                }
                foreach my $url (sort { $url_count{$b} <=> $url_count{$a} } keys %url_count) {
                    print "• $url (" . $url_count{$url} . "x)<br>";
                }
                print "</td>";
                print "</tr>";
            }
        }
        
        # Show allowed URLs for this ACL
        if ($a > 0 && exists $acl_stats{$acl}{urls}{Allowed}) {
            my @allowed_urls = @{ $acl_stats{$acl}{urls}{Allowed} };
            
            # If the search is for a DOMAIN, filter URLs
            # If the search is for an IP address, show all URLs associated with that IP address
            if ($search_query && $search_query ne '' && !$search_is_ip) {
                @allowed_urls = grep { /\Q$search_query\E/i } @allowed_urls;
            }
            
            if (@allowed_urls) {
                print "<tr style='background: #f5fff5;'>";
                print "<td colspan='4' style='padding: 10px; font-size: 12px;'>";
                print "<strong style='color: #28a745;'>Allowed URLs:</strong><br>";
                my %url_count = ();
                foreach my $url (@allowed_urls) {
                    $url_count{$url}++;
                }
                foreach my $url (sort { $url_count{$b} <=> $url_count{$a} } keys %url_count) {
                    print "• $url (" . $url_count{$url} . "x)<br>";
                }
                print "</td>";
                print "</tr>";
            }
        }
    }

    if (!$has_visible_rows) {
        print "<tr><td colspan='4' style='padding: 15px; text-align: center; color: #6c757d;'>";
        print "No data matches the current filters for this client";
        print "</td></tr>";
    }

    print "</tbody></table>";
    print "</div>";
    print "</details>";
}

# JavaScript for expandable rows
print <<'ENDJS';
<script>
document.querySelectorAll('.ip-row').forEach(function(row) {
    row.addEventListener('click', function() {
        var ip = row.getAttribute('data-ip');
        var details = document.getElementById('details-' + ip);
        
        if (details) {
            if (details.style.display === 'none' || details.style.display === '') {
                // Hide all other details first
                document.querySelectorAll('.details-row').forEach(function(r) {
                    r.style.display = 'none';
                });
                // Show this one
                details.style.display = 'table-row';
            } else {
                details.style.display = 'none';
            }
        }
    });
});
</script>
ENDJS

# JavaScript for ACL filtering
print <<'ENDJS2';
<script>
function filterByACL() {
    var selectedACL = document.getElementById('aclFilter').value;

    document.querySelectorAll('.details-row').forEach(function(detailsRow) {
        var rows = detailsRow.querySelectorAll("table tr[data-acl]");
        var anyVisible = false;

        rows.forEach(function(row) {
            var acl = row.getAttribute("data-acl");
            if (!selectedACL || acl === selectedACL) {
                row.style.display = "";
                anyVisible = true;
            } else {
                row.style.display = "none";
            }
        });

        // Hide the entire block if there are no matches
        detailsRow.style.display = anyVisible ? "table-row" : "none";
    });
}
</script>
ENDJS2


print "</div>"; # End dashboard-container

# Auto-refresh JavaScript
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

sub format_number {
    my ($num) = @_;
    $num = 0 unless defined $num;
    $num =~ s/(\d)(?=(\d{3})+(?!\d))/$1,/g;
    return $num;
}
INDEXCGI
    
    chmod +x "$MODDIR/index.cgi"
    
    # ============================================================
    # 2. pdf_report.cgi (PDF Report Generator)
    # ============================================================
    
    cat > "$MODDIR/pdf_report.cgi" <<'PDFCGI'
#!/usr/bin/perl
# PDF Report Generator for Proxy Monitor - Traffic Report Version
use strict;
use warnings;

do '../web-lib.pl';
do '../ui-lib.pl';
&init_config();
&ReadParse();

our $module_name;
our %text;
our %config;
our %in;

# Load language and config
&load_language($module_name);
&read_file("$ENV{'WEBMIN_CONFIG'}/$module_name/config", \%config);

# Get configuration values
my $log_file = $config{'squid_log'} || '/var/log/squid/access.log';
my $max_lines = $in{'max_lines'} || $config{'max_lines'} || '50000';
my $time_range = $in{'time_range'} || $config{'time_range'} || '24';
# Adjust lines to read based on time range for better performance
if ($time_range > 168) { # More than 7 days
    $max_lines = 100000; # Read more lines for historical data
}
my $time_range = $in{'time_range'} || $config{'time_range'} || '24';
my $specific_client = $in{'client_ip'} || '';

# Calculate time threshold
my $time_threshold = time() - ($time_range * 3600);

# Parse log file
my %client_data = ();
my %stats = ( total_requests => 0, blocked_requests => 0, allowed_requests => 0 );
my %domain_stats = ();
my %hourly_stats = ();
my %client_traffic = ();

# Read log lines
my $lines_to_read = int($max_lines);
my @log_lines = ();

if (open(my $fh, '<', $log_file)) {
    seek($fh, 0, 2);
    my $file_size = tell($fh);
    my $chunk_size = 8192;
    my $buffer = '';
    my $lines_found = 0;
    
    while ($file_size > 0 && $lines_found < $lines_to_read) {
        my $read_size = $chunk_size;
        $read_size = $file_size if $file_size < $chunk_size;
        $file_size -= $read_size;
        
        seek($fh, $file_size, 0);
        read($fh, my $chunk, $read_size);
        $buffer = $chunk . $buffer;
        
        my @lines = split(/\n/, $buffer);
        $buffer = shift(@lines) if $file_size > 0;
        
        unshift(@log_lines, @lines);
        $lines_found = scalar(@log_lines);
    }
    close($fh);
    
    @log_lines = splice(@log_lines, -$lines_to_read) if scalar(@log_lines) > $lines_to_read;
}

# Process each log line
foreach my $line (@log_lines) {
    next unless $line =~ /^(\d+\.\d+)\s+\S+\s+(\S+)\s+(\S+)\s+\S+\s+\S+\s+(https?:\/\/)?([^\s\/]+)([^\s]*)/;

    my $timestamp = int($1);
    my $client = $2;
    my $action_code = $3;
    my $domain = $5;

    # Skip if outside time range or if filtering by specific client
    next if $timestamp < $time_threshold;
    next if $specific_client && $client ne $specific_client;

    $stats{total_requests}++;

    my $is_blocked = ($action_code =~ /^TCP_DENIED/) ? 'Blocked' : 'Allowed';
    
    if ($is_blocked eq 'Blocked') {
        $stats{blocked_requests}++;
    } else {
        $stats{allowed_requests}++;
    }

    # Store client traffic data
    $client_traffic{$client}{total}++;
    $client_traffic{$client}{$is_blocked}++;
    
    # Store domain statistics (for all traffic)
    $domain_stats{$domain}{total}++;
    $domain_stats{$domain}{$is_blocked}++;
    $domain_stats{$domain}{clients}{$client}++;
    
    # Hourly statistics
    my ($hour) = (localtime($timestamp))[2];
    $hourly_stats{$hour}{total}++;
    $hourly_stats{$hour}{$is_blocked}++;
}

# Generate Traffic PDF Report
print "Content-Type: text/html\n\n";
print << 'HTMLHEAD';
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Proxy Monitor - Traffic Report</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            margin: 20px;
            color: #000000;
            font-size: 12px;
        }
        .header { 
            text-align: center; 
            border-bottom: 2px solid #333;
            padding-bottom: 10px;
            margin-bottom: 20px;
        }
        .summary { 
            background: #f5f5f5; 
            padding: 15px; 
            margin-bottom: 20px;
            border-radius: 5px;
        }
        table { 
            width: 100%; 
            border-collapse: collapse; 
            margin-bottom: 20px;
        }
        th { 
            background: #333; 
            color: white; 
            padding: 8px; 
            text-align: left;
            border: 1px solid #555;
        }
        td { 
            padding: 8px; 
            border: 1px solid #ddd;
            vertical-align: top;
        }
        .client-section { 
            margin-bottom: 30px; 
            page-break-inside: avoid;
        }
        .blocked { color: #dc2626; font-weight: bold; }
        .allowed { color: #10b981; font-weight: bold; }
        .traffic { color: #3b82f6; font-weight: bold; }
        .section-title { 
            background: #4b5563; 
            color: white; 
            padding: 10px; 
            margin: 20px 0 10px 0;
            border-radius: 4px;
        }
        @media print {
            body { margin: 0; }
            .no-print { display: none; }
        }
    </style>
</head>
<body>
    <div class="header">
HTMLHEAD

if ($specific_client) {
    print "<h1>Proxy Monitor - Client Traffic Report: $specific_client</h1>";
    print "<p>Generated on: " . scalar(localtime) . "</p>";
    print "<p>Time Period: Last 24 hours</p>";
} else {
    my $time_label = "Last $time_range hours";
    if ($time_range == 24) {
        $time_label = "Last 24 Hours";
    } elsif ($time_range == 168) {
        $time_label = "Last 7 Days";
    } elsif ($time_range == 720) {
        $time_label = "Last 30 Days";
    }
    print "<h1>Proxy Monitor - Historical Traffic Report</h1>";
    print "<p>Generated on: " . scalar(localtime) . "</p>";
    print "<p>Time Period: $time_label</p>";
}
print "</div>";

print "<div class='summary'>";
print "<h2>📊 Traffic Summary</h2>";
print "<p><strong>Total Requests:</strong> <span class='traffic'>" . format_number($stats{total_requests}) . "</span></p>";
print "<p><strong>Allowed Requests:</strong> <span class='allowed'>" . format_number($stats{allowed_requests}) . " (" . sprintf("%.1f", ($stats{allowed_requests}/$stats{total_requests})*100) . "%)</span></p>";
print "<p><strong>Blocked Requests:</strong> <span class='blocked'>" . format_number($stats{blocked_requests}) . " (" . sprintf("%.1f", ($stats{blocked_requests}/$stats{total_requests})*100) . "%)</span></p>";
print "<p><strong>Unique Clients:</strong> " . format_number(scalar(keys %client_traffic)) . "</p>";
print "</div>";

print "<div class='no-print' style='margin-bottom: 20px; padding: 10px; background: #ffeb3b; border-radius: 5px;'>";
print "<strong>Print Instructions:</strong> Use your browser's print function (Ctrl+P) and select \"Save as PDF\" to generate a PDF file.";
print "</div>";

# Show different content based on report type
if ($specific_client) {
    # CLIENT-SPECIFIC REPORT
    print "<div class='section-title'>👤 Client Details: $specific_client</div>";
    
    if (exists $client_traffic{$specific_client}) {
        my $client_total = $client_traffic{$specific_client}{total} || 0;
        my $client_blocked = $client_traffic{$specific_client}{Blocked} || 0;
        my $client_allowed = $client_traffic{$specific_client}{Allowed} || 0;
        
        print "<table>";
        print "<tr><th>Metric</th><th>Count</th><th>Percentage</th></tr>";
        print "<tr><td>Total Requests</td><td class='traffic'>" . format_number($client_total) . "</td><td>100%</td></tr>";
        print "<tr><td>Allowed</td><td class='allowed'>" . format_number($client_allowed) . "</td><td>" . sprintf("%.1f", ($client_allowed/$client_total)*100) . "%</td></tr>";
        print "<tr><td>Blocked</td><td class='blocked'>" . format_number($client_blocked) . "</td><td>" . sprintf("%.1f", ($client_blocked/$client_total)*100) . "%</td></tr>";
        print "</table>";
        
        # Top domains for this client
        print "<div class='section-title'>🌐 Top Visited Domains</div>";
        print "<table>";
        print "<tr><th>Domain</th><th>Visits</th><th>Status</th></tr>";
        
        my $domain_count = 0;
        foreach my $domain (sort { ($domain_stats{$b}{total} || 0) <=> ($domain_stats{$a}{total} || 0) } keys %domain_stats) {
            next unless exists $domain_stats{$domain}{clients}{$specific_client};
            last if $domain_count++ >= 15;
            my $visits = $domain_stats{$domain}{total} || 0;
            my $blocked = $domain_stats{$domain}{Blocked} || 0;
            my $status = $blocked > 0 ? "<span class='blocked'>Blocked</span>" : "<span class='allowed'>Allowed</span>";
            print "<tr><td>$domain</td><td>" . format_number($visits) . "</td><td>$status</td></tr>";
        }
        print "</table>";
    }
    
} else {
    # GENERAL TRAFFIC REPORT
    
    # Top Domains
    print "<div class='section-title'>🌐 Top 15 Most Visited Domains</div>";
    print "<table>";
    print "<tr><th>Domain</th><th>Total Visits</th><th>Allowed</th><th>Blocked</th><th>Unique Clients</th></tr>";
    
    my $domain_count = 0;
    foreach my $domain (sort { ($domain_stats{$b}{total} || 0) <=> ($domain_stats{$a}{total} || 0) } keys %domain_stats) {
        last if $domain_count++ >= 15;
        my $total = $domain_stats{$domain}{total} || 0;
        my $allowed = $domain_stats{$domain}{Allowed} || 0;
        my $blocked = $domain_stats{$domain}{Blocked} || 0;
        my $unique_clients = scalar(keys %{$domain_stats{$domain}{clients} || {}});
        print "<tr>";
        print "<td>$domain</td>";
        print "<td>" . format_number($total) . "</td>";
        print "<td class='allowed'>" . format_number($allowed) . "</td>";
        print "<td class='blocked'>" . format_number($blocked) . "</td>";
        print "<td>$unique_clients</td>";
        print "</tr>";
    }
    print "</table>";
    
    # Hourly Traffic
    print "<div class='section-title'>🕒 Traffic by Hour</div>";
    print "<table>";
    print "<tr><th>Hour</th><th>Total</th><th>Allowed</th><th>Blocked</th><th>Block Rate</th></tr>";
    foreach my $hour (sort { $a <=> $b } keys %hourly_stats) {
        my $total = $hourly_stats{$hour}{total} || 0;
        my $allowed = $hourly_stats{$hour}{Allowed} || 0;
        my $blocked = $hourly_stats{$hour}{Blocked} || 0;
        my $block_rate = $total > 0 ? sprintf("%.1f", ($blocked/$total)*100) : 0;
        print "<tr>";
        print "<td>$hour:00 - $hour:59</td>";
        print "<td>" . format_number($total) . "</td>";
        print "<td class='allowed'>" . format_number($allowed) . "</td>";
        print "<td class='blocked'>" . format_number($blocked) . "</td>";
        print "<td>$block_rate%</td>";
        print "</tr>";
    }
    print "</table>";
    
    # Top Clients
    print "<div class='section-title'>👥 Top 15 Clients by Traffic</div>";
    print "<table>";
    print "<tr><th>Client IP</th><th>Total</th><th>Allowed</th><th>Blocked</th><th>Block Rate</th></tr>";
    
    my $client_count = 0;
    foreach my $client (sort { ($client_traffic{$b}{total} || 0) <=> ($client_traffic{$a}{total} || 0) } keys %client_traffic) {
        last if $client_count++ >= 15;
        my $total = $client_traffic{$client}{total} || 0;
        my $allowed = $client_traffic{$client}{Allowed} || 0;
        my $blocked = $client_traffic{$client}{Blocked} || 0;
        my $block_rate = $total > 0 ? sprintf("%.1f", ($blocked/$total)*100) : 0;
        print "<tr>";
        print "<td>$client</td>";
        print "<td>" . format_number($total) . "</td>";
        print "<td class='allowed'>" . format_number($allowed) . "</td>";
        print "<td class='blocked'>" . format_number($blocked) . "</td>";
        print "<td>$block_rate%</td>";
        print "</tr>";
    }
    print "</table>";
}

print << 'HTMLFOOT';
</body>
</html>
HTMLFOOT

sub format_number {
    my ($num) = @_;
    $num = 0 unless defined $num;
    $num =~ s/(\d)(?=(\d{3})+(?!\d))/$1,/g;
    return $num;
}
PDFCGI
    
    chmod +x "$MODDIR/pdf_report.cgi"
    
    # ============================================================
    # 3. module.info (English)
    # ============================================================
    cat > "$MODDIR/module.info" <<'EOF'
desc=Proxy Monitor
longdesc=Monitor Proxy Logs and ACL Blocks
category=servers
os_support=*-linux
version=1.1
depends=webmin
defaultconfig=1
EOF
    
    # ============================================================
    # 4. module.info.es (Spanish)
    # ============================================================
    cat > "$MODDIR/module.info.es" <<'EOF'
desc=Monitor de Proxy
longdesc=Monitorear Logs del Proxy y Bloqueos de ACL
category=servers
os_support=*-linux
version=1.1
depends=webmin
defaultconfig=1
EOF
    
    # ============================================================
    # 5. lang/en (English strings)
    # ============================================================
    cat > "$MODDIR/lang/en" <<'EOF'
index_title=Proxy Monitor
index=Webmin Index
stat_total_requests=Total Requests
stat_blocked=Blocked
stat_allowed=Allowed
stat_clients=Unique Clients
stat_last=Last
stat_hours=hours
stat_of_total=of total
stat_unique_clients=unique clients
acl_stats_title=ACL Statistics
acl_name=ACL Name
acl_type=Type
acl_blocks=Blocks
acl_percentage=Percentage
acl_activity=Activity
acl_no_blocks=No blocks recorded for configured ACLs in this time period
top_blocked_title=Top Blocked Domains
top_allowed_title=Top Allowed Domains
top_clients_title=Top Blocked Clients
domain=Domain
blocks=Blocks
requests=Requests
client_ip=Client IP
total=Total
blocked=Blocked
blocked_percent=Blocked %
blocked_count=Blocked Count
no_blocks=No blocked requests in this time period
no_allowed=No allowed requests in this time period
no_clients=No client data available
hourly_activity_title=Requests Over Time
blocked_by_ip_title=Traffic by Client IP (Click to Expand)
click_to_expand=click to expand
datetime=Date/Time
domain_or_ip=Domain/IP
no_denied_events=No TCP_DENIED events recorded in this time period
no_log_data=No log data available
error_log_not_found=Squid log file not found
error_log_path=Expected path
config_title=Squid Monitor Configuration
config_header=Module Configuration
config_squid_log=Squid log file path
config_max_lines=Maximum lines to parse
config_max_lines_help=Number of log lines to read (more lines = more data but slower)
config_time_range=Time range (hours)
config_time_range_help=Only show requests from the last X hours
config_acl_list=ACL Files to Monitor
config_acl_list_help=One per line. File format: /path/to/acl.txt=Label Name. Regex format: regex:pattern=Label Name
config_acl_example=Example: /etc/squid/acl/social_media.txt=Social Media
config_acl_regex_example=Regex example: regex:^(http|https)://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+=Block IPv4
config_auto_refresh=Enable auto-refresh
config_refresh_interval=Refresh interval (seconds)
config_refresh_help=Minimum recommended: 60 seconds
config_save=Save Configuration
config_saved=Configuration saved successfully
traffic_distribution=Traffic Distribution
traffic_by_ip=Traffic by Client IP (Click to Expand)
EOF
    
    # ============================================================
    # 6. lang/es (Spanish strings)
    # ============================================================
    cat > "$MODDIR/lang/es" <<'EOF'
index_title=Monitor del Proxy
index=Índice de Webmin
stat_total_requests=Peticiones Totales
stat_blocked=Bloqueadas
stat_allowed=Permitidas
stat_clients=Clientes Únicos
stat_last=Últimas
stat_hours=horas
stat_of_total=del total
stat_unique_clients=clientes únicos
acl_stats_title=Estadísticas de ACL
acl_name=Nombre de ACL
acl_type=Tipo
acl_blocks=Bloqueos
acl_percentage=Porcentaje
acl_activity=Actividad
acl_no_blocks=No se registraron bloqueos para las ACL configuradas en este período
top_blocked_title=Dominios Más Bloqueados
top_allowed_title=Dominios Más Permitidos
top_clients_title=Principales Clientes
domain=Dominio
blocks=Bloqueos
requests=Peticiones
client_ip=IP del Cliente
total=Total
blocked=Bloqueadas
blocked_percent=% Bloqueadas
blocked_count=Cantidad Bloqueada
no_blocks=No hay peticiones bloqueadas en este período
no_allowed=No hay peticiones permitidas en este período
no_clients=No hay datos de clientes disponibles
hourly_activity_title=Peticiones en el Tiempo
blocked_by_ip_title=Tráfico por IP de Cliente (Clic para Expandir)
click_to_expand=clic para expandir
datetime=Fecha/Hora
domain_or_ip=Dominio/IP
no_denied_events=No hay eventos TCP_DENIED registrados en este período
no_log_data=No hay datos de log disponibles
error_log_not_found=Archivo de log de Squid no encontrado
error_log_path=Ruta esperada
config_title=Configuración del Monitor de Squid
config_header=Configuración del Módulo
config_squid_log=Ruta del archivo de log de Squid
config_max_lines=Máximo de líneas a procesar
config_max_lines_help=Número de líneas del log a leer (más líneas = más datos pero más lento)
config_time_range=Rango de tiempo (horas)
config_time_range_help=Solo mostrar peticiones de las últimas X horas
config_acl_list=Archivos ACL a Monitorear
config_acl_list_help=Uno por línea. Formato archivo: /ruta/a/acl.txt=Nombre Etiqueta. Formato regex: regex:patrón=Nombre Etiqueta
config_acl_example=Ejemplo: /etc/squid/acl/redes_sociales.txt=Redes Sociales
config_acl_regex_example=Ejemplo regex: regex:^(http|https)://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+=Bloquear IPv4
config_auto_refresh=Activar auto-actualización
config_refresh_interval=Intervalo de actualización (segundos)
config_refresh_help=Mínimo recomendado: 60 segundos
config_save=Guardar Configuración
config_saved=Configuración guardada exitosamente
traffic_distribution=Distribución del Tráfico
traffic_by_ip=Tráfico por IP de Cliente (Clic para Expandir)
EOF
    
    # ============================================================
    # 7. config.info (Webmin native configuration)
    # ============================================================
    cat > "$MODDIR/config.info" <<'EOF'
squid_log=Squid log file path,0,/var/log/squid/access.log
max_lines=Maximum lines to parse,3,50000
time_range=Time range in hours,0,720
acl_list=ACL files to monitor (one per line: path=label or regex:pattern=label),9,50,8,\t
auto_refresh=Auto-refresh,1,1-Enabled,0-Disabled
refresh_interval=Refresh interval (seconds),0,60
EOF
    
    # ============================================================
    # 8. config.info.es (Spanish)
    # ============================================================
    cat > "$MODDIR/config.info.es" <<'EOF'
squid_log=Ruta del archivo de log de Squid,0,/var/log/squid/access.log
max_lines=Máximo de líneas a procesar,3,50000
time_range=Rango de tiempo en horas,0,720
acl_list=Archivos ACL a monitorear (uno por línea: ruta=etiqueta o regex:patrón=etiqueta),9,50,8,\t
auto_refresh=Auto-actualización,1,1-Activado,0-Desactivado
refresh_interval=Intervalo de actualización (segundos),0,60
EOF
    
    # ============================================================
    # 9. defaultconfig (default configuration with 3 ACLs)
    # ============================================================
    cat > "$MODDIR/defaultconfig" <<'EOF'
squid_log=/var/log/squid/access.log
max_lines=50000
time_range=24
acl_list=/etc/squid/acl/blocktlds.txt=Blocked TLD	/etc/squid/acl/blockdomains.txt=Blocked Sites	regex:^(http|https)://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+=Block IPv4
auto_refresh=0
refresh_interval=60
EOF
    
    # ============================================================
    # 10. config (current configuration with 3 ACLs)
    # ============================================================
    cat > "$ETCDIR/config" <<'EOF'
squid_log=/var/log/squid/access.log
max_lines=50000
time_range=24
acl_list=/etc/squid/acl/blocktlds.txt=Blocked TLD	/etc/squid/acl/blockdomains.txt=Blocked Sites	regex:^(http|https)://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+=Block IPv4
auto_refresh=0
refresh_interval=60
EOF
    
    # ============================================================
    # 11. squidmon-lib.pl (module library)
    # ============================================================
    cat > "$MODDIR/squidmon-lib.pl" <<'EOF'
#!/usr/bin/perl
# Squid Monitor library functions

do '../web-lib.pl';
do '../ui-lib.pl';
&init_config();

1;
EOF
    
    chmod +x "$MODDIR/squidmon-lib.pl"
    
    # ============================================================
    # 12. install_check.pl (installation verification)
    # ============================================================
    cat > "$MODDIR/install_check.pl" <<'EOF'
#!/usr/bin/perl
# Check if Squid log file exists

do '../web-lib.pl';

sub module_install_check {
    my $log_file = '/var/log/squid/access.log';
    if (!-f $log_file && !-d '/var/log/squid') {
        return "Squid does not appear to be installed (log directory not found)";
    }
    return undef;
}
EOF
    
    chmod +x "$MODDIR/install_check.pl"
    
    # ============================================================
    # 13. help/intro.html (English help)
    # ============================================================
    cat > "$MODDIR/help/intro.html" <<'EOF'
<header>Squid Monitor</header>

<h3>Introduction</h3>
<p>The Proxy Monitor module provides a dashboard for monitoring your Squid proxy server. It focuses on blocked requests (TCP_DENIED) and provides detailed statistics about ACL activity.</p>

<h3>Features</h3>
<ul>
<li>Real-time statistics from Squid access logs</li>
<li>Monitor TCP_DENIED (blocked) requests</li>
<li>Track multiple ACL files and their block counts</li>
<li>Support for file-based and regex-based ACLs</li>
<li>Detailed blocked requests by client IP with expandable details</li>
<li>Top blocked domains and clients</li>
<li>Configurable time ranges and auto-refresh</li>
<li>Zero external dependencies (pure Perl parsing)</li>
</ul>

<h3>Configuration</h3>
<p>In the module configuration, you can customize:</p>
<ul>
<li><b>Log file path:</b> Location of Squid's access.log (default: /var/log/squid/access.log)</li>
<li><b>Lines to parse:</b> How many log lines to read (default: 50,000)</li>
<li><b>Time range:</b> Only show requests from last X hours (default: 24)</li>
<li><b>ACL files:</b> List of ACL files to monitor with custom labels</li>
<li><b>Auto-refresh:</b> Automatically reload the dashboard every X seconds</li>
</ul>

<h3>ACL Monitoring</h3>
<p>You can monitor two types of ACLs:</p>

<h4>File-based ACLs</h4>
<p>Format:</p>
<pre>/path/to/acl.txt=Label Name</pre>
<p>Example:</p>
<pre>/etc/squid/acl/social_media.txt=Social Media
/etc/squid/acl/streaming.txt=Streaming Sites
/etc/squid/acl/adult_content.txt=Adult Content</pre>

<h4>Regex-based ACLs</h4>
<p>Format:</p>
<pre>regex:pattern=Label Name</pre>
<p>Example:</p>
<pre>regex:^(http|https)://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+=Block IPv4
regex:.*\.(exe|msi|dmg)$=Executable Files</pre>

<p>The dashboard will show how many blocks each ACL generated and identify which ACL blocked each request.</p>

<h3>Blocked Requests Detail View</h3>
<p>The "Blocked Requests by Client IP" section shows all clients with blocked requests. Click on any client IP to expand and see:</p>
<ul>
<li>Date and time of each blocked request</li>
<li>Domain or IP that was blocked</li>
<li>Which ACL performed the block</li>
</ul>

<h3>Performance Notes</h3>
<ul>
<li>Parsing is done in real-time when you load the page</li>
<li>Large log files may take a few seconds to parse</li>
<li>Adjust "Lines to parse" if the page loads slowly</li>
<li>Squid automatically rotates logs, so access.log stays manageable</li>
<li>Regex ACLs are slightly slower than file-based ACLs</li>
</ul>

<footer>
EOF
    
    # ============================================================
    # 14. help/intro.es.html (Spanish help)
    # ============================================================
    cat > "$MODDIR/help/intro.es.html" <<'EOF'
<header>Monitor de Squid</header>

<h3>Introducción</h3>
<p>El módulo Monitor de Proxy proporciona un dashboard para monitorear su servidor proxy Squid. Se enfoca en peticiones bloqueadas (TCP_DENIED) y proporciona estadísticas detalladas sobre la actividad de las ACL.</p>

<h3>Características</h3>
<ul>
<li>Estadísticas en tiempo real desde los logs de Squid</li>
<li>Monitoreo de peticiones TCP_DENIED (bloqueadas)</li>
<li>Seguimiento de múltiples archivos ACL y sus conteos de bloqueos</li>
<li>Soporte para ACLs basadas en archivos y regex</li>
<li>Peticiones bloqueadas detalladas por IP de cliente con detalles expandibles</li>
<li>Dominios y clientes más bloqueados</li>
<li>Rangos de tiempo configurables y auto-actualización</li>
<li>Cero dependencias externas (parsing puro en Perl)</li>
</ul>

<h3>Configuración</h3>
<p>En la configuración del módulo, puede personalizar:</p>
<ul>
<li><b>Ruta del archivo de log:</b> Ubicación del access.log de Squid (predeterminado: /var/log/squid/access.log)</li>
<li><b>Líneas a procesar:</b> Cuántas líneas del log leer (predeterminado: 50,000)</li>
<li><b>Rango de tiempo:</b> Solo mostrar peticiones de las últimas X horas (predeterminado: 24)</li>
<li><b>Archivos ACL:</b> Lista de archivos ACL a monitorear con etiquetas personalizadas</li>
<li><b>Auto-actualización:</b> Recargar automáticamente el dashboard cada X segundos</li>
</ul>

<h3>Monitoreo de ACL</h3>
<p>Puede monitorear dos tipos de ACLs:</p>

<h4>ACLs basadas en archivos</h4>
<p>Formato:</p>
<pre>/ruta/a/acl.txt=Nombre Etiqueta</pre>
<p>Ejemplo:</p>
<pre>/etc/squid/acl/redes_sociales.txt=Redes Sociales
/etc/squid/acl/streaming.txt=Sitios de Streaming
/etc/squid/acl/contenido_adulto.txt=Contenido Adulto</pre>

<h4>ACLs basadas en regex</h4>
<p>Formato:</p>
<pre>regex:patrón=Nombre Etiqueta</pre>
<p>Ejemplo:</p>
<pre>regex:^(http|https)://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+=Bloquear IPv4
regex:.*\.(exe|msi|dmg)$=Archivos Ejecutables</pre>

<p>El dashboard mostrará cuántos bloqueos generó cada ACL e identificará qué ACL bloqueó cada petición.</p>

<h3>Vista Detallada de Peticiones Bloqueadas</h3>
<p>La sección "Peticiones Bloqueadas por IP de Cliente" muestra todos los clientes con peticiones bloqueadas. Haga clic en cualquier IP de cliente para expandir y ver:</p>
<ul>
<li>Fecha y hora de cada petición bloqueada</li>
<li>Dominio o IP que fue bloqueado</li>
<li>Qué ACL realizó el bloqueo</li>
</ul>

<h3>Notas de Rendimiento</h3>
<ul>
<li>El análisis se hace en tiempo real cuando carga la página</li>
<li>Archivos de log grandes pueden tardar unos segundos en procesarse</li>
<li>Ajuste "Líneas a procesar" si la página carga lentamente</li>
<li>Squid rota los logs automáticamente, así que access.log se mantiene manejable</li>
<li>Las ACLs regex son ligeramente más lentas que las ACLs basadas en archivos</li>
</ul>

<footer>
EOF
    
    # ============================================================
    # 15. CHANGELOG
    # ============================================================
    cat > "$MODDIR/CHANGELOG" <<'EOF'
Version 1.1 (2024)
- Added support for regex-based ACLs (regex:pattern=Label)
- New "Blocked Requests by Client IP" section with expandable details
- Shows which ACL blocked each request
- Multiple ACLs now properly supported (tab/newline separated)
- Improved ACL matching for both file and regex types
- Better identification of blocking ACL per request
- Enhanced UI with clickable IP rows

Version 1.0 (2024)
- Initial release
- Dashboard for Squid proxy
- Real-time log parsing (no database required)
- TCP_DENIED request monitoring
- Configurable ACL tracking
- Top blocked domains and clients
- Hourly statistics
- Multi-language support (English and Spanish)
- Auto-refresh capability
- Zero external dependencies
EOF
    
    # ============================================================
    # 16. Create icon.gif (updated Squid icon - base64 encoded)
    # ============================================================
    cat > /tmp/squid_icon.gif.b64 << 'ICONEOF'
R0lGODlhMAAwAPAAAAAAAAAAACH5BAEAAAAALAAAAAAwADAAAALIhI+py+0Po5xUhouz3jzUDobbdFUQFpXm6bHrgaKA+qiiDMdyW/Or3qI5hK8FsXEsGpLIm3NEekp9LKoS17Mql1oF08KzdRPiGxkYTAWd59JujPiqYTnw1iuPY4sZylTqt/fSZ3enB1dneDY3w1bYw2WG92SEmAXYNpinN/ljyTn5hxNGytUkupbYaKq46tqY+mooFhm7GchKSNu6qxurWJar07qq4dp3GwXrtsZMHHy8C/xLIz0bpmp9l8w6/dntjUm8LDleVAAAOw==
ICONEOF
    
    base64 -d /tmp/squid_icon.gif.b64 > "$MODDIR/images/icon.gif"
    rm -f /tmp/squid_icon.gif.b64
    
    # ============================================================
    # 17. Set correct permissions
    # ============================================================
    chown -R root:root "$MODDIR" "$ETCDIR"
    chmod -R 755 "$MODDIR"
    chmod 644 "$MODDIR"/*.info* "$MODDIR/lang/"* "$MODDIR/help/"* "$MODDIR/CHANGELOG" 2>/dev/null || true
    chmod 755 "$MODDIR"/*.cgi "$MODDIR"/*.pl 2>/dev/null || true
    chmod 644 "$MODDIR/images/"* 2>/dev/null || true
    
    # ============================================================
    # 18. Register module in Webmin ACL
    # ============================================================
    if ! grep -q "squidmon" /etc/webmin/webmin.acl 2>/dev/null; then
        sed -i.bak 's/\(^root:.*\)/\1 squidmon/' /etc/webmin/webmin.acl
        echo "✓ Module added to webmin.acl"
    fi
    
    # ============================================================
    # 19. Clear module cache
    # ============================================================
    rm -f /var/webmin/module.infos.cache
    
    # ============================================================
    # 20. Restart Webmin
    # ============================================================
    echo "Restarting Webmin service..."
    systemctl restart webmin.service 2>/dev/null || /etc/webmin/restart 2>/dev/null || true
    
    echo ""
    echo "=========================================="
    echo "✓ Squid Monitor module installed successfully!"
    echo "=========================================="
    echo ""
    echo "Module location: $MODDIR"
    echo "Config location: $ETCDIR"
    echo ""
    echo "Features:"
    echo "  ✓ Dashboard"
    echo "  ✓ TCP_DENIED request monitoring"
    echo "  ✓ File-based and regex-based ACL tracking"
    echo "  ✓ Detailed blocked requests by client IP"
    echo "  ✓ ACL identification per blocked request"
    echo "  ✓ Top blocked domains and clients"
    echo "  ✓ Real-time statistics"
    echo "  ✓ Zero external dependencies"
    echo ""
    echo "Default Configuration (3 ACLs included):"
    echo "  - Log file: /var/log/squid/access.log"
    echo "  - Lines to parse: 50,000"
    echo "  - Time range: Last 24 hours"
    echo "  - ACL 1: /etc/squid/acl/blocktlds.txt = Blocked TLD"
    echo "  - ACL 2: /etc/squid/acl/blockdomains.txt = Blocked Sites"
    echo "  - ACL 3: regex:^(http|https)://[0-9]+.*=Block IPv4 (regex)"
    echo ""
    echo "Next Steps:"
    echo "  1. Log out and log back into Webmin"
    echo "  2. Find the module under 'Servers' category"
    echo "  3. Configure your ACL files in Module Configuration"
    echo "  4. Access: https://localhost:10000/squidmon/"
    echo ""
    echo "ACL Configuration Examples:"
    echo "  File-based: /etc/squid/acl/social_media.txt=Social Media"
    echo "  Regex-based: regex:^(http|https)://[0-9]+\.[0-9]+.*=Block IPv4"
    echo ""
}

# ============================================================
# Function: Uninstall Module
# ============================================================
uninstall_module() {
    echo ""
    echo "=========================================="
    echo "Uninstalling Squid Monitor Module"
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
    
    # Remove from Webmin ACL
    if grep -q "squidmon" /etc/webmin/webmin.acl 2>/dev/null; then
        sed -i.bak 's/ squidmon//g' /etc/webmin/webmin.acl
        echo "✓ Module removed from webmin.acl"
    fi
    
    # Clear module cache
    rm -f /var/webmin/module.infos.cache
    echo "✓ Module cache cleared"
    
    # Restart Webmin
    echo "Restarting Webmin service..."
    systemctl restart webmin.service 2>/dev/null || /etc/webmin/restart 2>/dev/null || true
    
    echo ""
    echo "=========================================="
    echo "✓ Proxy Monitor module uninstalled successfully!"
    echo "=========================================="
    echo ""
}

# ============================================================
# Main Menu
# ============================================================
show_menu() {
    clear
    echo "============================================================"
    echo "          PROXY MONITOR - WEBMIN MODULE"
    echo "              Installation Menu"
    echo "============================================================"
    echo ""
    echo "  1) Install module"
    echo "  2) Uninstall module"
    echo "  3) Exit"
    echo ""
    echo -n "Select an option [1-3]: "
}

# ============================================================
# Show usage information
# ============================================================
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  install      Install the Proxy Monitor module"
    echo "  uninstall    Uninstall the Proxy Monitor module"
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

# ============================================================
# Main execution
# ============================================================
main() {
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        echo "Error: This script must be run as root"
        exit 1
    fi
    
    # Check if Webmin is installed
    if [ ! -d "/usr/share/webmin" ] && [ ! -d "/etc/webmin" ]; then
        echo "Error: Webmin is not installed on this system"
        exit 1
    fi
    
    # Check for command line arguments
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
    
    # Interactive menu mode (no arguments provided)
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

# Run main function
main "$@"
