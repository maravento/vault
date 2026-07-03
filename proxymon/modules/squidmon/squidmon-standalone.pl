#!/usr/bin/perl
# squidmon-standalone.pl
# Pure Perl implementation without Webmin dependencies
# Replaces web-lib.pl and ui-lib.pl

use strict;
use warnings;
use URI::URL;
use Cwd;

our %config;
our %text;
our %in;
our $module_name = 'squidmon';

# ============================================================
# Configuration and Initialization
# ============================================================

sub init_config {
    # Initialize global configuration
    %config = ();
    return 1;
}

# ============================================================
# Parse GET/POST Parameters
# ============================================================

sub ReadParse {
    my $query_string = '';
    
    if (($ENV{'REQUEST_METHOD'} // '') eq 'POST') {
        read(STDIN, $query_string, $ENV{'CONTENT_LENGTH'}) if $ENV{'CONTENT_LENGTH'};
    } else {
        $query_string = $ENV{'QUERY_STRING'} || '';
    }
    
    %in = ();
    foreach my $pair (split(/&/, $query_string)) {
        my ($name, $value) = split(/=/, $pair, 2);
        next unless $name;
        $value //= '';
        
        # URL decode
        $name =~ tr/+/ /;
        $name =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
        $value =~ tr/+/ /;
        $value =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
        
        if (exists $in{$name}) {
            # Handle multiple values
            if (ref($in{$name}) eq 'ARRAY') {
                push @{$in{$name}}, $value;
            } else {
                $in{$name} = [$in{$name}, $value];
            }
        } else {
            $in{$name} = $value;
        }
    }
    
    return 1;
}

# ============================================================
# Read Configuration Files
# ============================================================

sub read_file {
    my ($file, $config_ref) = @_;
    return 0 unless -f $file;
    
    %$config_ref = ();
    open(my $fh, '<', $file) or return 0;
    
    while (<$fh>) {
        chomp;
        next if /^#/ || /^\s*$/;
        
        if (/^([^=]+)=(.*)$/) {
            my ($key, $value) = ($1, $2);
            $key =~ s/^\s+|\s+$//g;
            $value =~ s/^\s+|\s+$//g;
            $config_ref->{$key} = $value;
        }
    }
    close($fh);
    return 1;
}

# ============================================================
# Language Support
# ============================================================

sub load_language {
    my ($module) = @_;
    $module ||= $module_name;
    
    %text = ();
    
    # Determine language from environment or default to 'en'
    my $lang = $ENV{'LANG'} || 'en';
    $lang =~ s/_.+//;  # Remove encoding suffix
    $lang = 'en' unless $lang;
    
    # Try to load language file
    my $lang_file = "./lang/$lang";
    if (-f $lang_file) {
        open(my $fh, '<', $lang_file) or return 0;
        while (<$fh>) {
            chomp;
            next if /^#/ || /^\s*$/;
            if (/^([^=]+)=(.*)$/) {
                my ($key, $value) = ($1, $2);
                $key =~ s/^\s+|\s+$//g;
                $value =~ s/^\s+|\s+$//g;
                $text{$key} = $value;
            }
        }
        close($fh);
    }
    
    return 1;
}

sub get_text {
    my ($key, $default) = @_;
    return $text{$key} || $default || $key;
}

# ============================================================
# HTML Output Functions
# ============================================================

sub ui_print_header {
    my ($title1, $title2, $title3, $help, $nomodule, $nowebmin) = @_;
    
    my $title = $title2 || $title1 || 'Squidmon';
    
    print "Content-Type: text/html; charset=utf-8\n";
    print "Cache-Control: no-cache, no-store, must-revalidate\n";
    print "Pragma: no-cache\n";
    print "\n";
    
    print <<'EOF';
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Proxy Monitor</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            background: #f5f7fa; 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            padding: 0;
            margin: 0;
        }
        .container { max-width: 1400px; margin: 0 auto; padding: 20px; }
        h1 { color: #333; margin-bottom: 20px; }
    </style>
</head>
<body>
    <div class="container">
EOF
    
    print "<h1>$title</h1>\n";
    
    return 1;
}

sub ui_print_footer {
    my ($home_url, $home_title) = @_;
    
    $home_url ||= '/';
    $home_title ||= 'Home';
    
    print <<'EOF';
    </div>
</body>
</html>
EOF
    
    return 1;
}

# ============================================================
# Table Functions
# ============================================================

sub ui_table_start {
    my ($title, $cols) = @_;
    print "<table border='1' cellpadding='5' cellspacing='0'>\n";
    if ($title) {
        print "<caption>$title</caption>\n";
    }
    return 1;
}

sub ui_table_end {
    print "</table>\n";
    return 1;
}

sub ui_table_row {
    my (@cells) = @_;
    print "<tr>";
    foreach my $cell (@cells) {
        print "<td>$cell</td>";
    }
    print "</tr>\n";
    return 1;
}

# ============================================================
# Form Functions
# ============================================================

sub ui_form_start {
    my ($action, $method, $title, $form_name) = @_;
    $method ||= 'post';
    $form_name ||= 'form1';
    
    print "<form name='$form_name' method='$method' action='$action'>\n";
    return 1;
}

sub ui_form_end {
    print "</form>\n";
    return 1;
}

# ============================================================
# Button/Input Functions
# ============================================================

sub ui_submit {
    my ($name, $label) = @_;
    $label ||= $name;
    return "<input type='submit' name='$name' value='$label'>";
}

sub ui_button {
    my ($name, $label, $onclick) = @_;
    $label ||= $name;
    my $on = $onclick ? " onclick='$onclick'" : '';
    return "<input type='button' name='$name' value='$label'$on>";
}

# ============================================================
# Utility Functions
# ============================================================

sub escape_html {
    my ($text) = @_;
    return '' unless defined $text;
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    $text =~ s/"/&quot;/g;
    $text =~ s/'/&#39;/g;
    return $text;
}

sub format_number {
    my ($num) = @_;
    return 0 unless defined $num;
    $num =~ s/(\d)(?=(\d{3})+(?!\d))/$1,/g;
    return $num;
}

sub get_time_string {
    my ($time) = @_;
    return scalar(localtime($time || time()));
}

# ============================================================
# File Operations
# ============================================================

sub copy_file {
    my ($source, $dest) = @_;
    open(my $src, '<', $source) or return 0;
    open(my $dst, '>', $dest) or return 0;
    while (<$src>) {
        print $dst $_;
    }
    close($src);
    close($dst);
    return 1;
}

# ============================================================
# Directory Operations
# ============================================================

sub make_dir {
    my ($dir) = @_;
    return 1 if -d $dir;
    return mkdir($dir, 0755);
}

# ============================================================
# Return 1 to indicate successful module load
# ============================================================

1;
