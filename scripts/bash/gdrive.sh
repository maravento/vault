#!/bin/bash
# maravento.com
#
################################################################################
#
# Mount | Umount Google Drive folder via google-drive-ocamlfuse
# FILE: gdrive.sh
#
# DESCRIPTION: Mounts/unmounts the local user's Google Drive folder,
# auto-detecting the local sudo user. Not run as root.
#
# USAGE: ./gdrive.sh { --start | --stop }
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# no-root check
if [ "$(id -u)" == "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script should not be run as root -abort" >&2
    exit 1
fi

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$script_lock"
if ! flock -n 200; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: script $(basename "$0") is already running -abort" >&2
    exit 1
fi

# dependencies
for dep in libcurl3-gnutls libfuse2t64 libsqlite3-0 fuse3 util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: dependency '$dep' is not installed -abort" >&2
        exit 1
    fi
done

# dependencies (external repo)
for dep in google-drive-ocamlfuse; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: 'google-drive-ocamlfuse' is not installed" >&2
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: run: add-apt-repository ppa:alessandro-strada/ppa -abort" >&2
        exit 1
    fi
done

# local_user detection
detect_local_user() {
    local uid_min uid_max
    local user uid best_user="" best_uid=999999

    uid_min=$(awk '/^UID_MIN/{print $2}' /etc/login.defs 2>/dev/null)
    uid_max=$(awk '/^UID_MAX/{print $2}' /etc/login.defs 2>/dev/null)
    uid_min=${uid_min:-1000}
    uid_max=${uid_max:-60000}

    while IFS=: read -r user _ uid _ _ _ shell; do
        [ "$user" = "root" ] && continue
        [ -z "$uid" ] && continue
        [ "$uid" -lt "$uid_min" ] && continue
        [ "$uid" -gt "$uid_max" ] && continue

        case "$shell" in
            */false|*/nologin) continue ;;
        esac

        id -nG "$user" 2>/dev/null | grep -qw sudo || continue

        if [ "$uid" -lt "$best_uid" ]; then
            best_uid="$uid"
            best_user="$user"
        fi
    done </etc/passwd

    [ -n "$best_user" ] || return 1
    echo "$best_user"
}

if ! local_user=$(detect_local_user); then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no local user; create one with sudo access -abort" >&2
    exit 1
fi

echo "Using local user: $local_user"

echo "$(date '+%Y-%m-%d %H:%M:%S') Gdrive Starting. Wait..."

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

GD="/home/$local_user/gdrive"
if [ -e "$GD" ] && [ ! -d "$GD" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: $GD exists but is not a directory -abort" >&2
    exit 1
fi
if [ ! -d "$GD" ]; then
    mkdir -p "$GD"
    chmod 755 "$GD"
fi

# ------------------------------------------------------------------------------
# ACTIONS
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') gdrive start..."

case "${1:-}" in
--start)
    echo "$(date '+%Y-%m-%d %H:%M:%S') Mount Google Drive..."
    if mountpoint -q "$GD"; then
        echo "$GD is already mounted"
        echo "$(date '+%Y-%m-%d %H:%M:%S') gdrive done at: $(date '+%Y-%m-%d %H:%M:%S')"
        exit 0
    fi
    if ! google-drive-ocamlfuse "$GD"; then
        echo "Failed to mount Google Drive"
        exit 1
    fi
    echo "OK"
    echo "$(date '+%Y-%m-%d %H:%M:%S') gdrive done at: $(date '+%Y-%m-%d %H:%M:%S')"
    exit 0
    ;;
--stop)
    echo "$(date '+%Y-%m-%d %H:%M:%S') Umount Google Drive..."
    if ! mountpoint -q "$GD"; then
        echo "$GD is not mounted"
        echo "$(date '+%Y-%m-%d %H:%M:%S') gdrive done at: $(date '+%Y-%m-%d %H:%M:%S')"
        exit 0
    fi
    if ! fusermount -u "$GD"; then
        echo "Failed to unmount Google Drive"
        exit 1
    fi
    echo "OK"
    echo "$(date '+%Y-%m-%d %H:%M:%S') gdrive done at: $(date '+%Y-%m-%d %H:%M:%S')"
    exit 0
    ;;
*)
    echo "Usage: $0 {--start|--stop}"
    exit 1
    ;;
esac
