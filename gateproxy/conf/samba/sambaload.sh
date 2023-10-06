#!/bin/bash
# by maravento.com

cat <<'EOF'
# Samba Service (smbd)
if [[ `ps -A | grep smbd` != "" ]];then
    echo -e "\nONLINE"
else
    echo -e "\n"
    for pid in $(ps -ef | grep "smbd" | awk '{print $2}'); do kill -9 $pid &> /dev/null; done
    sleep ${sleep_time}
    systemctl start smbd.service
    # alternative:
    #/etc/init.d/smbd start
    echo "Samba (smbd) start: $(date)" | tee -a /var/log/syslog
fi
# Samba Service (nmbd)
if [[ `ps -A | grep nmbd` != "" ]];then
    echo -e "\nONLINE"
else
    echo -e "\n"
    for pid in $(ps -ef | grep "nmbd" | awk '{print $2}'); do kill -9 $pid &> /dev/null; done
    sleep ${sleep_time}
    systemctl start nmbd.service
    # alternative:
    #/etc/init.d/nmbd start
    echo "Samba (nmbd) start: $(date)" | tee -a /var/log/syslog
fi
# Samba Service (winbind)
if [[ `ps -A | grep winbindd` != "" ]];then
    echo -e "\nONLINE"
else
    echo -e "\n"
    for pid in $(ps -ef | grep "winbindd" | awk '{print $2}'); do kill -9 $pid &> /dev/null; done
    sleep ${sleep_time}
    systemctl start winbind.service
    # alternative:
    #/etc/init.d/winbind start
    echo "Samba (winbind) start: $(date)" | tee -a /var/log/syslog
fi
EOF
