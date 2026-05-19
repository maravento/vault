#!/usr/bin/perl
# install_check.pl
# Check if Squid log file exists

do '../web-lib.pl';

sub module_install_check {
    my $log_file = '/var/log/squid/access.log';
    if (!-f $log_file && !-d '/var/log/squid') {
        return "Squid does not appear to be installed (log directory not found)";
    }
    return undef;
}
