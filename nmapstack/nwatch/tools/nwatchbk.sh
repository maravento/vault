#!/bin/bash
# maravento.com
#
################################################################################
#
# Nwatch Backup
# FILE: tools/nwatchbk.sh
#
# USAGE:
# sudo bash nwatchbk.sh
#
# LOG: /var/log/nwatch.log
#
################################################################################

set -euo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# path for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# root check
if [ "$(id -u)" != 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

# logging
log_file="/var/log/nwatch.log"
log() {
    local message="$(date '+%Y-%m-%d %H:%M:%S') $1"
    echo "$message" >> "$log_file" 2>/dev/null || true
    if [[ "$1" == ERROR:* ]]; then echo "$message" >&2; else echo "$message"; fi
}

# prevent overlapping runs
script_lock="/var/lock/nwatchbk.lock"
(umask 077; : >> "$script_lock") || { log "ERROR: cannot open backup lock -abort"; exit 1; }
exec 200>"$script_lock"
flock -n 200 || { log "ERROR: nwatchbk is already running -abort"; exit 1; }

# dependencies
for dep_pkg in python3 zip coreutils findutils util-linux grep; do
    dpkg -s "$dep_pkg" &>/dev/null || { log "ERROR: dependency '$dep_pkg' is not installed -abort"; exit 1; }
done

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

nwatch_env="/etc/nwatch/nwatch.env"

# ------------------------------------------------------------------------------
# ENV
# ------------------------------------------------------------------------------

# PERMS
env_specs=("$nwatch_env root:www-data 640")
for env_spec in "${env_specs[@]}"; do
    read -r env_path env_owner_want env_perms_want <<< "$env_spec"
    [ -f "$env_path" ] && [ ! -L "$env_path" ] || { log "ERROR: nwatch.env not found or invalid -abort"; exit 1; }
    env_owner=$(stat -c '%U:%G' "$env_path")
    env_perms=$(stat -c '%a' "$env_path")
    if [[ "$env_owner" != "$env_owner_want" || "$env_perms" != "$env_perms_want" ]]; then
        chown "$env_owner_want" "$env_path" && chmod "$env_perms_want" "$env_path" || {
            log "ERROR: cannot fix nwatch.env permissions -abort"; exit 1;
        }
    fi
done
unset env_specs env_spec env_path env_owner_want env_perms_want env_owner env_perms

# LOAD_CONF
source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/nwatchenv.sh"
env_keys='BACKUP_DIR'

# LOAD
load_nwatch_env "$nwatch_env" "$env_keys"

# KEY CHECK
if ! grep -q '^BACKUP_DIR=' "$nwatch_env" || [[ -z "${BACKUP_DIR:-}" || "$BACKUP_DIR" != /* ]]; then
    log "ERROR: BACKUP_DIR missing or invalid in nwatch.env -abort"
    exit 1
fi
backup_dir=$(realpath -m -- "$BACKUP_DIR") || { log "ERROR: cannot resolve BACKUP_DIR -abort"; exit 1; }
case "$backup_dir/" in
    /var/www/nwatch/*|/etc/nwatch/*) log "ERROR: BACKUP_DIR overlaps Nwatch files -abort"; exit 1 ;;
esac

# ------------------------------------------------------------------------------
# BACKUP
# ------------------------------------------------------------------------------

log "EVENT: nwatchbk start..."
install -d -m 700 -o root -g root "$backup_dir"
backup_zip="$backup_dir/nwatchbk_$(date +%Y%m%d_%H%M%S).zip"
backup_part="${backup_zip}.part"
find "$backup_dir" -mindepth 1 -maxdepth 1 ! -name 'nwatchbk_*.zip' -exec rm -rf {} +
backup_stage=$(mktemp -d "$backup_dir/nwatchbk-stage.XXXXXX")
trap 'rm -f -- "$backup_part"; rm -rf -- "$backup_stage"' EXIT

backup_list=()
for backup_item in /etc/nwatch /var/www/nwatch /etc/apache2/sites-available/nwatch.conf /etc/logrotate.d/nwatch /etc/cron.d/nwatch; do
    [ ! -e "$backup_item" ] || backup_list+=("$backup_item")
done
(( ${#backup_list[@]} > 0 )) || { log "ERROR: Nwatch backup paths not found -abort"; exit 1; }

if [ -f /var/www/nwatch/data/nwatch.db ]; then
    if ! python3 - "$backup_stage" <<'SQLITE_BACKUP'
import os, sqlite3, stat, sys
stage = sys.argv[1]
target = os.path.join(stage, 'var/www/nwatch/data/nwatch.db')
os.makedirs(os.path.dirname(target), exist_ok=True)
with sqlite3.connect('file:/var/www/nwatch/data/nwatch.db?mode=ro', uri=True, timeout=30) as source:
    with sqlite3.connect(target) as destination:
        source.backup(destination)
original = os.stat('/var/www/nwatch/data/nwatch.db')
os.chmod(target, stat.S_IMODE(original.st_mode))
os.chown(target, original.st_uid, original.st_gid)
SQLITE_BACKUP
    then
        log "ERROR: cannot snapshot nwatch.db -abort"
        exit 1
    fi
fi

if ! (umask 077; zip -r -q -y "$backup_part" "${backup_list[@]}" -x '*/nwatch.db' '*/nwatch.db-wal' '*/nwatch.db-shm'); then
    log "ERROR: cannot create Nwatch archive -abort"
    exit 1
fi
if [ -f "$backup_stage/var/www/nwatch/data/nwatch.db" ]; then
    if ! (cd "$backup_stage" && zip -q "$backup_part" var/www/nwatch/data/nwatch.db); then
        log "ERROR: cannot archive nwatch.db snapshot -abort"
        exit 1
    fi
fi
zip -T -q "$backup_part" || { log "ERROR: invalid Nwatch archive -abort"; exit 1; }
if ! { chmod 600 "$backup_part" && mv -T -- "$backup_part" "$backup_zip"; }; then
    log "ERROR: cannot publish Nwatch archive -abort"
    exit 1
fi

shopt -s nullglob
old_backups=("$backup_dir"/nwatchbk_*.zip)
if (( ${#old_backups[@]} > 3 )); then
    printf '%s\0' "${old_backups[@]}" | sort -z | head -z -n -3 | xargs -0 -r rm -f --
fi
rm -rf -- "$backup_stage" || { log "ERROR: cannot remove backup temporary directory -abort"; exit 1; }
trap - EXIT
log "INFO: backup written to $(basename "$backup_zip")"

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

log "EVENT: nwatchbk done"
