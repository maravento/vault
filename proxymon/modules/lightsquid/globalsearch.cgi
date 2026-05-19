#!/usr/bin/perl
# globalsearch.cgi
use strict;
use warnings;
use CGI ':standard';
use File::Basename;
use File::Find;
use Time::HiRes qw(gettimeofday tv_interval);

my $start_time = [gettimeofday];

push (@INC,(fileparse($0))[1]);
require "lightsquid.cfg";
require "common.pl";

my %skipusers;
my $skipfile = '/var/www/proxymon/lightsquid/skipuser.cfg';
if (open(my $sfh, '<', $skipfile)) {
    while (my $line = <$sfh>) {
        chomp $line;
        $line =~ s/^\s+|\s+$//g;
        next if $line eq '' || $line =~ /^#/;
        my ($ip) = split(/\s+/, $line);
        $skipusers{$ip} = 1;
    }
    close($sfh);
}

print header(-type => 'text/html; charset=utf-8');

my $query = param('query') // '';
$query =~ s/^\s+|\s+$//g;
$query =~ s/[^a-zA-Z0-9.-]//g;

print <<'HTML_HEADER';
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Global Site Search - LightSquid</title>
<link href="assets/global/plugins/bootstrap/css/bootstrap.min.css" rel="stylesheet">
<link href="assets/global/plugins/font-awesome/css/font-awesome.min.css" rel="stylesheet">
<style>
    body { background-color: #f5f5f5; margin-top: 20px; }
    .search-container { background: white; padding: 20px; border-radius: 4px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); margin-bottom: 20px; }
    .result-row { transition: background 0.2s; }
    .result-row:hover { background-color: #f9f9f9; }
</style>
</head>
<body>
<div class="container">
<div class="search-container">
    <h2><i class="fa fa-search"></i> Global Site Search</h2>
    <hr>
    <form method="get" class="form-inline">
        <div class="form-group" style="width: 100%;">
            <input type="text" name="query" class="form-control" style="width: 70%; padding: 8px;" placeholder="Search site..." value="">
            <button type="submit" class="btn btn-primary" style="margin-left: 10px;"><i class="fa fa-search"></i> Search</button>
            <a href="index.cgi" class="btn btn-default" style="margin-left: 10px;"><i class="fa fa-home"></i> Back</a>
        </div>
    </form>
</div>
HTML_HEADER

if ($query eq '') {
    print "<div class='alert alert-info text-center'><i class='fa fa-info-circle'></i> Please enter a search term</div>";
    print "</div></body></html>";
    exit;
}

print "<p class='lead'>Searching for: <strong>" . escapeHtml($query) . "</strong></p>";

my @results;
my $reportpath = '/var/www/proxymon/lightsquid/report';
my @all_grep_results;
my $query_lc = lc($query);

find(sub {
    return unless -f $_;
    return unless $File::Find::name =~ m{/\d{8}/[^/]+$};
    open(my $fh, '<', $File::Find::name) or return;
    while (my $line = <$fh>) {
        if (index(lc($line), $query_lc) != -1) {
            push @all_grep_results, $File::Find::name . ':' . $line;
        }
    }
    close($fh);
}, $reportpath);

foreach my $line (@all_grep_results) {
    chomp $line;

    my ($filepath, $content) = split(/:/, $line, 2);
    next unless $content;

    my ($date, $userfile) = $filepath =~ m{/(\d{8})/([^/]+)$};
    next unless $date && $userfile;
    next if $skipusers{$userfile};

    $content =~ s/^\s+|\s+$//g;
    next if $content =~ /^total:/;

    my @parts = split(/\s+/, $content);
    next unless @parts >= 2;

    my $site = $parts[0];
    my $size = $parts[1];
    my $hits = $parts[2] || 0;

    next unless $size =~ /^\d+$/;

    my ($year, $month, $day) = ($date =~ /^(\d{4})(\d{2})(\d{2})$/);
    my @months = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
    my $monthname = $months[$month - 1];
    my $printdate = "$day $monthname $year";

    my $printsize = FineDec($size);
    my $detail_url = "user_detail.cgi?year=" . $year .
                     "&month=" . $month .
                     "&day=" . $day .
                     "&user=$userfile";

    push @results, {
        site       => $site,
        user       => $userfile,
        size       => $printsize,
        size_bytes => int($size),
        hits       => $hits,
        date       => $printdate,
        date_sort  => $date,
        url        => $detail_url
    };
}

my $elapsed = tv_interval($start_time);
my $elapsed_ms = sprintf("%.2f", $elapsed * 1000);

if (!@results) {
    print "<div class='alert alert-warning'><i class='fa fa-search'></i> No results found for: <strong>" . escapeHtml($query) . "</strong> in <strong>$elapsed_ms ms</strong></div>";
} else {
    my $count = scalar(@results);
    print "<div class='alert alert-success'><i class='fa fa-check-circle'></i> Found <strong>$count</strong> result(s) in <strong>$elapsed_ms ms</strong></div>";

    print "<table class='table table-striped table-bordered table-hover'>";
    print "<thead><tr class='info'>";
    print "<th style='width: 30%;'>Site</th>";
    print "<th style='width: 20%;'>User</th>";
    print "<th style='width: 15%;'>Size</th>";
    print "<th style='width: 10%;'>Requests</th>";
    print "<th style='width: 15%;'>Date</th>";
    print "<th style='width: 10%;'>View</th>";
    print "</tr></thead><tbody>";

    my $rownum = 0;
    foreach my $r (sort { $b->{date_sort} cmp $a->{date_sort} || $b->{size_bytes} <=> $a->{size_bytes} } @results) {
        $rownum++;
        my $bgcolor = ($rownum % 2) ? '#ffffff' : '#f9f9f9';

        print "<tr class='result-row' style='background-color: $bgcolor;'>";
        print "<td><strong>" . escapeHtml($r->{site}) . "</strong></td>";
        print "<td>" . escapeHtml($r->{user}) . "</td>";
        print "<td>$r->{size}</td>";
        print "<td style='text-align: center;'>$r->{hits}</td>";
        print "<td>$r->{date}</td>";
        print "<td><a href='$r->{url}' class='btn btn-xs btn-primary'><i class='fa fa-arrow-right'></i></a></td>";
        print "</tr>";

        last if $rownum >= 200;
    }

    print "</tbody></table>";
}

print "</div></body></html>";

sub escapeHtml {
    my $text = shift;
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    $text =~ s/"/&quot;/g;
    return $text;
}
