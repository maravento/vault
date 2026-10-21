#!/bin/bash
# maravento.com
#
################################################################################
#
# fmssetup -- installer for FMS
#
# DESCRIPTION:
# Installs or uninstalls FMS. Run without sudo.
# Install requires an X11 or Wayland desktop session.
#
# USAGE:
# bash fmssetup.sh --install      Install for a file manager
# bash fmssetup.sh --uninstall    Remove FMS from a file manager
# bash fmssetup.sh                Interactive menu
#
# LOG: fmssetup.log, in this script's directory
#
################################################################################

set -euo pipefail

# no-root check
if [ "$(id -u)" == "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: run fmssetup as a normal user -abort" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

case "${1:-}" in
    -h|--help)
        echo "Usage: bash fmssetup.sh [--install|--uninstall]"
        echo "Without arguments, opens the action menu"
        exit 0
        ;;
esac

# logging
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
log_file="${script_dir}/fmssetup.log"
if ! { > "$log_file"; } 2>/dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot write fmssetup.log -abort" >&2
    exit 1
fi
log() {
    local message="$(date '+%Y-%m-%d %H:%M:%S') $1"
    printf '%s\n' "$message" >> "$log_file" 2>/dev/null || true
    if [[ "$1" == ERROR:* ]]; then
        printf '%s\n' "$message" >&2
    else
        printf '%s\n' "$message"
    fi
}
info() { log "INFO: $*"; }
warn() { log "WARNING: $*"; }
err() { log "ERROR: $*"; }
abort() { err "$*"; exit 1; }

# dependencies
for dep_pkg in coreutils util-linux grep sed; do
    if ! dpkg-query -W -f='${Status}' "$dep_pkg" 2>/dev/null \
        | grep -qx 'install ok installed'; then
        abort "dependency '$dep_pkg' is not installed -abort"
    fi
done

# prevent overlapping runs
script_lock="${script_dir}/fmssetup.lock"
[ ! -L "$script_lock" ] || abort "fmssetup.lock is a symbolic link -abort"
if ! (umask 077; : >> "$script_lock"); then
    abort "cannot open fmssetup.lock -abort"
fi
exec 200>"$script_lock"
if ! flock -n 200; then
    abort "fmssetup is already running -abort"
fi

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
[[ "$data_home" == /* && "$config_home" == /* ]] \
    || abort "XDG data and config paths must be absolute -abort"
install_root="${data_home}/scripts/fms"
install_dir="$install_root"
manifest_file="${install_root}/.fms.manifest"
manager_dir="${install_root}/.managers"
selected_manager=""
integration_path=""

# ------------------------------------------------------------------------------
# OWN VALUES
# ------------------------------------------------------------------------------

script_names=(checkmd5 checksha256 copypath makemd5 makesha256 mountman send2phone)
manager_names=(nautilus caja nemo thunar)
package_names=(python3 zenity libnotify-bin xdg-utils
    cifs-utils sshfs fuse3 pkexec kdeconnect)
required_commands=(python3 zenity notify-send xdg-open mount
    umount mountpoint mount.cifs sshfs fusermount fusermount3 pkexec kdeconnect-cli
    kdeconnect-handler md5sum sha256sum)

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

check_sources() {
    local script_name
    for script_name in "${script_names[@]}"; do
        [ -f "${script_dir}/${script_name}" ] \
            || abort "source $script_name not found -abort"
        [ -r "${script_dir}/${script_name}" ] \
            || abort "cannot read source $script_name -abort"
        bash -n "${script_dir}/${script_name}" >/dev/null 2>&1 \
            || abort "$script_name has invalid Bash syntax -abort"
    done
}

check_owned_root() {
    if [ -e "$install_root" ] || [ -L "$install_root" ]; then
        [ -d "$install_root" ] && [ ! -L "$install_root" ] \
            || abort "fms installation path is not a directory -abort"
        [ -f "$manifest_file" ] && [ ! -L "$manifest_file" ] \
            || abort "fms path exists without its ownership marker -abort"
        [ "$(cat "$manifest_file")" = fms-managed-v1 ] \
            || abort "fms ownership marker is invalid -abort"
    fi
    local owned_path
    for owned_path in "$install_dir" "$manager_dir"; do
        [ ! -L "$owned_path" ] \
            || abort "fms installation contains a linked directory -abort"
        if [ -e "$owned_path" ] && [ ! -d "$owned_path" ]; then
            abort "fms installation contains a directory conflict -abort"
        fi
    done
}

check_registered() {
    [ -f "${manager_dir}/${selected_manager}" ] \
        && [ ! -L "${manager_dir}/${selected_manager}" ] \
        || abort "$selected_manager has no FMS registration -abort"
    [ "$(cat "${manager_dir}/${selected_manager}")" = fms-managed-v1 ] \
        || abort "$selected_manager FMS registration is invalid -abort"
}

set_integration_path() {
    case "$selected_manager" in
        nautilus) integration_path="${data_home}/nautilus/scripts/fms" ;;
        caja) integration_path="${config_home}/caja/scripts/fms" ;;
        nemo) integration_path="${data_home}/nemo/scripts/fms" ;;
        thunar) integration_path="${data_home}/Thunar/sendto" ;;
    esac
}

select_manager() {
    local menu_choice
    while true; do
        echo ""
        echo "File manager"
        echo "1) Nautilus"
        echo "2) Caja"
        echo "3) Nemo"
        echo "4) Thunar (Send To)"
        echo "5) Cancel"
        read -r -p "Select option [5]: " menu_choice \
            || abort "cannot read the file manager choice -abort"
        case "${menu_choice:-5}" in
            1) selected_manager=nautilus; break ;;
            2) selected_manager=caja; break ;;
            3) selected_manager=nemo; break ;;
            4) selected_manager=thunar; break ;;
            5) return 2 ;;
            *) info "invalid option -retry" ;;
        esac
    done
    set_integration_path
}

prepare_dependencies() {
    local dep_pkg command_name
    local missing_packages=()
    local dependency_packages=("${package_names[@]}")
    if ! command -v xclip >/dev/null && ! command -v xsel >/dev/null \
        && ! command -v wl-copy >/dev/null; then
        if [ "${XDG_SESSION_TYPE:-}" = wayland ] \
            || [ -n "${WAYLAND_DISPLAY:-}" ]; then
            dependency_packages+=(wl-clipboard)
        else
            dependency_packages+=(xclip)
        fi
    fi
    for dep_pkg in "${dependency_packages[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$dep_pkg" 2>/dev/null \
            | grep -qx 'install ok installed'; then
            warn "dependency '$dep_pkg' is not installed -alert"
            missing_packages+=("$dep_pkg")
        fi
    done
    if [ "${#missing_packages[@]}" -gt 0 ]; then
        echo ""
        echo "Missing packages: ${missing_packages[*]}"
        echo "sudo will install these packages for the system"
        local confirm_answer
        read -r -p "Install missing packages? [y/N]: " confirm_answer \
            || abort "cannot read the package installation choice -abort"
        if [[ ! "$confirm_answer" =~ ^[yY]$ ]]; then
            abort "required package installation was declined -abort"
        fi
        command -v sudo >/dev/null \
            || abort "dependency 'sudo' is not installed -abort"
        command -v apt-get >/dev/null \
            || abort "dependency 'apt-get' is not installed -abort"
        sudo apt-get update || abort "cannot update APT package lists -abort"
        sudo apt-get install -y "${missing_packages[@]}" \
            || abort "APT dependency installation failed -abort"
    fi
    if ! command -v xclip >/dev/null && ! command -v xsel >/dev/null \
        && ! command -v wl-copy >/dev/null; then
        abort "no clipboard command is available -abort"
    fi
    for command_name in "${required_commands[@]}"; do
        command -v "$command_name" >/dev/null \
            || abort "command '$command_name' not found -abort"
    done
}

remove_integration() {
    local script_name entry_file link_path
    if [ "$selected_manager" = thunar ]; then
        for script_name in "${script_names[@]}"; do
            entry_file="${integration_path}/fms-${script_name}.desktop"
            [ -e "$entry_file" ] || [ -L "$entry_file" ] || continue
            [ -f "$entry_file" ] && [ ! -L "$entry_file" ] \
                && grep -qx 'X-FMS-Managed=true' "$entry_file" \
                || abort "fms-$script_name.desktop is not FMS-owned -abort"
            rm -- "$entry_file" \
                || abort "cannot remove fms-$script_name.desktop -abort"
        done
        return 0
    fi
    [ -e "$integration_path" ] || [ -L "$integration_path" ] || return 0
    [ -d "$integration_path" ] && [ ! -L "$integration_path" ] \
        || abort "$selected_manager FMS path is not a directory -abort"
    for script_name in "${script_names[@]}"; do
        link_path="${integration_path}/${script_name}"
        [ -e "$link_path" ] || [ -L "$link_path" ] || continue
        [ -L "$link_path" ] \
            && [ "$(readlink "$link_path")" = "${install_dir}/${script_name}" ] \
            || abort "$script_name is not an FMS link -abort"
        rm -- "$link_path" || abort "cannot remove $script_name link -abort"
    done
    rmdir -- "$integration_path" \
        || abort "$selected_manager FMS directory is not empty -abort"
}

write_thunar_entries() {
    python3 - "$install_dir" "$integration_path" <<'PYTHON'
import os
import pathlib
import sys
import tempfile

scripts_dir = pathlib.Path(sys.argv[1])
target_dir = pathlib.Path(sys.argv[2])
labels = {
    "checkmd5": "Check MD5",
    "checksha256": "Check SHA256",
    "copypath": "Copy paths",
    "makemd5": "Create MD5 checksums",
    "makesha256": "Create SHA256 checksums",
    "mountman": "Mount or unmount",
    "send2phone": "Send to phone",
}

def desktop_string(value):
    return (value.replace("\\", "\\\\").replace("\n", "\\n")
            .replace("\r", "\\r").replace("\t", "\\t"))

for name, label in labels.items():
    executable = str(scripts_dir / name)
    quoted = executable.replace("%", "%%")
    for character in ("\\", '"', "`", "$"):
        quoted = quoted.replace(character, "\\" + character)
    content = ("[Desktop Entry]\nType=Application\n"
               f"Name=FMS: {label}\n"
               f'Exec={desktop_string(chr(34) + quoted + chr(34))} %F\n'
               "Terminal=false\nIcon=system-run\nX-FMS-Managed=true\n")
    fd, temporary = tempfile.mkstemp(prefix="fms-entry-", dir=target_dir)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            output.write(content)
        os.chmod(temporary, 0o644)
        os.replace(temporary, target_dir / f"fms-{name}.desktop")
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
PYTHON
}

deploy_scripts() {
    local script_name stage_dir
    stage_dir=$(mktemp -d "${install_root}/stage.XXXXXX") \
        || abort "cannot create the FMS staging directory -abort"
    for script_name in "${script_names[@]}"; do
        if ! install -m 755 "${script_dir}/${script_name}" \
            "${stage_dir}/${script_name}"; then
            rm -rf -- "$stage_dir"
            abort "cannot stage $script_name -abort"
        fi
    done
    for script_name in "${script_names[@]}"; do
        if ! mv -fT -- "${stage_dir}/${script_name}" \
            "${install_dir}/${script_name}"; then
            rm -rf -- "$stage_dir"
            abort "cannot replace $script_name -abort"
        fi
        info "updated $script_name"
    done
    rmdir -- "$stage_dir" || abort "cannot remove the FMS staging directory -abort"
}

require_desktop() {
    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        abort "no graphical desktop session detected -abort"
    fi
}

do_install() {
    require_desktop
    local selection_rc=0 script_name
    select_manager || selection_rc=$?
    [ "$selection_rc" -ne 2 ] || return 0
    [ "$selection_rc" -eq 0 ] || exit 1
    check_sources
    check_owned_root
    command -v "$selected_manager" >/dev/null \
        || abort "$selected_manager is not installed -abort"
    prepare_dependencies
    remove_integration
    mkdir -p -- "$install_dir" "$manager_dir" \
        || abort "cannot create FMS installation directories -abort"
    printf '%s\n' fms-managed-v1 > "$manifest_file" \
        || abort "cannot write the FMS ownership marker -abort"
    deploy_scripts
    if [ "$selected_manager" = thunar ]; then
        mkdir -p -- "$integration_path" \
            || abort "cannot create Thunar/sendto -abort"
        write_thunar_entries || abort "cannot create Thunar FMS entries -abort"
    else
        mkdir -p -- "$integration_path" \
            || abort "cannot create $selected_manager FMS directory -abort"
        for script_name in "${script_names[@]}"; do
            ln -s -- "${install_dir}/${script_name}" \
                "${integration_path}/${script_name}" \
                || abort "cannot link $script_name for $selected_manager -abort"
        done
    fi
    printf '%s\n' fms-managed-v1 > "${manager_dir}/${selected_manager}" \
        || abort "cannot register $selected_manager FMS -abort"
    info "installed FMS for $selected_manager"
}

do_uninstall() {
    local selection_rc=0 confirm_answer script_name registered_manager
    select_manager || selection_rc=$?
    [ "$selection_rc" -ne 2 ] || return 0
    [ "$selection_rc" -eq 0 ] || exit 1
    check_owned_root
    check_registered
    echo "Remove FMS from $selected_manager? Logs and profiles will remain"
    read -r -p "Continue? [y/N]: " confirm_answer \
        || abort "cannot read the uninstall choice -abort"
    [[ "$confirm_answer" =~ ^[yY]$ ]] || return 0
    remove_integration
    rm -- "${manager_dir}/${selected_manager}" \
        || abort "cannot remove $selected_manager FMS registration -abort"
    for registered_manager in "${manager_names[@]}"; do
        if [ -e "${manager_dir}/${registered_manager}" ] \
            || [ -L "${manager_dir}/${registered_manager}" ]; then
            info "removed FMS from $selected_manager"
            return 0
        fi
    done
    for script_name in "${script_names[@]}"; do
        rm -f -- "${install_dir}/${script_name}" \
            || abort "cannot remove $script_name -abort"
    done
    rm -f -- "$manifest_file" \
        || abort "cannot remove the FMS ownership marker -abort"
    rmdir -- "$manager_dir" "$install_root" \
        || abort "FMS installation directory is not empty -abort"
    info "removed FMS from $selected_manager"
}

# ------------------------------------------------------------------------------
# MENU
# ------------------------------------------------------------------------------

show_menu() {
    local menu_option
    while true; do
        echo ""
        echo "FMS installer"
        echo "1) Install"
        echo "2) Uninstall"
        echo "3) Exit"
        read -r -p "Select option [3]: " menu_option \
            || abort "cannot read the installer menu choice -abort"
        case "${menu_option:-3}" in
            1) do_install; break ;;
            2) do_uninstall; break ;;
            3) exit 0 ;;
            *) info "invalid option -retry" ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# ACTIONS
# ------------------------------------------------------------------------------

log "fmssetup start..."
case "${1:-}" in
    --install) do_install ;;
    --uninstall) do_uninstall ;;
    "") show_menu ;;
    *)
        err "unknown option $1 -abort"
        echo "Usage: bash fmssetup.sh [--install|--uninstall]"
        exit 1
        ;;
esac

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

log "fmssetup done at: $(date '+%Y-%m-%d %H:%M:%S')"
