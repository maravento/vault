#!/bin/bash
# maravento.com
#
################################################################################
#
# Suridata Configuration Reader
# FILE: suridataenv.sh
#
# USAGE:
# Loaded by callers with source. Not a standalone command or cron job.
#
################################################################################

load_suridata_env() {
    local conf_file="$1" allowed_keys="$2" env_key env_value env_line
    while IFS= read -r env_line || [[ -n "$env_line" ]]; do
        [[ "$env_line" =~ ^[[:space:]]*[#] ]] && continue
        [[ "$env_line" =~ ^[[:space:]]*$ ]] && continue
        env_key="${env_line%%=*}"
        env_value="${env_line#*=}"
        if [[ ! "$env_line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] \
           || [[ "$env_value" == [[:space:]\"\']* ]] \
           || [[ "$env_value" == *[[:space:]\"\'] ]]; then
            log "ERROR: malformed line in $(basename "$conf_file") -abort"
            exit 1
        fi
        [[ "|$allowed_keys|" == *"|$env_key|"* ]] || continue
        printf -v "$env_key" '%s' "$env_value"
    done < "$conf_file"
}

