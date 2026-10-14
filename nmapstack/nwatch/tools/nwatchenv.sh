#!/bin/bash
# maravento.com
#
################################################################################
#
# nwatchenv -- shared Bash configuration reader
#
# DESCRIPTION:
# Shared configuration reader for nwatch Bash scripts.
#
# USAGE:
# Loaded by callers with source. Not a standalone command or cron job.
#
################################################################################

load_nwatch_env() {
    local conf_file="$1" conf_keys="$2" env_key env_value env_line env_count=0
    [[ ! -f "$conf_file" ]] && { log "WARNING: $conf_file not found -- fallback"; return 1; }
    while IFS= read -r env_line || [[ -n "$env_line" ]]; do
        env_count=$((env_count + 1))
        [[ "$env_line" =~ ^[[:space:]]*[#] ]] && continue
        [[ "$env_line" =~ ^[[:space:]]*$ ]] && continue
        env_key="${env_line%%=*}"
        env_value="${env_line#*=}"
        if [[ ! "$env_line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] \
           || [[ "$env_value" == [[:space:]\"\']* ]] \
           || [[ "$env_value" == *[[:space:]\"\'] ]]; then
            if [[ ! "$env_line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
                log "ERROR: $(basename "$conf_file"):$env_count not key=value -- abort"
            else
                log "ERROR: $(basename "$conf_file"):$env_count space or quote in value -- abort"
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
