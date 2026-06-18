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
    systemctl stop smbd.service &>/dev/null
    if systemctl start smbd.service; then
        echo "smbd start: $(date)" | tee -a /var/log/syslog
    else
        echo "smbd start FAILED: $(date)" | tee -a /var/log/syslog
    fi
fi

# Samba Service (winbind)
if pgrep -x winbindd > /dev/null; then
    echo "winbind: ONLINE"
else
    systemctl stop winbind.service &>/dev/null
    if systemctl start winbind.service; then
        echo "winbind start: $(date)" | tee -a /var/log/syslog
    else
        echo "winbind start FAILED: $(date)" | tee -a /var/log/syslog
    fi
fi
