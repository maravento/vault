#!/bin/bash
# maravento.com
#
################################################################################
#
# MAC Address Consistency Checker (uhotspot) — Interactive Menu
#
# DESCRIPTION:
#   Diagnostic tool that verifies the presence and consistency of one or more
#   MAC addresses across all DHCP/ACL data sources used by pydhcpd and
#   uhotspot. Designed for troubleshooting client connectivity issues and
#   validating that ACL state is coherent after lease/block operations.
#
# USAGE:
#   sudo bash ucheck.sh
#
# MENU OPTIONS:
#   1. Check MAC          - verify a single MAC across all data sources
#   2. Grace period       - list all MACs in grace period with time remaining
#   3. Consistency check  - check all MACs from all sources + system summary
#   4. Search by IP/name  - find MAC by IP or hostname and run consistency check
#   5. Exit
#
# DATA SOURCES CHECKED:
#   guest-pending.txt  - Clients awaiting captive-portal authentication
#   mac-hotspot.txt    - Clients authorized through the hotspot portal
#   gracedhcp.txt      - Clients in the 24-hour grace period after hotspot auth
#   blockdhcp.txt      - Blocked/unknown MACs (quarantine pool, short lease)
#   acl_mac/*.txt      - Permanent ACL lists (proxy, transparent, unlimited)
#   pydhcpd.leases     - Active DHCP lease file
#
# CONSISTENCY RULES:
#   A MAC should appear in only one logical state at a time. The checker
#   flags violations but some transient states are expected:
#
#   State            | Expected presence
#   -----------------+---------------------------------------------------
#   Blocked          | blockdhcp only. NOT in acl_mac, grace or leases
#   Grace period     | gracedhcp Y, leases Y (may be absent briefly
#                    | due to short 60s pool lease and limited range)
#   ACL permanent    | acl_mac Y, NOT in blockdhcp
#   Pending portal   | guest-pending only
#   Hotspot auth     | mac-hotspot Y, gracedhcp Y
#
# EXIT CODES:
#   0 - Normal exit
#   2 - Usage error (not root)
#
# REQUIREMENTS:
#   - Root privileges (files are owned by root / pydhcpd)
#   - pydhcpd and uhotspot installed with standard paths
#
################################################################################

set -u

BLOCKDHCP_GRACE_SECONDS=86400

# Paths
GUEST_PENDING="/etc/uhotspot/guest-pending.txt"
MAC_HOTSPOT="/etc/uhotspot/mac-hotspot.txt"
GRACE_DHCP="/etc/acl/acl_dhcp/gracedhcp.txt"
BLOCK_DHCP="/etc/acl/acl_dhcp/blockdhcp.txt"
ACL_MAC_DIR="/etc/acl/acl_mac"
LEASES_FILE="/etc/pydhcp/pydhcpd.leases"

ALL_SOURCES=(
    "$GUEST_PENDING"
    "$MAC_HOTSPOT"
    "$GRACE_DHCP"
    "$BLOCK_DHCP"
    "$LEASES_FILE"
)

# Colors
if [ -t 1 ]; then
    GREEN='\033[1;32m'
    RED='\033[1;31m'
    YELLOW='\033[1;33m'
    CYAN='\033[1;36m'
    WHITE='\033[1;37m'
    NC='\033[0m'
else
    GREEN="" RED="" YELLOW="" CYAN="" WHITE="" NC=""
fi

OK="${GREEN}Y${NC}"
NO="${RED}N${NC}"

# ─── Root check ──────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must be run as root" >&2
    exit 2
fi

# ─── Helpers ─────────────────────────────────────────────────────────────────
warn() {
    printf "  ${YELLOW}[!] %s${NC}\n" "$*"
}

info() {
    printf "  ${CYAN}[i] %s${NC}\n" "$*"
}

found_in() {
    grep -qiF ";$1;" "$2" 2>/dev/null
}

found_in_leases() {
    grep -qiF "$1" "$2" 2>/dev/null
}

valid_mac() {
    echo "$1" | grep -qiE '^([0-9a-f]{2}:){5}[0-9a-f]{2}$'
}

press_enter() {
    echo ""
    read -rp "  Press ENTER to continue..." _
}

# ─── Option 1: Check single MAC ──────────────────────────────────────────────
check_mac() {
    local mac="$1"
    local warnings=0

    printf "${WHITE}=== %s ===${NC}\n" "$mac"

    local in_pending=0 in_hotspot=0 in_grace=0 in_block=0 in_acl=0 in_leases=0

    printf "  guest-pending.txt: "
    if found_in "$mac" "$GUEST_PENDING"; then in_pending=1; printf "$OK\n"; else printf "$NO\n"; fi

    printf "  mac-hotspot.txt:   "
    if found_in "$mac" "$MAC_HOTSPOT"; then in_hotspot=1; printf "$OK\n"; else printf "$NO\n"; fi

    printf "  gracedhcp.txt:     "
    if found_in "$mac" "$GRACE_DHCP"; then in_grace=1; printf "$OK\n"; else printf "$NO\n"; fi

    printf "  blockdhcp.txt:     "
    if found_in "$mac" "$BLOCK_DHCP"; then in_block=1; printf "$OK\n"; else printf "$NO\n"; fi

    printf "  acl_mac/*.txt:     "
    if grep -rqi "$mac" "$ACL_MAC_DIR"/ 2>/dev/null; then
        in_acl=1; printf "$OK\n"
        grep -rli "$mac" "$ACL_MAC_DIR"/ 2>/dev/null | sed 's/^/        /'
    else
        printf "$NO\n"
    fi

    printf "  pydhcpd.leases:    "
    if found_in_leases "$mac" "$LEASES_FILE"; then in_leases=1; printf "$OK\n"; else printf "$NO\n"; fi

    # Grace period time remaining
    if [ $in_grace -eq 1 ] && [ -f "$GRACE_DHCP" ]; then
        local line ts remaining
        line=$(grep -iF ";${mac};" "$GRACE_DHCP" 2>/dev/null | head -1)
        ts=$(echo "$line" | awk -F';' '{print $5}')
        if [[ "$ts" =~ ^[0-9]+$ ]]; then
            remaining=$(( (ts + BLOCKDHCP_GRACE_SECONDS) - $(date +%s) ))
            if (( remaining > 0 )); then
                printf "  Grace expires in : ${GREEN}%dh %dm${NC}\n" "$((remaining/3600))" "$(( (remaining%3600)/60 ))"
            else
                printf "  Grace expires in : ${RED}EXPIRED${NC}\n"
            fi
        fi
    fi

    # Consistency checks
    if [ $in_block -eq 1 ]; then
        [ $in_acl -eq 1 ]    && { warn "In blockdhcp AND acl_mac -- should be in one, not both"; warnings=$((warnings+1)); }
        [ $in_grace -eq 1 ]  && { warn "In blockdhcp AND gracedhcp -- contradictory state"; warnings=$((warnings+1)); }
        [ $in_leases -eq 1 ] && { warn "In blockdhcp AND leases -- lease should have been cleared"; warnings=$((warnings+1)); }
    fi

    if [ $in_acl -eq 1 ] && [ $in_block -eq 1 ]; then
        warn "In acl_mac AND blockdhcp -- pyleases should have removed it from blockdhcp"
        warnings=$((warnings+1))
    fi

    if [ $in_grace -eq 1 ] && [ $in_leases -eq 0 ]; then
        info "In gracedhcp without active lease (normal -- short pool lease / limited range)"
    fi

    if [ $in_pending -eq 1 ] && [ $in_hotspot -eq 1 ]; then
        warn "In guest-pending AND mac-hotspot -- should move from pending to hotspot, not both"
        warnings=$((warnings+1))
    fi

    local total=$((in_pending + in_hotspot + in_grace + in_block + in_acl + in_leases))
    if [ $total -eq 0 ]; then
        printf "  ${YELLOW}[!] MAC not found in any data source${NC}\n"
    fi

    echo ""
    return $warnings
}

menu_check_mac() {
    echo ""
    local mac
    while true; do
        read -rp "  Enter MAC address (XX:XX:XX:XX:XX:XX): " mac
        mac=$(echo "$mac" | xargs | tr '[:upper:]' '[:lower:]')
        if valid_mac "$mac"; then
            break
        fi
        printf "  ${RED}Invalid MAC format, try again${NC}\n"
    done
    echo ""
    check_mac "$mac"
    press_enter
}

# ─── Option 2: Grace period status ───────────────────────────────────────────
menu_grace_period() {
    echo ""
    if [ ! -f "$GRACE_DHCP" ]; then
        printf "  ${RED}File not found: %s${NC}\n" "$GRACE_DHCP"
        press_enter
        return
    fi

    local now total=0 expired=0
    now=$(date +%s)

    printf "  ${WHITE}%-20s %-18s %-25s %s${NC}\n" "MAC" "IP" "NAME" "EXPIRES IN"
    printf "  %s\n" "$(printf -- '-%.0s' {1..75})"

    while IFS=';' read -r _ mac ip name ts _rest; do
        [[ -z "$mac" || -z "$ts" ]] && continue
        [[ ! "$ts" =~ ^[0-9]+$ ]] && continue
        total=$((total+1))
        local remaining=$(( (ts + BLOCKDHCP_GRACE_SECONDS) - now ))
        if (( remaining > 0 )); then
            local h=$(( remaining/3600 ))
            local m=$(( (remaining%3600)/60 ))
            local color
            if (( remaining < 7200 )); then
                color="$RED"
            elif (( remaining < 21600 )); then
                color="$YELLOW"
            else
                color="$GREEN"
            fi
            printf "  %-20s %-18s %-25s ${color}%dh %dm${NC}\n" "$mac" "$ip" "$name" "$h" "$m"
        else
            expired=$((expired+1))
            printf "  %-20s %-18s %-25s ${RED}EXPIRED${NC}\n" "$mac" "$ip" "$name"
        fi
    done < "$GRACE_DHCP"

    echo ""
    printf "  Total: %d  |  Expired: %d  |  Active: %d\n" "$total" "$expired" "$((total-expired))"
    press_enter
}

# ─── Option 3: Consistency check + system summary ────────────────────────────
menu_consistency() {
    echo ""
    printf "  ${CYAN}Collecting all MACs from all data sources...${NC}\n\n"

    # Collect all unique MACs
    local tmpfile
    tmpfile=$(mktemp)

    # From semicolon-delimited files (field 2)
    for f in "$GUEST_PENDING" "$MAC_HOTSPOT" "$GRACE_DHCP" "$BLOCK_DHCP"; do
        [ -f "$f" ] && awk -F';' '{print tolower($2)}' "$f" >> "$tmpfile" 2>/dev/null
    done

    # From acl_mac dir
    grep -rhioE '([0-9a-f]{2}:){5}[0-9a-f]{2}' "$ACL_MAC_DIR"/ 2>/dev/null \
        | tr '[:upper:]' '[:lower:]' >> "$tmpfile"

    # From leases file
    grep -ioE '([0-9a-f]{2}:){5}[0-9a-f]{2}' "$LEASES_FILE" 2>/dev/null \
        | tr '[:upper:]' '[:lower:]' >> "$tmpfile"

    local all_macs
    mapfile -t all_macs < <(sort -u "$tmpfile" | grep -E '^([0-9a-f]{2}:){5}[0-9a-f]{2}$')
    rm -f "$tmpfile"

    local total_warnings=0
    local cnt_grace=0 cnt_block=0 cnt_acl=0 cnt_pending=0 cnt_hotspot=0 cnt_leases=0

    for mac in "${all_macs[@]}"; do
        # Count per state for summary
        found_in "$mac" "$GUEST_PENDING" && cnt_pending=$((cnt_pending+1))
        found_in "$mac" "$MAC_HOTSPOT"   && cnt_hotspot=$((cnt_hotspot+1))
        found_in "$mac" "$GRACE_DHCP"    && cnt_grace=$((cnt_grace+1))
        found_in "$mac" "$BLOCK_DHCP"    && cnt_block=$((cnt_block+1))
        grep -rqi "$mac" "$ACL_MAC_DIR"/ 2>/dev/null && cnt_acl=$((cnt_acl+1))
        found_in_leases "$mac" "$LEASES_FILE" && cnt_leases=$((cnt_leases+1))

        # Run consistency check (only print if warnings)
        local w=0
        local in_pending=0 in_hotspot=0 in_grace=0 in_block=0 in_acl=0 in_leases=0
        found_in "$mac" "$GUEST_PENDING" && in_pending=1
        found_in "$mac" "$MAC_HOTSPOT"   && in_hotspot=1
        found_in "$mac" "$GRACE_DHCP"    && in_grace=1
        found_in "$mac" "$BLOCK_DHCP"    && in_block=1
        grep -rqi "$mac" "$ACL_MAC_DIR"/ 2>/dev/null && in_acl=1
        found_in_leases "$mac" "$LEASES_FILE" && in_leases=1

        if [ $in_block -eq 1 ]; then
            if [ $in_acl -eq 1 ]; then
                [ $w -eq 0 ] && printf "${WHITE}--- %s ---${NC}\n" "$mac"
                warn "In blockdhcp AND acl_mac -- should be in one, not both"
                w=$((w+1))
            fi
            if [ $in_grace -eq 1 ]; then
                [ $w -eq 0 ] && printf "${WHITE}--- %s ---${NC}\n" "$mac"
                warn "In blockdhcp AND gracedhcp -- contradictory state"
                w=$((w+1))
            fi
            if [ $in_leases -eq 1 ]; then
                [ $w -eq 0 ] && printf "${WHITE}--- %s ---${NC}\n" "$mac"
                warn "In blockdhcp AND leases -- lease should have been cleared"
                w=$((w+1))
            fi
        fi
        if [ $in_acl -eq 1 ] && [ $in_block -eq 1 ]; then
            [ $w -eq 0 ] && printf "${WHITE}--- %s ---${NC}\n" "$mac"
            warn "In acl_mac AND blockdhcp -- pyleases should have removed it from blockdhcp"
            w=$((w+1))
        fi
        if [ $in_pending -eq 1 ] && [ $in_hotspot -eq 1 ]; then
            [ $w -eq 0 ] && printf "${WHITE}--- %s ---${NC}\n" "$mac"
            warn "In guest-pending AND mac-hotspot -- should not be in both"
            w=$((w+1))
        fi
        [ $w -gt 0 ] && echo ""
        total_warnings=$((total_warnings+w))
    done

    # Summary
    printf "${WHITE}=== SYSTEM SUMMARY ===${NC}\n"
    printf "  MACs found total  : %d\n" "${#all_macs[@]}"
    printf "  Grace period      : %d\n" "$cnt_grace"
    printf "  Blocked           : %d\n" "$cnt_block"
    printf "  ACL permanent     : %d\n" "$cnt_acl"
    printf "  Pending portal    : %d\n" "$cnt_pending"
    printf "  Hotspot auth      : %d\n" "$cnt_hotspot"
    printf "  Active leases     : %d\n" "$cnt_leases"
    if [ $total_warnings -eq 0 ]; then
        printf "  Warnings          : ${GREEN}0${NC}\n"
    else
        printf "  Warnings          : ${RED}%d${NC}\n" "$total_warnings"
    fi

    press_enter
}

# ─── Option 4: Search by IP or hostname ──────────────────────────────────────
menu_search() {
    echo ""
    local query
    read -rp "  Enter IP address or hostname: " query
    query=$(echo "$query" | xargs | tr '[:upper:]' '[:lower:]')
    if [ -z "$query" ]; then
        printf "  ${RED}Empty query${NC}\n"
        press_enter
        return
    fi

    echo ""
    printf "  ${CYAN}Searching for: %s${NC}\n\n" "$query"

    local found_macs=()
    local tmpfile
    tmpfile=$(mktemp)

    # Search in semicolon-delimited files (all fields)
    for f in "$GUEST_PENDING" "$MAC_HOTSPOT" "$GRACE_DHCP" "$BLOCK_DHCP"; do
        if [ -f "$f" ]; then
            grep -iF "$query" "$f" 2>/dev/null \
                | awk -F';' '{print tolower($2)}' >> "$tmpfile"
        fi
    done

    # Search in acl_mac dir (lines containing query, extract MAC)
    grep -rhiF "$query" "$ACL_MAC_DIR"/ 2>/dev/null \
        | grep -ioE '([0-9a-f]{2}:){5}[0-9a-f]{2}' \
        | tr '[:upper:]' '[:lower:]' >> "$tmpfile"

    # Search in leases file
    grep -iF "$query" "$LEASES_FILE" 2>/dev/null \
        | grep -ioE '([0-9a-f]{2}:){5}[0-9a-f]{2}' \
        | tr '[:upper:]' '[:lower:]' >> "$tmpfile"

    mapfile -t found_macs < <(sort -u "$tmpfile" | grep -E '^([0-9a-f]{2}:){5}[0-9a-f]{2}$')
    rm -f "$tmpfile"

    if [ ${#found_macs[@]} -eq 0 ]; then
        printf "  ${YELLOW}No MACs found matching: %s${NC}\n" "$query"
        press_enter
        return
    fi

    printf "  Found %d MAC(s):\n\n" "${#found_macs[@]}"
    for mac in "${found_macs[@]}"; do
        check_mac "$mac"
    done

    press_enter
}

# ─── Main menu ───────────────────────────────────────────────────────────────
main_menu() {
    while true; do
        clear
        printf "${WHITE}########################################${NC}\n"
        printf "${WHITE}#     ucheck -- MAC Diagnostic Tool    #${NC}\n"
        printf "${WHITE}########################################${NC}\n"
        echo ""
        printf "  1. Check MAC\n"
        printf "  2. Grace period status\n"
        printf "  3. Consistency check + system summary\n"
        printf "  4. Search by IP or hostname\n"
        printf "  5. Exit\n"
        echo ""
        read -rp "  Select option [1-5]: " opt
        case "$opt" in
            1) menu_check_mac ;;
            2) menu_grace_period ;;
            3) menu_consistency ;;
            4) menu_search ;;
            5) echo ""; exit 0 ;;
            *) printf "  ${RED}Invalid option${NC}\n"; sleep 1 ;;
        esac
    done
}

main_menu
