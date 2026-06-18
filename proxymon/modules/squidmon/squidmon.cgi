#!/usr/bin/perl
# squidmon.cgi
use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

# Escape special HTML characters to prevent XSS.
sub h {
    my ($str) = @_;
    return '' unless defined $str;
    $str =~ s/&/&amp;/g;
    $str =~ s/</&lt;/g;
    $str =~ s/>/&gt;/g;
    $str =~ s/"/&quot;/g;
    $str =~ s/'/&#39;/g;
    return $str;
}
our ($module_name, %text, %config, %in);

# Match $text against a user-supplied regex pattern with a hard time limit,
# so a catastrophic-backtracking ACL pattern (e.g. "(a+)+$") cannot hang
# this CGI process indefinitely.
sub safe_regex_match {
    my ($text, $pattern) = @_;
    my $matched = 0;
    local $@;
    local $SIG{ALRM} = sub { die "regex_timeout\n" };
    eval {
        alarm(2);
        $matched = ($text =~ /$pattern/i) ? 1 : 0;
    };
    alarm(0);
    return 0 if $@;  # timeout or invalid pattern — treat as no match
    return $matched;
}

do '/var/www/proxymon/squidmon/squidmon-standalone.pl';
&init_config();
&ReadParse();

my $config_file = '/var/www/proxymon/squidmon/etc/config';

$module_name = 'squidmon';

# Load language and config
&load_language($module_name);
&read_file($config_file, \%config);
$config{'acl_list'} =~ s/\\n/\n/g if $config{'acl_list'};

# Get configuration values
my $log_file = $config{'squid_log'} || '/var/log/squid/access.log';
my $max_lines = $config{'max_lines'} || '50000';
my $acl_list = $config{'acl_list'} || '';
my $auto_refresh = $config{'auto_refresh'} || '0';
my $refresh_interval = $config{'refresh_interval'} || '60';
my $time_range = $config{'time_range'} || '24';
$time_range = int($time_range) || 24;

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

print "<div style='margin: 20px 0; text-align: right;'>";
print "<a href='config.cgi' style='display: inline-block; padding: 10px 20px; background: #667eea; color: white; text-decoration: none; border-radius: 4px; font-weight: 600;'>⚙️ Configuration</a>";
print "</div>";

my %client_acl_stats = ();
#my %debug_info = ();
# TIME MEASUREMENT VARIABLES
my $search_start_time;
my $search_elapsed_ms = 0;

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

/* MOBILE SCROLL FIXES */
@media (max-width: 768px) {
  .content-card {
    overflow-x: auto;
  }
  .content-card .table-responsive {
    min-width: 600px;
  }
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
#print "<!-- DEBUG: Show monitored ACLs -->\n";
#foreach my $acl (@monitored_acls) {
#    print "<!-- ACL: type=$acl->{type}, label=$acl->{label}, value=$acl->{value} -->\n";
#    if ($acl->{type} eq 'file') {
#        if (-f $acl->{value}) {
#            my $line_count = 0;
#            if (open(my $fh, '<', $acl->{value})) {
#                while (<$fh>) { $line_count++; }
#                close($fh);
#            }
#            print "<!-- FILE EXISTS: $line_count lines -->\n";
#        } else {
#            print "<!-- FILE NOT FOUND: $acl->{value} -->\n";
#        }
#    }
#}
#print "<!-- END DEBUG -->\n";

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
#my $total_domains = scalar(keys %domain_to_acl);
#print "<!-- DEBUG: Total dominios cargados en domain_to_acl: $total_domains -->\n";
#if ($total_domains > 0) {
#    my @sample_domains = (keys %domain_to_acl)[0..4];
#    print "<!-- Sample domains: " . join(", ", @sample_domains) . " -->\n";
#}

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
    my $url = $5 . ($6 // '');

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
        if (safe_regex_match($url, $acl->{value})) {
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
    print "<th style='text-align: left; padding: 12px; width: 15%; color: #000000 !important; border: 1px solid #e5e7eb !important;'>Type</th>";
    print "<th style='text-align: center; padding: 12px; width: 12%; color: #000000 !important; border: 1px solid #e5e7eb !important;'>Count</th>";
    print "<th style='text-align: center; padding: 12px; width: 10%; color: #000000 !important; border: 1px solid #e5e7eb !important;'>Percent</th>";
    print "<th style='padding: 12px; width: 63%; color: #000000 !important; border: 1px solid #e5e7eb !important;'>Distribution</th>";
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
        
        foreach my $acl_label (sort { ($acl_hits{$b} || 0) <=> ($acl_hits{$a} || 0) } keys %acl_hits) {
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
    foreach my $domain (sort { ($blocked_domains{$b} || 0) <=> ($blocked_domains{$a} || 0) } keys %blocked_domains) {
        last if ++$count > 10;
        print "<tr>";
        print "<td>" . h($domain) . "</td>";
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
    print "<th style='text-align: left;'>$text{'client_ip'}</th>";
    print "<th style='text-align: center;'>$text{'blocked'}</th>";
    print "<th style='text-align: center;'>$text{'blocked_percent'}</th>";
    print "<th style='text-align: center;'>$text{'total'}</th>";
    print "</tr></thead><tbody>";
    
    my $count = 0;
    
    foreach my $client (sort { ($clients_data{$b}{blocked} || 0) <=> ($clients_data{$a}{blocked} || 0) } keys %clients_data) {
        last if ++$count > 10;
        my $total = $clients_data{$client}{total} || 0;
        my $blocked = $clients_data{$client}{blocked} || 0;
        my $percent = $total > 0 ? sprintf("%.1f", ($blocked / $total) * 100) : 0;
        
        print "<tr>";
        print "<td style='text-align: left;'><strong>" . h($client) . "</strong></td>";
        print "<td style='text-align: center;'><span class='badge badge-blocked'>" . format_number($blocked) . "</span></td>";
        print "<td style='text-align: center;'>$percent%</td>";
        print "<td style='text-align: center;'>" . format_number($total) . "</td>";
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

# PDF Button - General (Mobile Responsive)
print "<div style='margin-bottom: 20px;'>";
print "<form method='post' action='pdf_report.cgi' target='_blank' style='background: #1f2937; padding: 15px; border-radius: 8px;'>";
print "<div style='display: flex; flex-wrap: wrap; align-items: center; justify-content: center; gap: 15px;'>";

print "<span style='color: white; white-space: nowrap;'>📊 Report Time Range:</span>";
print "<select name='time_range' style='padding: 8px; min-width: 150px;'>";
print "<option value='24'>Last 24 Hours</option>";
print "<option value='168'>Last 7 Days</option>";
print "<option value='720'>Last 30 Days</option>";
print "</select>";
print "<input type='hidden' name='max_lines' value='" . int($max_lines) . "'>";
print "<input type='submit' value='📄 Generate PDF Report' style='background-color: #1f2937; color: #ffffff !important; border: 1px solid #ffffff !important; padding: 8px 15px; white-space: nowrap; cursor: pointer;'>";

print "</div>";
print "</form>";
print "</div>";

# Filter form with ACL menu
my %input = %in;
my $show_acl = $input{'filter_acl'} || '';
my $show_blocked = $input{'filter_blocked'} || '';
my $show_allowed = $input{'filter_allowed'} || '';
my $search_query = $in{'search_query'} || '';

# TIME MEASUREMENT FOR SEARCHES - WITH Time::HiRes
print "<form id='filter-form' method='get' action='#traffic-by-ip' style='margin-bottom: 20px; padding: 20px; background: #1f2937; border-radius: 8px; color: #ffffff; box-shadow: 0 0 6px rgba(0,0,0,0.3); border: 1px solid #ffffff; display: flex; align-items: center; gap: 15px; flex-wrap: wrap;'>";
print "<div><strong>Filters:</strong></div>";
print "<div>";
print "<label style='color: #ffffff;'>ACL: </label>";
print "<select name='filter_acl' style='width:200px;'>";
print "<option value=''>-- All ACLs --</option>";
foreach my $acl (@monitored_acls) {
    my $label = $acl->{label};
    my $sel = ($label eq $show_acl) ? "selected" : "";
    print "<option value='".h($label)."' $sel>".h($label)."</option>";
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
print "<input type='text' name='search_query' value='".h($search_query)."' placeholder='IP or domain...' style='width: 250px; padding: 5px; margin-left: 5px;'>";
print "<input type='submit' name='search' value='Search' style='background-color: #1f2937; color: #ffffff !important; border: 1px solid #ffffff !important; padding: 5px 10px; margin-left: 5px;'>";
print "</div>";

print "<div>";
print "<input type='submit' name='filter_blocked' value='Show Blocked Only' style='background-color: #1f2937; color: #ffffff !important; border: 1px solid #ffffff !important; padding: 5px 10px; margin-right: 10px;'>";
print "<input type='submit' name='filter_allowed' value='Show Allowed Only' style='background-color: #1f2937; color: #ffffff !important; border: 1px solid #ffffff !important; padding: 5px 10px; margin-right: 10px;'>";
my $script_url = $ENV{SCRIPT_NAME} || 'squidmon.cgi';
print "<a href='" . h($script_url) . "' style='color: #ffffff !important; text-decoration: underline; padding: 5px 10px; display: inline-block;'>Clear Filters</a>";
print "</div>";
print "</form>";

# DEBUG: Show loaded ACL information
#print "<!-- DEBUG: " . scalar(@monitored_acls) . " Monitored ACLs -->\n";
#foreach my $acl (@monitored_acls) {
#    print "<!-- ACL: $acl->{type} - $acl->{label} - $acl->{value} -->\n";
#}

# Process logs for client data with improved ACL detection
foreach my $line (@log_lines) {
    next unless $line =~ /^(\d+\.\d+)\s+\S+\s+(\S+)\s+(\S+)\s+\S+\s+\S+\s+(https?:\/\/)?([^\s\/]+)([^\s]*)/;
    
    my $timestamp = int($1);
    my $client = $2;
    my $action_code = $3;
    my $domain = $5;
    my $proto = ($action_code =~ /^CONNECT/) ? 'https://' : ($4 || 'http://');
    my $url = $5 . ($6 // '');
    
    # Skip if outside time range
    next if $timestamp < $time_threshold;
    
    my $is_blocked = ($action_code =~ /^TCP_DENIED/) ? 'Blocked' : 'Allowed';
    
    # DEBUG: Request information
    #$debug_info{total_requests}++;
    #$debug_info{"$client-$is_blocked"}++;
    
    # Determine which ACL matched
    my $matched_acl = 'N/A';
    
    if ($is_blocked eq 'Blocked') {
        my $domain_lc = lc($domain);
        #$debug_info{blocked_requests}++;
        
        # DEBUG
        #$debug_info{domains}{$domain_lc}++;
        
        # REMOVE PORT from domain if it exists
        my $domain_only = $domain_lc;
        $domain_only =~ s/:\d+$//;  # Remove :port
        
        # 1. Search for EXACT match in file ACLs
        my $found_acl = '';
        if (exists $domain_to_acl{$domain_only}) {
            $found_acl = $domain_to_acl{$domain_only};
            #$debug_info{exact_matches}++;
        }
        
        # 2. Search for a SUBDOMAIN match if an exact match was not found
        if (!$found_acl && $domain_only =~ /\./) {
            my @parts = split(/\./, $domain_only);
            # Test from the full domain to the TLD
            for (my $i = 1; $i < scalar(@parts); $i++) {
                my $test_domain = join('.', @parts[$i..$#parts]);
                if (exists $domain_to_acl{$test_domain}) {
                    $found_acl = $domain_to_acl{$test_domain};
                    #$debug_info{subdomain_matches}++;
                    last;
                }
            }
        }
        
        # 3. Search in ACLs regex if not found in files
        if (!$found_acl) {
            foreach my $acl (@regex_acls) {
                if (safe_regex_match($url, $acl->{value})) {
                    $found_acl = $acl->{label};
                    #$debug_info{regex_matches}++;
                    last;
                }
            }
        }
        
        $matched_acl = $found_acl || 'Unknown ACL';
        
    } else {
        # For allowed requests - DO NOT count as an ACL hit
        $matched_acl = 'Allowed Traffic';
        #$debug_info{allowed_requests}++;
    }
    
    # Store ALL unfiltered statistics
        $client_acl_stats{$client}{$matched_acl}{$is_blocked}++;
        $client_acl_stats{$client}{total}{$is_blocked}++;
        push @{ $client_acl_stats{$client}{$matched_acl}{urls}{$is_blocked} }, $url;

        # DEBUG: Register the association
        #$debug_info{acl_matches}{$matched_acl}++;
}

# DEBUG: Show diagnostic information
#print "<!-- DEBUG INFO: -->\n";
#print "<!-- Total requests: $debug_info{total_requests} -->\n";
#print "<!-- Blocked: " . ($debug_info{blocked_requests} || 0) . " -->\n";
#print "<!-- Allowed: " . ($debug_info{allowed_requests} || 0) . " -->\n";
#print "<!-- Exact matches: " . ($debug_info{exact_matches} || 0) . " -->\n";
#print "<!-- Subdomain matches: " . ($debug_info{subdomain_matches} || 0) . " -->\n";
#print "<!-- Regex matches: " . ($debug_info{regex_matches} || 0) . " -->\n";

# Show blocked domains for debugging
#if ($debug_info{domains}) {
#    print "<!-- Blocked domains: " . join(', ', keys %{$debug_info{domains}}) . " -->\n";
#}

# Show ACL matches for debugging
#if ($debug_info{acl_matches}) {
#    print "<!-- ACL Matches: -->\n";
#    foreach my $acl (keys %{$debug_info{acl_matches}}) {
#        print "<!--   $acl: $debug_info{acl_matches}{$acl} -->\n";
#    }
#}

# ============================================================
# SEARCH AND FILTERING
# ============================================================

my @clients_to_show = ();
my $search_is_ip = 0;  # Flag to determine if the search is an IP address

# If there is an active search
if ($search_query && $search_query ne '') {
    $search_query = lc($search_query);  # Convert to lowercase for comparison
    
    # START TIME MEASUREMENT
    my ($start_seconds, $start_microseconds) = gettimeofday();
    $search_start_time = $start_seconds + ($start_microseconds / 1000000);
    
    
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
            # Search in blocked URLs of the client
            foreach my $acl (keys %{$client_acl_stats{$client}}) {
                next if $acl eq 'total' || $acl eq 'urls';
                
                if (exists $client_acl_stats{$client}{$acl}{urls} && exists $client_acl_stats{$client}{$acl}{urls}{Blocked}) {
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
                    
                    if (exists $client_acl_stats{$client}{$acl}{urls} && exists $client_acl_stats{$client}{$acl}{urls}{Allowed}) {
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
    # CALCULATE SEARCH TIME
    my ($end_seconds, $end_microseconds) = gettimeofday();
    my $search_end_time = $end_seconds + ($end_microseconds / 1000000);
    $search_elapsed_ms = sprintf("%.2f", ($search_end_time - $search_start_time) * 1000);
    
    my $results_count = scalar(@clients_to_show);
    my $search_type = $search_is_ip ? "IP Address" : "Domain";
    print "<div style='margin-bottom: 15px; padding: 12px; background: #eff6ff; border-left: 4px solid #3b82f6; border-radius: 4px;'>";
    print "<strong style='color: #1e40af;'>🔍 Search Results ($search_type):</strong> ";
    print "Found <strong style='color: #1e40af;'>$results_count</strong> client(s) matching '<strong>".h($search_query)."</strong>' ";
    print "in <strong style='color: #1e40af;'>$search_elapsed_ms ms</strong>";
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
            # If there is no type filter, or if the data matches
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
    print "<strong>" . h($client) . "</strong> — Total: <strong>$total_requests</strong> | ";
    print "Blocked: <span style='color: #dc3545 !important;'><strong>$total_blocked</strong></span> | ";
    print "Allowed: <span style='color: #28a745 !important;'><strong>$total_allowed</strong></span>";
    
    # PDF Button by IP
    print "<form method='post' action='pdf_report.cgi' target='_blank' style='display: inline; float: right;'>";
    print "<input type='hidden' name='client_ip' value='" . h($client) . "'>";
    print "<input type='hidden' name='time_range' value='$time_range'>";
    print "<input type='hidden' name='max_lines' value='" . int($max_lines) . "'>";
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
        print "<td style='padding: 8px;'><strong>" . h($acl) . "</strong></td>";
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
                foreach my $url (sort { ($url_count{$b} || 0) <=> ($url_count{$a} || 0) } keys %url_count) {
                    print "• " . h($url) . " (" . $url_count{$url} . "x)<br>";
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
                foreach my $url (sort { ($url_count{$b} || 0) <=> ($url_count{$a} || 0) } keys %url_count) {
                    print "• " . h($url) . " (" . $url_count{$url} . "x)<br>";
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

# Auto-refresh JavaScript - SILENT
if ($auto_refresh eq '1') {
    print <<AUTOREFRESH;
<div class='refresh-indicator' id='refreshIndicator'>
🔄 Auto-refresh: <span id='countdown'>$refresh_interval</span>s
</div>

<script>
var refreshInterval = $refresh_interval;
var countdown = refreshInterval;
var countdownElement = document.getElementById('countdown');

function silentRefresh() {
    fetch(window.location.href, {
        method: 'GET',
        cache: 'no-store'
    })
    .then(response => response.text())
    .then(html => {
        var parser = new DOMParser();
        var newDoc = parser.parseFromString(html, 'text/html');
        var newContent = newDoc.querySelector('.dashboard-container');
        var oldContent = document.querySelector('.dashboard-container');
        
        if (newContent && oldContent) {
            oldContent.innerHTML = newContent.innerHTML;
        }
        
        startCountdown();
    })
    .catch(err => console.log('Refresh failed:', err));
}

function startCountdown() {
    countdown = refreshInterval;
    countdownElement.textContent = countdown;
    
    var countdownInterval = setInterval(function() {
        countdown--;
        countdownElement.textContent = countdown;
        
        if (countdown <= 0) {
            clearInterval(countdownInterval);
            silentRefresh();
        }
    }, 1000);
}

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', startCountdown);
} else {
    startCountdown();
}
</script>
AUTOREFRESH
}

&ui_print_footer("/", $text{'index'});
