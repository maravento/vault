#!/bin/bash
# maravento.com

# Minor update to DDoS-Deflate, version 0.6
# Author: Zaf <zaf@vsnl.com>

# check root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# check script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
fi

load_conf()
{
    CONF="/usr/local/ddos/ddos.conf"
    if [ -f "$CONF" ] && [ ! "$CONF" ==    "" ]; then
        source $CONF
    else
        head
        echo "$CONF not found."
        exit 1
    fi
}

head()
{
    echo "DDoS-Deflate"
}

showhelp()
{
    head
    echo 'Usage: ddos.sh [OPTIONS] [N|IP]'
    echo "N : Ban limit for number of tcp/udp    connections per IP (default $BAN_LIMIT)"
    echo 'OPTIONS:'
    echo '-h | --help:    Show this help screen'
    echo "-c | --cron:    Create cron job to run this script regularly ($FREQ minutes)"
    echo '-k | --kill:    Block the offending ip making more than N connections (overrides config)'
    echo '-n | --no-kill: Report only, do not block IPs (overrides config)'
    echo '-l | --list:    List all IPs and connection counts over the warning limit.'
    echo '-b | --ban:     Ban the given IP address temporarily.'
}

unbanip()
{
    UNBAN_SCRIPT=`mktemp /tmp/unban.XXXXXXXX`
    TMP_FILE=`mktemp /tmp/unban.XXXXXXXX`
    UNBAN_IP_LIST=`mktemp /tmp/unban.XXXXXXXX`
    echo '#!/bin/sh' > $UNBAN_SCRIPT
    echo "sleep $BAN_PERIOD" >> $UNBAN_SCRIPT
    if [ $APF_BAN -eq 1 ]; then
        while read line; do
            echo "$APF -u $line" >> $UNBAN_SCRIPT
            echo $line >> $UNBAN_IP_LIST
        done < $BANNED_IP_LIST
    else
        while read line; do
            echo "$IPT -D INPUT -s $line -j DROP" >> $UNBAN_SCRIPT
            echo $line >> $UNBAN_IP_LIST
        done < $BANNED_IP_LIST
    fi
    echo "grep -v --file=$UNBAN_IP_LIST $IGNORE_IP_LIST > $TMP_FILE" >> $UNBAN_SCRIPT
    echo "mv $TMP_FILE $IGNORE_IP_LIST" >> $UNBAN_SCRIPT
    echo "rm -f $UNBAN_SCRIPT" >> $UNBAN_SCRIPT
    echo "rm -f $UNBAN_IP_LIST" >> $UNBAN_SCRIPT
    echo "rm -f $TMP_FILE" >> $UNBAN_SCRIPT
    . $UNBAN_SCRIPT &
}

add_to_cron()
{
    rm -f $CRON
    sleep 1
    systemctl restart cron
    sleep 1
    echo "SHELL=/bin/sh" > $CRON
    if [ $FREQ -le 2 ]; then
        echo "0-59/$FREQ * * * * root $PROG >/dev/null 2>&1" >> $CRON
    else
        let "START_MINUTE = $RANDOM % ($FREQ - 1)"
        let "START_MINUTE = $START_MINUTE + 1"
        let "END_MINUTE = 60 - $FREQ + $START_MINUTE"
        echo "$START_MINUTE-$END_MINUTE/$FREQ * * * * root $PROG >/dev/null 2>&1" >> $CRON
    fi
    systemctl restart cron
}

ban_ips()
{
    BANNED_IP_MAIL=$(mktemp $TMP_PREFIX.XXXXXXXX)
    BANNED_IP_LIST=$(mktemp $TMP_PREFIX.XXXXXXXX)
    echo "Banned the following ip addresses on `date`" > $BANNED_IP_MAIL
    IP_BANNED=0
    IP_LOGGED=0
    while read CONN IP; do
        FQDN=$(dig +short -x $IP)
        if [ $CONN -ge $BAN_LIMIT -a $KILL -eq 1 ]; then
            echo "BANNED: $IP with $CONN connections ($FQDN)" >> $BANNED_IP_MAIL
            echo $IP >> $BANNED_IP_LIST
            echo $IP >> $IGNORE_IP_LIST
            if [ $APF_BAN -eq 1 ]; then
                $APF -d $IP && IP_BANNED=1
            else
                $IPT -I INPUT -s $IP -j DROP && IP_BANNED=1
            fi
        else
            echo "WARNING: $IP with $CONN connections ($FQDN)" >> $BANNED_IP_MAIL
        fi
        IP_LOGGED=1
    done < $BAD_IP_LIST

    if [ $IP_BANNED -eq 1 ]; then
        [ -n $AFTER_BAN ] && eval $AFTER_BAN
        unbanip
    fi
    if [ $IP_LOGGED -eq 1 ]; then
        echo >>    $BANNED_IP_MAIL
        if [ -n $LOG_FILE ]; then
            cat $BANNED_IP_MAIL >> $LOG_FILE
        fi
        if [ "$EMAIL_TO" != "" ]; then
            mail -s "IP addresses banned on `date`" $EMAIL_TO < $BANNED_IP_MAIL &> /dev/null
        fi
    fi
}

TMP_PREFIX='/tmp/ddos'
load_conf
LIST=0
while [ $1 ]; do
    case $1 in
        '-h' | '--help' | '?' )
            showhelp
            exit
            ;;
        '--cron' | '-c' )
            add_to_cron
            exit
            ;;
        '--ban' | '-b' )
            [ "$2" != "" ] || { echo "You did not provide the IP to ban.."; exit 1; }
            BAD_IP_LIST=$(mktemp $TMP_PREFIX.XXXXXXXX)
            echo "999999 $2" > $BAD_IP_LIST
            KILL=1
            ban_ips
            rm -f $TMP_PREFIX.*
            exit
            ;;
        '--kill' | '-k' )
            KILL=1
            ;;
        '--no-kill' | '-n' )
            KILL=0
            ;;
        '--list' | '-l' )
            LIST=1
            ;;
         *[0-9]* )
            BAN_LIMIT=$1
            ;;
        * )
            showhelp
            exit
            ;;
    esac
    shift
done
[ -z $WARN_LIMIT ] && WARN_LIMIT=$BAN_LIMIT
[ $LIST -eq 1 -a $BAN_LIMIT -lt $WARN_LIMIT ] && WARN_LIMIT=$BAN_LIMIT
[ $BAN_LIMIT -ge $WARN_LIMIT ] || WARN_LIMIT=$BAN_LIMIT

# Modified netstat command taken from: http://blog.everymanhosting.com/webhosting/dos-deflate-blocks-numbers-not-ip-addresses/
# Only check for ESTABLISHED status connections
BAD_IP_LIST=$(mktemp $TMP_PREFIX.XXXXXXXX)
netstat -ntu | grep ':' | awk '{print $5}' | sed 's/::ffff://' | cut -f1 -d ':' \
  | sort | grep -v -f <(grep -vF '#' $IGNORE_IP_LIST | sort) | uniq -c \
  | awk "{ if (\$1 >= $WARN_LIMIT) print; }" | sort -nr \
  > $BAD_IP_LIST
cat $BAD_IP_LIST
if [ $LIST -eq 1 ]; then
    FOUND_COUNT=$(cat $BAD_IP_LIST | wc -l)
    echo "Found ${FOUND_COUNT} IPs with ${WARN_LIMIT} or more connections."
    rm -f $TMP_PREFIX.*
    exit
fi
ban_ips
rm -f $TMP_PREFIX.*
#echo "$(date) - DDoS-Deflate Done" | tee -a /usr/local/ddos/ddos.log > /dev/null
