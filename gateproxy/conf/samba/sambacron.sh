#!/bin/bash
# maravento.com

echo "Add Samba Task to Crontab"
sudo crontab -l | {
    cat
    echo '@monthly find ~/compartida/recycle/* -mtime +7 -exec rm -rf "{}" \; >/dev/null'
} | sudo crontab -
echo Done
exit
