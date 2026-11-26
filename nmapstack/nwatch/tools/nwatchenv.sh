#!/bin/bash
# maravento.com
#
################################################################################
#
# nwatchenv -- shared Bash configuration reader
# FILE: tools/nwatchenv.sh
#
# USAGE:
# COMMAND              ACTION
# source nwatchenv.sh  Load shared environment settings
#
################################################################################

load_nwatch_env() {
    local conf_file="$1" conf_keys="$2" env_key env_value env_line env_count=0
    local env_assignment='^[A-Z][A-Z0-9_]*='
    while IFS= read -r env_line || [[ -n "$env_line" ]]; do
        env_count=$((env_count + 1))
        [[ "$env_line" =~ ^[[:space:]]*[#] ]] && continue
        [[ "$env_line" =~ ^[[:space:]]*$ ]] && continue
        env_key="${env_line%%=*}"
        env_value="${env_line#*=}"
        if [[ ! "$env_line" =~ $env_assignment ]] \
           || [[ "$env_value" == [[:space:]\"\']* ]] \
           || [[ "$env_value" == *[[:space:]\"\'] ]]; then
            if [[ ! "$env_line" =~ $env_assignment ]]; then
                log "ERROR: $(basename "$conf_file"):$env_count not key=value -abort"
            else
                log "ERROR: $(basename "$conf_file"):$env_count space or quote in value -abort"
            fi
            exit 1
        fi
        case " $conf_keys " in
            *" $env_key "*)
                printf -v "$env_key" '%s' "$env_value"
                ;;
        esac
    done < "$conf_file"
}
