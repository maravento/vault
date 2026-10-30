#!/bin/bash
# maravento.com
#
################################################################################
#
# fmssetup -- installer for FMS
# FILE: fmssetup.sh
#
# DESCRIPTION:
# Installs, updates or uninstalls FMS. Run without sudo.
# Update replaces shared scripts without changing file manager integration.
# Caja installation restarts Caja and closes its open windows.
# Install requires an X11 or Wayland desktop session.
#
# USAGE:
# bash fmssetup.sh --install      Install for every file manager found
# bash fmssetup.sh --update       Replace installed shared scripts
# bash fmssetup.sh --uninstall    Remove FMS from every file manager
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
        echo "Usage: bash fmssetup.sh [--install|--update|--uninstall]"
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
for dep_pkg in coreutils util-linux grep sed procps; do
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
found_managers=()

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

is_registered() {
    local marker_file="${manager_dir}/$1"
    [ -f "$marker_file" ] && [ ! -L "$marker_file" ] || return 1
    [ "$(cat "$marker_file")" = fms-managed-v1 ] || return 1
}

integration_path_for() {
    case "$1" in
        nautilus) printf '%s\n' "${data_home}/nautilus/scripts/fms" ;;
        caja) printf '%s\n' "${config_home}/caja/scripts/fms" ;;
        nemo) printf '%s\n' "${data_home}/nemo/scripts/fms" ;;
        thunar) printf '%s\n' "${config_home}/Thunar/uca.xml" ;;
    esac
}

detect_managers() {
    local manager_name
    found_managers=()
    for manager_name in "${manager_names[@]}"; do
        command -v "$manager_name" >/dev/null || continue
        found_managers+=("$manager_name")
    done
    [ "${#found_managers[@]}" -gt 0 ] \
        || abort "no supported file manager is installed -abort"
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
    local manager_name="$1" script_name link_path integration_path
    integration_path=$(integration_path_for "$manager_name")
    if [ "$manager_name" = thunar ]; then
        [ -f "$integration_path" ] && [ ! -L "$integration_path" ] || return 0
        edit_thunar_actions remove "$integration_path" \
            || abort "cannot remove the Thunar FMS actions -abort"
        return 0
    fi
    [ -e "$integration_path" ] || [ -L "$integration_path" ] || return 0
    [ -d "$integration_path" ] && [ ! -L "$integration_path" ] \
        || abort "$manager_name FMS path is not a directory -abort"
    for script_name in "${script_names[@]}"; do
        link_path="${integration_path}/${script_name}"
        [ -e "$link_path" ] || [ -L "$link_path" ] || continue
        [ -L "$link_path" ] \
            && [ "$(readlink "$link_path")" = "${install_dir}/${script_name}" ] \
            || abort "$script_name is not an FMS link -abort"
        rm -- "$link_path" || abort "cannot remove $script_name link -abort"
    done
    rmdir -- "$integration_path" \
        || abort "$manager_name FMS directory is not empty -abort"
}

# Thunar reads its context menu from uca.xml, a file shared with other
# projects, so only the FMS actions are rewritten and the rest is kept.
edit_thunar_actions() {
    python3 - "$1" "$2" "$install_dir" <<'PYTHON'
import hashlib
import os
import pathlib
import sys
import tempfile
import xml.etree.ElementTree as ET

mode = sys.argv[1]
menu_file = pathlib.Path(sys.argv[2])
scripts_dir = pathlib.Path(sys.argv[3])
labels = {
    "checkmd5": "Check MD5",
    "checksha256": "Check SHA256",
    "copypath": "Copy paths",
    "makemd5": "Create MD5 checksums",
    "makesha256": "Create SHA256 checksums",
    "mountman": "Mount or unmount",
    "send2phone": "Send to phone",
}
type_tags = ("directories", "audio-files", "image-files", "text-files",
             "video-files", "other-files")

def is_ours(action):
    command = action.findtext("command") or ""
    return str(scripts_dir) in command

if menu_file.is_file():
    root = ET.parse(str(menu_file)).getroot()
else:
    root = ET.Element("actions")

for action in [item for item in root.findall("action") if is_ours(item)]:
    root.remove(action)

if mode == "remove" and not root.findall("action"):
    menu_file.unlink()
    sys.exit(0)

if mode == "install":
    taken = {action.findtext("unique-id") for action in root.findall("action")}
    for name, label in labels.items():
        digest = hashlib.md5(("fms" + name).encode("utf-8")).hexdigest()
        digits = "".join(character for character in digest
                         if character.isdigit()) or "0"
        unique_id = digits[:8]
        while unique_id in taken:
            unique_id = str(int(unique_id or 0) + 1)
        taken.add(unique_id)
        action = ET.SubElement(root, "action")
        values = (("icon", ""), ("name", label), ("submenu", "FMS"),
                  ("unique-id", unique_id),
                  ("command", 'bash "%s" %%F' % (scripts_dir / name)),
                  ("description", ""), ("range", ""), ("patterns", "*"))
        for tag, text in values:
            ET.SubElement(action, tag).text = text
        for tag in type_tags:
            ET.SubElement(action, tag)

ET.indent(root, space="\t")
menu_file.parent.mkdir(parents=True, exist_ok=True)
fd, temporary = tempfile.mkstemp(prefix="uca-", dir=str(menu_file.parent))
try:
    with os.fdopen(fd, "wb") as output:
        output.write(b'<?xml version="1.0" encoding="UTF-8"?>\n')
        output.write(ET.tostring(root, encoding="utf-8").split(b"?>")[-1])
        output.write(b"\n")
    os.chmod(temporary, 0o644)
    os.replace(temporary, str(menu_file))
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
PYTHON
}

integrate_manager() {
    local manager_name="$1" script_name integration_path
    integration_path=$(integration_path_for "$manager_name")
    if [ "$manager_name" = thunar ]; then
        edit_thunar_actions install "$integration_path" \
            || abort "cannot create the Thunar FMS actions -abort"
        return 0
    fi
    mkdir -p -- "$integration_path" \
        || abort "cannot create $manager_name FMS directory -abort"
    for script_name in "${script_names[@]}"; do
        ln -s -- "${install_dir}/${script_name}" \
            "${integration_path}/${script_name}" \
            || abort "cannot link $script_name for $manager_name -abort"
    done
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

restart_manager() {
    local manager_name="$1"
    pgrep -x "$manager_name" >/dev/null || return 0
    info "restarting $manager_name; its open windows will close"
    # Nautilus exits 255 even when it closes, so its status is not read.
    "$manager_name" -q >/dev/null 2>&1 || true
    sleep 2
    if pgrep -x "$manager_name" >/dev/null; then
        warn "$manager_name could not close; restart it manually -alert"
        return 0
    fi
    # Caja draws the desktop, so it is relaunched; the others start on demand.
    if [ "$manager_name" = caja ]; then
        nohup caja --no-default-window \
            >> "$log_file" 2>&1 200>&- &
    fi
}

do_install() {
    local manager_name installed=false
    require_desktop
    detect_managers
    check_sources
    check_owned_root
    prepare_dependencies
    mkdir -p -- "$install_dir" "$manager_dir" \
        || abort "cannot create FMS installation directories -abort"
    printf '%s\n' fms-managed-v1 > "$manifest_file" \
        || abort "cannot write the FMS ownership marker -abort"
    deploy_scripts
    for manager_name in "${found_managers[@]}"; do
        if is_registered "$manager_name"; then
            info "$manager_name already has FMS -skip"
            continue
        fi
        remove_integration "$manager_name"
        integrate_manager "$manager_name"
        printf '%s\n' fms-managed-v1 > "${manager_dir}/${manager_name}" \
            || abort "cannot register $manager_name FMS -abort"
        info "installed FMS for $manager_name"
        restart_manager "$manager_name"
        installed=true
    done
    [ "$installed" = true ] || info "every installed file manager already has FMS"
}

do_update() {
    local manager_name registered=false
    check_owned_root
    for manager_name in "${manager_names[@]}"; do
        if is_registered "$manager_name"; then
            registered=true
        fi
    done
    [ "$registered" = true ] || abort "FMS is not installed -abort"
    check_sources
    deploy_scripts
    for manager_name in "${manager_names[@]}"; do
        if is_registered "$manager_name"; then
            restart_manager "$manager_name"
        fi
    done
}

do_uninstall() {
    local manager_name confirm_answer script_name
    local registered_managers=()
    check_owned_root
    for manager_name in "${manager_names[@]}"; do
        if is_registered "$manager_name"; then
            registered_managers+=("$manager_name")
        fi
    done
    [ "${#registered_managers[@]}" -gt 0 ] || abort "FMS is not installed -abort"
    echo "Remove FMS from: ${registered_managers[*]}"
    echo "Logs and profiles will remain"
    read -r -p "Continue? [y/N]: " confirm_answer \
        || abort "cannot read the uninstall choice -abort"
    [[ "$confirm_answer" =~ ^[yY]$ ]] || return 0
    for manager_name in "${registered_managers[@]}"; do
        remove_integration "$manager_name"
        rm -- "${manager_dir}/${manager_name}" \
            || abort "cannot remove $manager_name FMS registration -abort"
        info "removed FMS from $manager_name"
        restart_manager "$manager_name"
    done
    for script_name in "${script_names[@]}"; do
        rm -f -- "${install_dir}/${script_name}" \
            || abort "cannot remove $script_name -abort"
    done
    rm -f -- "$manifest_file" \
        || abort "cannot remove the FMS ownership marker -abort"
    rmdir -- "$manager_dir" "$install_root" \
        || abort "FMS installation directory is not empty -abort"
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
        echo "2) Update"
        echo "3) Uninstall"
        echo "4) Exit"
        read -r -p "Select option [4]: " menu_option \
            || abort "cannot read the installer menu choice -abort"
        case "${menu_option:-4}" in
            1) do_install; break ;;
            2) do_update; break ;;
            3) do_uninstall; break ;;
            4) exit 0 ;;
            *) info "invalid option -retry" ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# ACTIONS
# ------------------------------------------------------------------------------

log "EVENT: fmssetup start..."
case "${1:-}" in
    --install) do_install ;;
    --update) do_update ;;
    --uninstall) do_uninstall ;;
    "") show_menu ;;
    *)
        err "invalid option -abort"
        echo "Usage: bash fmssetup.sh [--install|--update|--uninstall]"
        exit 1
        ;;
esac

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

log "EVENT: fmssetup done"
