#!/bin/bash
# by maravento.com

# BlackUSB

# Fork:
# [usbkill](https://github.com/hephaest0s/usbkill)
# [usbdeath](https://github.com/trpt/usbdeath)
# Modified by:
# maravento.com and novatoz.com

echo "BlackUSB Start. Wait..."
printf "\n"

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

# How to Use:
# block usb except whitelist (00-blackusb.rules)
# Safe (demo) mode, remove to run real commands
demo='no'

# Commands to run on trigger
commands_list=(
    'sync'
    # Uncomment to activate paranoid mode (poweroff: turn off the computer when detecting unauthorized removable device)
    #'poweroff'
)

# Use colors in messages
colors='yes'

# Advanced config #
###################

# Logging, you possibly don't want to turn it off
log_enabled='yes'
log_file='/var/log/blackusb.log'
if [ ! -f "$log_file" ]; then touch $log_file; fi

# Use custom editor
custom_editor='yes'
editor_x='gedit'
editor_console='nano'

# Path to udev rule, edit carefully
rule_file='/etc/udev/rules.d/00-blackusb.rules'

# Path to the app, do not edit
SCR="$(
    cd "$(dirname "$0")"
    pwd -P
)"
PROGRAM="${0##*/}"
PROGRAM_ABS="$SCR/$PROGRAM"

# Run this when uknown usb device is added
trigger_cmd_add="$PROGRAM_ABS trigger"

# Run this when specified usb device is removed
trigger_cmd_remove="$PROGRAM_ABS trigger"

# Code       #
##############
if [[ $custom_editor = 'yes' ]]; then
    [[ -n $DISPLAY ]] && INX=yes
    [[ -n $INX ]] && export EDITOR="$editor_x" || export EDITOR="$editor_console"
fi

die() {
    [[ $colors = 'yes' ]] && echo -e "\n\033[1;31m$@\033[0m" >&2 || echo -e "\n$@" >&2
    exit 1
}

message() { [[ $colors = 'yes' ]] && echo -e "\033[1;37m$@\033[0m" || echo -e "$@"; }

if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    die "Not running as root"
fi

if [[ ! -d $(dirname "$rule_file") ]]; then
    die "No udev rules folder found"
fi

usage() {
    cat <<EOF

BlackUSB

usage: ${0##*/} [action]

  action
    o, on - activate blackusb
    x, off - temporarily deactivate blackusb
    j, eject - add entry on eject event
    g, gen - generate or refresh whitelist udev rules file
    d, del - delete udev rules file
    t, trigger - trigger event on insertion or removal
    e, edit - edit udev rules file manually
    s, show - show currently connected usb devices

  config (check source)
    udev rule file: $rule_file
    editor: $EDITOR
    safe (demo) mode: $demo
    colors: $colors
    logs: $log_enabled, $log_file

EOF
}

rule_end="SUBSYSTEM==\"usb\", ENV{ACTION}==\"add\", ENV{DEVTYPE}==\"usb_device\", RUN+=\""$trigger_cmd_add"\", ATTR{authorized}=\"0\", OPTIONS+=\"last_rule\"
LABEL=\"end\""

read_values() {
    while read key value; do
        case "$key" in
        "idVendor")
            vendors+=("${value:2:4}")
            ;;
        "idProduct")
            products+=("${value:2:4}")
            ;;
        "iSerial")
            serials+=("${value:2}")
            ;;
        "iProduct")
            products_name+=("${value:2}")
            ;;
        esac
    done < <(lsusb -v 2>/dev/null)
}

show_values() {
    for ((i = 0; i < "${#vendors[@]}"; i++)); do
        show_usbs=" $i"
        [[ -z ${products_name[$i]} ]] || show_usbs="${show_usbs} Name=${products_name[$i]//\?/ },"
        show_usbs="${show_usbs} Vendor=${vendors[$i]}, Product=${products[$i]}"
        [[ -z ${serials[$i]} ]] || show_usbs="${show_usbs}, Serial=${serials[$i]}"
        echo "$show_usbs"
    done
}

eject_product() {
    if [[ -z ${products_name[$number]} ]]; then
        rulevar+="\n${string_eject}\n"
    else
        rulevar+="\n#${products_name[$number]}"
        rulevar+="\n${string_eject}\n"
    fi
}

choose_remove() {
    message "\nChoose number to add"
    read -e number
    [[ -z "${vendors[$number]}" || !($number == ?(-)+([0-9])) ]] && die "wrong number"

    string_eject="SUBSYSTEM==\"usb\", ENV{ID_VENDOR_ID}==\""${vendors[$number]}"\", ENV{ID_MODEL_ID}==\""${products[$number]}"\""
    [[ -z ${serials[$number]} ]] || string_eject="${string_eject}, ENV{ID_SERIAL_SHORT}==\""${serials[$number]}"\""
    string_eject="${string_eject}, ACTION==\"remove\", RUN+=\""$trigger_cmd_remove"\", OPTIONS+=\"last_rule\""

    [[ -f "${rule_file}.off" ]] && rule_file="${rule_file}.off"

    if [[ ! -f "$rule_file" ]]; then
        rulevar='# blackusb rules file\n'
        eject_product
    else
        rulevar="$(<$rule_file)"
        if [[ "$rulevar" =~ .*"$rule_end".* ]]; then
            rulevar="${rulevar%%$rule_end}"
            rulevar="${rulevar/%$'\n'/}"
            eject_product
            rulevar+="\n$rule_end"
        else
            eject_product
        fi
    fi

    echo -e "$rulevar" >"$rule_file"
    udevadm control --reload
    message "\nAdded:\n${products_name[$number]//\?/ } ${vendors[$number]} ${products[$number]} ${serials[$number]}"
}

gen_whitelist() {
    count=0
    [[ -f "${rule_file}.off" ]] && rule_file="${rule_file}.off"

    if [[ ! -f "$rule_file" ]]; then
        rulevar='# blackusb rules file\n'
    else
        rulevar="$(<$rule_file)"
        rulevar="${rulevar%%$rule_end}"
        rulevar="${rulevar/%$'\n'/}"
    fi

    for ((i = 0; i < "${#vendors[@]}"; i++)); do
        string="SUBSYSTEM==\"usb\", ATTR{idVendor}==\""${vendors[$i]}"\", ATTR{idProduct}==\""${products[$i]}"\""
        [[ -z ${serials[$i]} ]] || string="${string}, ATTR{serial}==\""${serials[$i]}"\""
        string="${string}, ENV{ACTION}==\"add\", GOTO=\"end\""

        if [[ !("$rulevar" =~ .*"$string".*) ]]; then
            if [[ -z ${products_name[$i]} ]]; then
                rulevar+="\n${string}\n"
            else
                rulevar+="\n#${products_name[$i]}"
                rulevar+="\n${string}\n"
            fi
            ((count++))
        fi
    done

    rulevar+="\n$rule_end"
    echo -e "$rulevar" >"$rule_file"
    udevadm control --reload
}

del_rule() {
    [[ -f "${rule_file}.off" ]] && rule_file="${rule_file}.off"
    if [[ -f "$rule_file" ]]; then
        rm "$rule_file" && message "$rule_file deleted" || die "error deleting $rule_file"
        udevadm control --reload
    else
        die "$rule_file does not exist"
    fi
}

deactivate() {
    if [[ -f "$rule_file" ]]; then
        mv "$rule_file" "${rule_file}.off"
        udevadm control --reload
        message "blackusb deactivated"
    else
        die "$rule_file does not exist"
    fi
}

activate() {
    if [[ -f "${rule_file}.off" ]]; then
        mv "${rule_file}.off" "$rule_file"
        udevadm control --reload
        message "blackusb activated"
    else
        read_values && gen_whitelist && message "rules refreshed, $count rules added, blackusb activated"
    fi
}

edit_rules() {
    if [[ -f "${rule_file}.off" ]]; then
        die "blackusb deactivated, activate it first"
    elif [[ ! -f "${rule_file}" ]]; then
        die "udev file does not exist, activate blackusb first"
    else
        "$EDITOR" "$rule_file"
    fi
}

trigger() {
    read_values
    rulevar="$(<$rule_file)"

    for ((i = 0; i < "${#vendors[@]}"; i++)); do
        string="SUBSYSTEM==\"usb\", ATTR{idVendor}==\""${vendors[$i]}"\", ATTR{idProduct}==\""${products[$i]}"\""
        [[ -z ${serials[$i]} ]] || string="${string}, ATTR{serial}==\""${serials[$i]}"\""

        if [[ !("$rulevar" =~ .*"$string".*) ]]; then
            [[ -z ${products_name[$i]} ]] || string+="\n${products_name[$i]}"
            newdevice+="${string}"
        fi
    done

    trigger_msg="\n$(date '+%Y-%m-%d %H:%M:%S') Blackusb triggered!\n"
    [[ -z $newdevice ]] && trigger_msg+="Device ejected" || trigger_msg+="Unknown Device Blocked: $newdevice"
    if [[ $demo = 'yes' ]]; then
        echo -e "$trigger_msg \nDemo mode" >>"$log_file"
    else
        [[ $log_enabled = 'yes' ]] && (echo -e "$trigger_msg" >>"$log_file" && echo -e "$trigger_msg" | systemd-cat --priority=7)
        for i in "${commands_list[@]}"; do
            eval "$i"
        done
    fi
}

case $1 in
g | gen)
    read_values && gen_whitelist && message "rules refreshed, $count rules added"
    [[ "${rule_file##*.}" = 'off' ]] && message "blackusb inactive"
    ;;

d | del)
    del_rule
    ;;

x | off)
    deactivate
    ;;

o | on)
    activate
    ;;

t | trigger)
    trigger
    ;;

e | editor)
    edit_rules
    ;;

s | show)
    read_values && show_values
    ;;

j | eject)
    read_values && show_values && choose_remove
    [[ "${rule_file##*.}" = 'off' ]] && message "blackusb inactive"
    ;;

*)
    usage
    ;;
esac
echo "Done"
