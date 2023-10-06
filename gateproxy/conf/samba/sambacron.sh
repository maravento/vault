#!/bin/bash
# by maravento.com

echo "Add Samba Task to Crontab"
sudo crontab -l | {
    cat
    echo "*/10 * * * * grep smbd_audit /var/log/samba/audit.log > /var/www/smbaudit/audit.log"
} | sudo crontab -
sudo crontab -l | {
    cat
    echo '@monthly find ~/compartida/recycle/* -mtime +7 -exec rm -rf "{}" \; >/dev/null'
} | sudo crontab -
sudo crontab -l | {
    cat
    echo "#@monthly cat /dev/null > /var/log/samba/audit.log"
} | sudo crontab -
echo Done
exit
