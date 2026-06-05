#!/bin/bash
# maravento.com
#
################################################################################
#
# MAC Address Consistency Checker (uhotspot)
#
# DESCRIPTION:
#   Diagnostic tool that verifies the presence and consistency of one or more
#   MAC addresses across all DHCP/ACL data sources used by pydhcpd and
#   uhotspot. Designed for troubleshooting client connectivity issues and
#   validating that ACL state is coherent after lease/block operations.
#
# USAGE:
#   sudo bash ucheck.sh <MAC> [MAC2] [MAC3] ...
#
# EXAMPLES:
#   sudo bash ucheck.sh 9c:c7:d3:70:99:f8
#   sudo bash ucheck.sh ce:8b:c0:43:aa:bb 42:20:52:94:cc:dd
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
#   0 - All MACs consistent (or no consistency issues detected)
#   1 - One or more consistency warnings found
#   2 - Usage error (no MACs given, not root)
#
# REQUIREMENTS:
#   - Root privileges (files are owned by root / pydhcpd)
#   - pydhcpd and uhotspot installed with standard paths
#
################################################################################

set -u

# Paths
GUEST_PENDING="/etc/uhotspot/guest-pending.txt"
MAC_HOTSPOT="/etc/uhotspot/mac-hotspot.txt"
GRACE_DHCP="/etc/acl/acl_dhcp/gracedhcp.txt"
BLOCK_DHCP="/etc/acl/acl_dhcp/blockdhcp.txt"
ACL_MAC_DIR="/etc/acl/acl_mac"
LEASES_FILE="/etc/pydhcp/pydhcpd.leases"

# Colors (disabled if stdout is not a terminal)
# Bold/bright variants for readability on dark backgrounds.
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

# Root check
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must be run as root" >&2
    exit 2
fi

if [ $# -eq 0 ]; then
    echo "Usage: $(basename "$0") <MAC> [MAC2] ..." >&2
    exit 2
fi

# Helpers
warn() {
    printf "  ${YELLOW}[!] %s${NC}\n" "$*"
}

found_in() {
    grep -qi "$1" "$2" 2>/dev/null
}

# Main
warnings=0
checked=0
skipped=0

for mac in "$@"; do
    [ -z "$mac" ] && continue

    # Validate MAC format (XX:XX:XX:XX:XX:XX, hex only)
    if ! echo "$mac" | grep -qiE '^([0-9a-f]{2}:){5}[0-9a-f]{2}$'; then
        printf "${RED}[!] Invalid MAC format: %s (expected XX:XX:XX:XX:XX:XX)${NC}\n\n" "$mac"
        skipped=$((skipped+1))
        continue
    fi

    checked=$((checked+1))

    printf "${WHITE}=== %s ===${NC}\n" "$mac"

    # Presence checks
    in_pending=0; in_hotspot=0; in_grace=0; in_block=0; in_acl=0; in_leases=0

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
    if found_in "$mac" "$LEASES_FILE"; then in_leases=1; printf "$OK\n"; else printf "$NO\n"; fi

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
        printf "  ${CYAN}[i] In gracedhcp without active lease (normal -- short pool lease / limited range)${NC}\n"
    fi

    if [ $in_pending -eq 1 ] && [ $in_hotspot -eq 1 ]; then
        warn "In guest-pending AND mac-hotspot -- should move from pending to hotspot, not both"
        warnings=$((warnings+1))
    fi

    total=$((in_pending + in_hotspot + in_grace + in_block + in_acl + in_leases))
    if [ $total -eq 0 ]; then
        printf "  ${YELLOW}[!] MAC not found in any data source${NC}\n"
    fi

    echo ""
done

if [ $checked -eq 0 ]; then
    printf "${RED}No valid MACs to check${NC}\n"
    exit 2
fi

printf "${WHITE}%d checked${NC}" "$checked"
[ $skipped -gt 0 ] && printf ", ${RED}%d skipped (bad format)${NC}" "$skipped"
[ $warnings -gt 0 ] && printf ", ${YELLOW}%d warning(s)${NC}" "$warnings"
printf "\n"

[ $warnings -gt 0 ] && exit 1
exit 0
