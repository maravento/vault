#!/bin/bash
# by maravento.com

# Leases DHCP-SERVER

# checking root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi
# checking script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
fi
# checking dependencies (optional)
pkg='notify-osd libnotify-bin'
if apt-get -qq install $pkg; then
    echo "OK"
else
    echo "Error installing $pkg. Abort"
    exit
fi

aclroute="/etc/acl"

# LOCAL USER
local_user=${SUDO_USER:-$(whoami)}

function is_iscdhcp() {
    dhcpd=/var/lib/dhcp/dhcpd.leases
    dhcpd_temp=/var/lib/dhcp/dhcpd.leases.temp
    dhcp_conf=/etc/dhcp/dhcpd.conf
    dhcp_conf_temp=/etc/dhcp/dhcpd.conf.temp #$(mktemp)
    echo "" >"$dhcp_conf_temp"

    serv_dhcp=192.168.0.10
    serv_subnet=192.168.0.0
    serv_ini_range_block=192.168.0.100
    serv_end_range_block=192.168.0.250
    serv_broadcast=192.168.0.255
    serv_mask=255.255.255.0
    serv_dns=8.8.8.8,8.8.4.4
    #serv_dns=1.0.0.1,1.1.1.1
    #serv_dns=192.168.0.10

    function read_leases {
        # Reading the dhcp_leases entries. Format / Leyendo las entradas de dhcp_leases. Formato:
        #    host PC2 {
        #         hardware ethernet 00:13:46:7a:xx:xx;
        #         fixed-address 192.168.0.183;
        #    }

        # Output format
        # [a|b];00:11:22:33:44:55;111.111.111.111;hostname;introduction_date
        #
        num_line_actual=0
        while read line; do
            num_line_actual=$(($num_line_actual + 1))
            if $(echo "$line" | grep -E -q 'lease [0-9,.]+ {'); then # Initialization of variables of a new lease / Inicialización de variables de un nuevo arrendamiento
                host="no_name_$(get_cadena_random 10)"
                mac_address=""
                ip_address=$(echo "$line" | grep -E -o '[0-9,.]+')
                num_line_ini_lease=$num_line_actual
                num_line_end_lease=0
                continue
            fi

            if $(echo "$line" | grep -E -q 'client-hostname "[^"]+";'); then
                host=$(echo "$line" | cut -d"\"" -f2 | tr " " "_")
                # If the client did not have an associated name, its entry is updated / Si el cliente no tenía un nombre asociado, se actualiza su entrada
                if [[ $mac_address != "" && $(grep -E "$mac_address;[^;]+;no_name_[^;]+;" "$aclroute"/mac-* "$aclroute"/blockdhcp.txt) != "" ]]; then
                    line_aux=$(grep -E "$mac_address;[^;]+;no_name_[^;]+;" "$aclroute"/mac-* "$aclroute"/blockdhcp.txt | cut -d":" -f2-)
                    wcstatus_aux=$(echo "$line_aux" | cut -d ';' -f 1)
                    macsource_aux=$(echo "$line_aux" | cut -d ';' -f 2)
                    ipsource_aux=$(echo "$line_aux" | cut -d ';' -f 3)
                    date_aux=$(echo "$line_aux" | cut -d ';' -f 5)
                    sed -i "s/$line_aux/$wcstatus_aux;$macsource_aux;$ipsource_aux;$host;$date_aux/g" "$aclroute"/blockdhcp.txt "$aclroute"/mac-*
                fi
                continue
            fi

            if $(echo "$line" | grep -E -q 'hardware ethernet [0-9,a-f,:]+;'); then
                mac_address=$(echo "$line" | grep -E -o '[0-9,a-f,:]+;' | cut -d";" -f1)
                continue
            fi

            if $(echo "$line" | grep -E -q '}'); then # End of current lease / Fin del arrendamiento actual
                date_actual=$(date +"%s")
                num_line_end_lease=$num_line_actual
                if [[ $host != "" && $mac_address != "" && $ip_address != "" ]]; then
                    line_lease="a;$mac_address;$ip_address;$host;$date_actual;"
                    if [[ $(grep -o "$mac_address" "$aclroute"/mac-*) == "" ]]; then
                        if [[ $(grep -o "$mac_address" "$aclroute"/blockdhcp.txt) == "" ]]; then
                            # If the mac address is not in the authorized acl or in blockdhcp, it is added to blockdhcp, but it is kept in the lease, and the next time the script is run, if the mac address is still in the blockdhcp, it is removed from the lease file / Si la dirección mac no está en las acl autorizadas ni en blockdhcp, se añade a blockdhcp, pero se mantiene en el lease y la proxima vez que se ejecute el script, si la direccion mac sigue en el blockdhcp, se elimina del archivo lease
                            echo "$line_lease" >>"$aclroute"/blockdhcp.txt
                            sed "$num_line_ini_lease,$num_line_end_lease!d" "$dhcpd" >>"$dhcpd_temp"
                        fi
                    else
                        # If it is in the authorized acl, it is added to the leases / Si esta en las acl autorizadas, se añade al leases temporal
                        sed "$num_line_ini_lease,$num_line_end_lease!d" "$dhcpd" >>"$dhcpd_temp"
                        echo "" >>"$dhcpd_temp" # Por formato
                    fi
                fi
            fi

        done <"$dhcpd"

        # Replace the current leases file with the new one, with the authorized acl users / Reemplaza el archivo leases actual por el nuevo, con los usuarios de las acl autorizadas
        if [[ -e "$dhcpd_temp" ]]; then
            mv -f "$dhcpd_temp" "$dhcpd"
        else
            echo "" >"$dhcpd"
        fi
    }

    function update_dhcp_conf {
        # Updating the configuration file with data from the acl / Actualización del archivo de configuración con datos de las acl
        # General Options / Opciones generales
        echo "# ISC-DHCP-Server Configuration
authoritative;
option wpad code 252 = text;
server-identifier $serv_dhcp;
deny duplicates;
one-lease-per-client true;
deny declines;
deny client-updates;
ping-check true;
log-facility local7;
ddns-update-style none;
        " >"$dhcp_conf_temp"

        # Allowed Clients / Clientes permitidos
        for line in $(cat "$aclroute"/mac-*); do
            wcstatus=$(echo "$line" | cut -d ';' -f 1)
            macsource=$(echo "$line" | cut -d ';' -f 2)
            ipsource=$(echo "$line" | cut -d ';' -f 3)
            usersource=$(echo "$line" | cut -d ';' -f 4)
            if [[ $wcstatus == "a" ]]; then
                echo '
    host '$usersource '{
    hardware ethernet '$macsource';
    fixed-address '$ipsource';
                }' >>"$dhcp_conf_temp"
            fi
        done

        # Clients blocked from the blockdhcp blacklist / Clientes bloqueados de la lista negra blockdhcp
        echo '
class "blockdhcp" {
     match pick-first-value (option dhcp-client-identifier, hardware);
        }' >>"$dhcp_conf_temp"

        for line in $(cat "$aclroute"/blockdhcp.txt); do
            macs=$(echo "$line" | cut -d ';' -f 2)
            echo '    subclass "blockdhcp" 1:'$macs';' >>"$dhcp_conf_temp"
        done

        echo "" >>"$dhcp_conf_temp"

        # Subnet configuration / Configuracion subred
        echo "subnet $serv_subnet netmask $serv_mask {
    option wpad \"http://$serv_dhcp:8000/proxy.pac\";
    option routers $serv_dhcp;
    option subnet-mask $serv_mask;
    option broadcast-address $serv_broadcast;
    #option domain-name \"example.org\";
    option domain-name-servers $serv_dns;
    min-lease-time 2592000; # 30 days
    default-lease-time 2592000; # 30 days
    max-lease-time 2592000; # 30 days
    pool {
        min-lease-time 60;
        default-lease-time 60;
        max-lease-time 60;
        deny members of \"blockdhcp\";
        range $serv_ini_range_block $serv_end_range_block;
    }
}
        " >>"$dhcp_conf_temp"

        mv -f "$dhcp_conf_temp" "$dhcp_conf"

    }
    function clean_block_list {
        # Remove from blockdhcp blacklist entries added to acl / Elimina de la lista negra blockdhcp las entradas añadidas a las acl
        file_temp=$(mktemp)
        grep -E ';[0-9,a-f,:]+;' "$aclroute"/mac-* | cut -d ";" -f2 >"$file_temp"
        while read line; do
            mac_actual=$(echo "$line" | cut -d ';' -f 2)
            sed -i "/$mac_actual/d" "$aclroute"/blockdhcp.txt
        done <"$file_temp"
        rm -f "$file_temp"
    }

    function clean_local_list {
        # Removes entries added to the mac-unlimited acl from mac-unlimited / Elimina de mac-unlimited las entradas añadidas a la acl mac-unlimited
        while read line; do
            mac_actual=$(echo "$line" | cut -d ';' -f 2)
            sed -i "/$mac_actual/d" "$aclroute"/mac-proxy.txt
        done <"$aclroute"/mac-unlimited.txt
    }

    function clean_transparent_list {
        # Remove the entries added to the mac-unlimited acl from mac-transparent / Elimina de mac-transparent las entradas añadidas a la acl mac-unlimited
        while read line; do
            mac_actual=$(echo "$line" | cut -d ';' -f 2)
            sed -i "/$mac_actual/d" "$aclroute"/mac-transparent.txt
        done <"$aclroute"/mac-unlimited.txt
    }

    function clean_limit_list {
        # Removes the entries added to the privileged acl from the local list / Elimina de la acl local las entradas añadidas al acl privilegiados
        while read line; do
            mac_actual=$(echo "$line" | cut -d ';' -f 2)
            sed -i "/$mac_actual/d" "$aclroute"/mac-limited.txt
        done <"$aclroute"/mac-unlimited.txt
    }

    function clean_acl {
        # Remove blank lines from acl / Elimina lineas en blanco de las acl
        sed '/^$/d' -i "$aclroute"/blockdhcp.txt
        sed '/^$/d' -i "$aclroute"/mac-proxy.txt
        sed '/^$/d' -i "$aclroute"/mac-transparent.txt
        sed '/^$/d' -i "$aclroute"/mac-limited.txt
        sed '/^$/d' -i "$aclroute"/mac-unlimited.txt
    }

    function get_cadena_random {
        head -c100 /dev/urandom | sha1sum | head -c10
    }

    function order_files_acl {
        sort -n -t . -k 3,3 -k 4,4 "$aclroute"/blockdhcp.txt -o "$aclroute"/blockdhcp.txt
        sort -n -t . -k 3,3 -k 4,4 "$aclroute"/mac-proxy.txt -u -o "$aclroute"/mac-proxy.txt
        sort -n -t . -k 3,3 -k 4,4 "$aclroute"/mac-transparent.txt -u -o "$aclroute"/mac-transparent.txt
        sort -n -t . -k 3,3 -k 4,4 "$aclroute"/mac-limited.txt -u -o "$aclroute"/mac-limited.txt
        sort -n -t . -k 3,3 -k 4,4 "$aclroute"/mac-unlimited.txt -u -o "$aclroute"/mac-unlimited.txt
    }

    clean_acl
    clean_block_list
    clean_local_list
    clean_transparent_list
    clean_limit_list

    /etc/init.d/isc-dhcp-server stop
    read_leases
    order_files_acl
    update_dhcp_conf
    /etc/init.d/isc-dhcp-server start
}

# Stops the service if there are duplicates / Detiene el servicio si hay duplicados
function duplicate() {
    #aclall=`for field in 2 3 4; do cut -d\; -f${field} "$aclroute"/mac-* | sort | uniq -d; done`
    aclall=$(for field in 2 3 4; do cut -d\; -f${field} "$aclroute"/mac-* | sort | uniq -d; done)
    if [ "${aclall}" == "" ]; then
        is_iscdhcp
        echo OK
    else
        echo "Duplicate Data: $(date) "$aclall"" | tee -a /var/log/syslog
        sudo -u $local_user DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u $local_user)/bus notify-send "Warning: Abort" "Duplicate: "$aclroute". $date" -i error
        exit
    fi
}
duplicate
