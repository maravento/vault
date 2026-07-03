#!/usr/bin/perl
# pdf_report.cgi
use strict;
use warnings;

print "Content-type: text/html; charset=utf-8\n\n";

# Variables
our (%config, %in);

eval {
    # load config
    if (-e '/var/www/proxymon/squidmon/squidmon-standalone.pl') {
        require '/var/www/proxymon/squidmon/squidmon-standalone.pl';
        &init_config() if defined &init_config;
        &ReadParse()   if defined &ReadParse;
    }

    my $module_name = 'squidmon';
    &load_language($module_name) if defined &load_language;

    my $config_file = '/var/www/proxymon/squidmon/etc/config';
    &read_file($config_file, \%config) if defined &read_file;

    my $log_file       = $config{'squid_log'} || '/var/log/squid/access.log';
    my $max_lines      = $in{'max_lines'} || $config{'max_lines'} || 50000;
    my $time_range     = $in{'time_range'} || $config{'time_range'} || 24;
    my $specific_client = $in{'client_ip'} || '';

    # Validate as plain integers — these come straight from request params
    $max_lines  = 50000 unless $max_lines  =~ /^\d+$/;
    $time_range = 24    unless $time_range =~ /^\d+$/;
    $specific_client = '' unless $specific_client =~ /^[0-9a-fA-F.:]*$/; # IPv4/IPv6 only

    $max_lines = 100000 if $time_range > 168;
    my $time_threshold = time() - ($time_range * 3600);

    my (%stats, %client_traffic, %domain_stats, %hourly_stats);
    %stats = (total_requests => 0, blocked_requests => 0, allowed_requests => 0);

    # Read the last lines of the log
    my @log_lines;
    if (open(my $fh, '<', $log_file)) {
        my @all = <$fh>;
        close $fh;
        @log_lines = @all[-$max_lines .. -1] if @all > $max_lines;
        @log_lines = @all if @all <= $max_lines;
    }

    foreach my $line (@log_lines) {
        next unless $line =~ /^(\d+\.\d+)\s+\S+\s+(\S+)\s+(\S+)\s+\S+\s+\S+\s+(https?:\/\/)?([^\s\/]+)([^\s]*)/;

        my ($timestamp, $client, $action_code, $domain) = ($1, $2, $3, $5);
        next if $timestamp < $time_threshold;
        next if $specific_client && $client ne $specific_client;

        $stats{total_requests}++;
        my $is_blocked = ($action_code =~ /^TCP_DENIED/) ? 'Blocked' : 'Allowed';
        $stats{'blocked_requests'}++ if $is_blocked eq 'Blocked';
        $stats{'allowed_requests'}++ if $is_blocked eq 'Allowed';

        $client_traffic{$client}{total}++;
        $client_traffic{$client}{$is_blocked}++;
        $domain_stats{$domain}{total}++;
        $domain_stats{$domain}{$is_blocked}++;
        $domain_stats{$domain}{clients}{$client}++;

        my ($hour) = (localtime($timestamp))[2];
        $hourly_stats{$hour}{total}++;
        $hourly_stats{$hour}{$is_blocked}++;
    }

    # HTML output
    print <<'HTMLHEAD';
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Proxy Monitor - Traffic Report</title>
<style>
body { font-family: Arial, sans-serif; margin:20px; color:#000; font-size:12px; }
.header { text-align:center; border-bottom:2px solid #333; padding-bottom:10px; margin-bottom:20px; }
.summary { background:#f5f5f5; padding:15px; margin-bottom:20px; border-radius:5px; }
table { width:100%; border-collapse:collapse; margin-bottom:20px; }
th { background:#333; color:#fff; padding:8px; text-align:left; border:1px solid #555; }
td { padding:8px; border:1px solid #ddd; vertical-align:top; }
.section-title { background:#4b5563; color:#fff; padding:10px; margin:20px 0 10px 0; border-radius:4px; }
.blocked { color:#dc2626; font-weight:bold; }
.allowed { color:#10b981; font-weight:bold; }
.traffic { color:#3b82f6; font-weight:bold; }
@media print { .no-print { display:none; } body { margin:0; } }
</style>
</head>
<body>
<div class="header">
HTMLHEAD

    my $time_label = ($time_range == 24) ? "Last 24 Hours"
                   : ($time_range == 168) ? "Last 7 Days"
                   : ($time_range == 720) ? "Last 30 Days"
                   : "Last $time_range Hours";

    if ($specific_client) {
        print "<h1>Proxy Monitor - Client Traffic Report: $specific_client</h1>";
    } else {
        print "<h1>Proxy Monitor - Traffic Report</h1>";
    }
    print "<p>Generated on: " . scalar(localtime) . "</p>";
    print "<p>Time Period: $time_label</p></div>";

    my $total = $stats{total_requests} || 1;
    my $allowed_p = sprintf("%.1f", ($stats{allowed_requests}/$total)*100);
    my $blocked_p = sprintf("%.1f", ($stats{blocked_requests}/$total)*100);

    print "<div class='summary'>";
    print "<h2>📊 Traffic Summary</h2>";
    print "<p><strong>Total Requests:</strong> <span class='traffic'>" . format_number_pdf($stats{total_requests}) . "</span></p>";
    print "<p><strong>Allowed:</strong> <span class='allowed'>" . format_number_pdf($stats{allowed_requests}) . " ($allowed_p%)</span></p>";
    print "<p><strong>Blocked:</strong> <span class='blocked'>" . format_number_pdf($stats{blocked_requests}) . " ($blocked_p%)</span></p>";
    print "<p><strong>Unique Clients:</strong> " . format_number_pdf(scalar keys %client_traffic) . "</p>";
    print "</div>";

    print "<div class='no-print' style='background:#ffeb3b;padding:10px;border-radius:5px;'>";
    print "💾 To save: Press <b>Ctrl+P</b> → Select <b>Save as PDF</b>.</div>";

    # Table of main domains
    print "<div class='section-title'>🌐 Top 15 Most Visited Domains</div><table>";
    print "<tr><th>Domain</th><th>Total</th><th>Allowed</th><th>Blocked</th><th>Clients</th></tr>";
    my $count = 0;
    for my $domain (sort { ($domain_stats{$b}{total}||0) <=> ($domain_stats{$a}{total}||0) } keys %domain_stats) {
        last if $count++ >= 15;
        my $t = $domain_stats{$domain}{total} || 0;
        my $a = $domain_stats{$domain}{Allowed} || 0;
        my $b = $domain_stats{$domain}{Blocked} || 0;
        my $c = scalar keys %{$domain_stats{$domain}{clients}||{}};
        print "<tr><td>".html_escape_pdf($domain)."</td><td>".format_number_pdf($t)."</td><td class='allowed'>".format_number_pdf($a)."</td><td class='blocked'>".format_number_pdf($b)."</td><td>$c</td></tr>";
    }
    print "</table></body></html>";

}; # fin eval

if ($@) {
    print "<h3 style='color:red;'>Error generating report: $@</h3>";
}

sub format_number_pdf {
    my ($num) = @_;
    $num ||= 0;
    $num =~ s/(\d)(?=(\d{3})+(?!\d))/$1,/g;
    return $num;
}

sub html_escape_pdf {
    my ($s) = @_;
    return '' unless defined $s;
    $s =~ s/&/&amp;/g;
    $s =~ s/</&lt;/g;
    $s =~ s/>/&gt;/g;
    $s =~ s/"/&quot;/g;
    $s =~ s/'/&#39;/g;
    return $s;
}

