#!/usr/bin/perl
# config.cgi
use strict;
use warnings;

our ($module_name, %text, %config, %in);

do '/var/www/proxymon/squidmon/squidmon-standalone.pl';
&init_config();
&ReadParse();

$module_name = 'squidmon';
&load_language($module_name);

# Load current config from file
my $config_file = '/var/www/proxymon/squidmon/etc/config';
&read_file($config_file, \%config);
$config{'acl_list'} =~ s/\\n/\n/g if $config{'acl_list'};

# Set defaults if not configured
$config{'squid_log'} ||= '/var/log/squid/access.log';
$config{'max_lines'} ||= 50000;
$config{'time_range'} ||= 24;
$config{'acl_list'} ||= "/etc/acl/acl_squid/blocktlds.txt=Blocked TLD\n/etc/acl/acl_squid/blockdomains.txt=Blocked Domains\nregex:^(http|https)://[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+=Block IPv4";
$config{'auto_refresh'} ||= 0;
$config{'refresh_interval'} ||= 60;

my $message = '';
my $message_type = '';

# Handle form submission - FIX: Check if action is defined
if (defined $in{'action'} && $in{'action'} eq 'save') {
    my $acl_list_value = $in{'acl_list'} || '';
    $acl_list_value =~ s/\r\n/\n/g;

    my $squid_log_value = $in{'squid_log'} || '/var/log/squid/access.log';

    # Validate inputs before writing them to disk — squidmon.cgi opens these
    # paths directly, so an unrestricted path here is an arbitrary file read.
    my @validation_errors = ();

    if ($squid_log_value !~ m{^/var/log/squid/[a-zA-Z0-9._-]+\.log$}) {
        push @validation_errors, 'Squid Log File Path must be under /var/log/squid/ and end in .log';
    }

    foreach my $acl_entry (split(/\n/, $acl_list_value)) {
        my $trimmed = $acl_entry;
        $trimmed =~ s/^\s+|\s+$//g;
        next if $trimmed eq '' || $trimmed =~ /^regex:/;
        if ($trimmed =~ /^([^=]+)=(.+)$/) {
            my $path = $1;
            if ($path !~ m{^/etc/acl/}) {
                push @validation_errors, "ACL path '$path' must be under /etc/acl/";
            }
        }
    }

    if (@validation_errors) {
        $message = 'Configuration not saved: ' . join('; ', @validation_errors);
        $message_type = 'error';
    } else {
    %config = (
        'squid_log' => $squid_log_value,
        'max_lines' => int($in{'max_lines'}) || 50000,
        'time_range' => int($in{'time_range'}) || 24,
        'acl_list' => $acl_list_value,
        'auto_refresh' => $in{'auto_refresh'} ? 1 : 0,
        'refresh_interval' => int($in{'refresh_interval'}) || 60
    );
    
    # Write config file
    if (open(my $fh, '>', $config_file)) {
        foreach my $key (sort keys %config) {
            if ($key eq 'acl_list') {
                my $acl_value = $config{$key};
                $acl_value =~ s/\r?\n/\\n/g;
                print $fh "$key=$acl_value\n";
            } else {
                print $fh "$key=$config{$key}\n";
            }
        }
        close($fh);
        $message = 'Configuration saved successfully!';
        $message_type = 'success';
    } else {
        $message = 'Error saving configuration. Check file permissions.';
        $message_type = 'error';
    }
    }
}

# Anti-cache headers
print "Content-Type: text/html; charset=utf-8\n";
print "Cache-Control: no-cache\n";
print "\n";

# Start HTML
print <<'HTML_START';
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Squid - Configuration</title>
    <style>
        body { 
            background: #f5f7fa; 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 20px;
        }
        .container { max-width: 900px; margin: 0 auto; }
        .header { background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
        .header h1 { margin: 0; color: #333; }
        .nav { margin-top: 15px; }
        .nav a { display: inline-block; padding: 8px 16px; background: #667eea; color: white; text-decoration: none; border-radius: 4px; margin-right: 10px; }
        .nav a:hover { background: #764ba2; }
        .content-card { background: white; border-radius: 8px; padding: 25px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); margin-bottom: 20px; }
        .form-group { margin-bottom: 20px; }
        .form-group label { display: block; margin-bottom: 8px; font-weight: 600; color: #333; }
        .form-group input, .form-group textarea, .form-group select { width: 100%; padding: 10px; border: 1px solid #ddd; border-radius: 4px; font-size: 13px; box-sizing: border-box; }
        .form-group textarea { min-height: 150px; font-family: monospace; }
        .form-group small { display: block; margin-top: 5px; color: #666; }
        .button-group { display: flex; gap: 10px; }
        .button-group button { padding: 10px 20px; border: none; border-radius: 4px; font-size: 14px; font-weight: 600; cursor: pointer; }
        .button-save { background: #10b981; color: white; }
        .button-save:hover { background: #059669; }
        .button-reset { background: #ef4444; color: white; }
        .button-reset:hover { background: #dc2626; }
        .alert { padding: 15px 20px; border-radius: 8px; margin-bottom: 20px; border-left: 4px solid; }
        .alert-success { background: #d1fae5; color: #065f46; border-left-color: #10b981; }
        .alert-error { background: #fee2e2; color: #991b1b; border-left-color: #dc2626; }
        .checkbox-group { display: flex; align-items: center; }
        .checkbox-group input[type="checkbox"] { margin-right: 10px; width: auto; }
    </style>
    <script>
    function resetToDefaults() {
        if (confirm('Are you sure you want to reset all values to defaults? This cannot be undone.')) {
            document.getElementById('squid_log').value = '/var/log/squid/access.log';
            document.getElementById('max_lines').value = '50000';
            document.getElementById('time_range').value = '24';
            document.getElementById('acl_list').value = '/etc/acl/acl_squid/blocktlds.txt=Blocked TLD\n/etc/acl/acl_squid/blockdomains.txt=Blocked Domains\nregex:^(http|https)://[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+=Block IPv4';
            document.getElementById('auto_refresh').checked = false;
            document.getElementById('refresh_interval').value = '60';
        }
    }
    </script>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>⚙️ Squidmon - Configuration</h1>
            <div class="nav">
                <a href="squidmon.cgi">← Back to Dashboard</a>
            </div>
        </div>
HTML_START

# Show message if exists
if ($message) {
    print "<div class='alert alert-$message_type'>\n";
    print escape_html($message) . "\n";
    print "</div>\n";
}

# Print form
print "<div class='content-card'>\n";
print "<form method='POST'>\n";
print "<input type='hidden' name='action' value='save'>\n";

print "<div class='form-group'>\n";
print "<label for='squid_log'>Squid Log File Path</label>\n";
print "<input type='text' id='squid_log' name='squid_log' value='" . escape_html($config{'squid_log'}) . "'>\n";
print "<small>Default: /var/log/squid/access.log</small>\n";
print "</div>\n";

print "<div class='form-group'>\n";
print "<label for='max_lines'>Maximum Lines to Parse</label>\n";
print "<input type='number' id='max_lines' name='max_lines' value='" . ($config{'max_lines'} || '50000') . "' min='1000' step='1000'>\n";
print "<small>Higher values = more data but slower parsing</small>\n";
print "</div>\n";

print "<div class='form-group'>\n";
print "<label for='time_range'>Time Range (Hours)</label>\n";
print "<input type='number' id='time_range' name='time_range' value='" . ($config{'time_range'} || '24') . "' min='1' step='1'>\n";
print "<small>Only show requests from last X hours</small>\n";
print "</div>\n";

print "<div class='form-group'>\n";
print "<label for='acl_list'>ACL Files to Monitor</label>\n";
print "<textarea id='acl_list' name='acl_list' placeholder='/etc/acl/acl_squid/file.txt=Label Name&#10;regex:pattern=Label Name'>" . escape_html($config{'acl_list'}) . "</textarea>\n";
print "<small>Format: One per line. File-based: /path/to/acl.txt=Label | Regex: regex:pattern=Label</small>\n";
print "</div>\n";

print "<div class='form-group checkbox-group'>\n";
print "<input type='checkbox' id='auto_refresh' name='auto_refresh'" . ($config{'auto_refresh'} ? ' checked' : '') . ">\n";
print "<label for='auto_refresh' style='margin: 0;'>Enable Auto-Refresh</label>\n";
print "</div>\n";

print "<div class='form-group'>\n";
print "<label for='refresh_interval'>Refresh Interval (Seconds)</label>\n";
print "<input type='number' id='refresh_interval' name='refresh_interval' value='" . ($config{'refresh_interval'} || 60) . "' min='30' step='10'>\n";
print "<small>Minimum recommended: 60 seconds</small>\n";
print "</div>\n";

print "<div class='button-group'>\n";
print "<button type='submit' class='button-save'>💾 Save Configuration</button>\n";
print "<button type='button' class='button-reset' onclick='resetToDefaults()'>↻ Reset to Defaults</button>\n";
print "</div>\n";

print "</form>\n";
print "</div>\n";

print "</div>\n"; # End container
print "</body>\n";
print "</html>\n";

exit;
