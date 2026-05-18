#!/bin/bash
# maravento.com
#
################################################################################
#
# smbstack - Service Watchdog
# https://github.com/maravento/vault/smbstack
#
################################################################################

SLEEP_TIME=5

# Samba Service (smbd)
if pgrep -x smbd > /dev/null; then
    echo "smbd: ONLINE"
else
    pkill -x smbd &>/dev/null; sleep $SLEEP_TIME
    systemctl start smbd.service
    echo "smbd start: $(date)" | tee -a /var/log/syslog
fi

# Samba Service (winbind)
if pgrep -x winbindd > /dev/null; then
    echo "winbind: ONLINE"
else
    pkill -x winbindd &>/dev/null; sleep $SLEEP_TIME
    systemctl start winbind.service
    echo "winbind start: $(date)" | tee -a /var/log/syslog
fi
