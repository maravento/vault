#!/bin/bash
# maravento.com
#
################################################################################
#
# BlackShield
# File Extensions/Patterns/User-Agents/Hex-String to Block
#
# OVERVIEW
# This script builds Squid and Samba ACLs for ransomware-related file
# extensions/patterns and for malicious User-Agent strings, by downloading
# and aggregating several public source lists and then filtering out
# entries that are not safe or meaningful as extension patterns.
#
# PIPELINE (in order)
# 1. Download bad User-Agent list -> normalize -> append to
#    acl/squid/blockua.txt (deduplicated).
# 2. Download multiple ransomware extension/pattern lists -> concatenate
#    into source_lst.txt.
# 3. Normalize: keep ASCII-only lines, trim whitespace, drop empty lines,
#    sort/dedupe -> acl/normalized_lst.txt.
# 4. Normalize extension forms: "ext", ".ext", "_ext", "-ext" all become
#    "*.ext" so equivalent notations are treated the same.
# 5. Filter to simple "*.ext" patterns only (single leading wildcard, no
#    internal wildcards/whitespace) -> acl/output_lst.txt. Anything else
#    (bare filenames, multi-pattern lines separated by "/", lines with
#    embedded spaces, [ID]/[KEY] placeholders, or entries containing
#    unsafe regex/glob metacharacters [ ] @ { } ( ) ? ^) is routed to
#    acl/discarded_lst.txt for manual review.
# 6. Apply acl/rw/wl.txt as an exact-match administrator whitelist
#    (entries removed verbatim from acl/output_lst.txt).
# 7. Discard ransom-note-style entries: anything ending in a whitelisted
#    document extension (*.ext) or an extra segment plus a whitelisted
#    extension (*.algo.ext), e.g. "*.DATA_RECOVERY.html", "*.README.txt".
# 8. Discard entries whose extension segment is implausibly long (>35
#    chars), which are typically ransom note filenames or attacker IDs
#    rather than real encryption extensions, e.g.
#    "*.NEED_TO_MAKE_THE_PAYMENT_IN_MAXIM_24_HOURS...".
# 9. Generate acl/squid/rwext.txt: a Squid url_regex ACL derived from
#    acl/output_lst.txt.
# 10. Generate acl/smb/ransom_veto.txt: a Samba "veto files" line derived
#     from acl/output_lst.txt.
# 11. Merge acl/smb/ransom_veto.txt with the static acl/smb/common_veto.txt
#     into acl/smb/vetofiles.txt.
#
# NOTE on acl/rw/rw.txt:
# - Administrator-defined additions, always merged into acl/output_lst.txt
#   regardless of the source feeds (see step 5/6 in the script body).
#
# NOTE on acl/rw/wl.txt:
# - One pattern per line, format "*.ext".
# - Entries are excluded by exact match (administrator override, step 6).
# - Entries are also used in step 7 to detect and discard ransom-note-style
#   entries ending in a whitelisted extension, e.g. "*.DATA_RECOVERY.html",
#   "*.README.txt".
# - Do NOT add "*.zip" or "*.rar": these are common legitimate ransomware
#   suffixes (e.g. "*.bart.zip", "*.locked.zip") and would be discarded
#   in step 7 if whitelisted here.
#
################################################################################

set -e

echo "Blackshield Start. Wait..."
printf "\n"

# check no-root
if [ "$(id -u)" == "0" ]; then
    echo "❌ This script should not be run as root."
    exit 1
fi

### VARIABLES
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

wgetd='wget -q -c --no-check-certificate --retry-connrefused --timeout=10 --tries=4'

# Bad User-Agents
if $wgetd -O bad-user-agents.list "https://raw.githubusercontent.com/mitchellkrogza/nginx-ultimate-bad-bot-blocker/refs/heads/master/_generator_lists/bad-user-agents.list"; then
    sed -E 's/\\//g; s#/#-#g' bad-user-agents.list >> acl/squid/blockua.txt
    sort -o acl/squid/blockua.txt -u acl/squid/blockua.txt
    rm -f bad-user-agents.list
    echo "Bad User-Agents for Squid: blockua.txt"
else
    echo "ERROR: failed to download bad-user-agents.list"
fi

# Ransomware
function rw() {
    if $wgetd "$1" -O - >> source_lst.txt; then
        return 0
    else
        echo "ERROR: $1"
        return 1
    fi
}
rw 'https://raw.githubusercontent.com/dannyroemhild/ransomware-fileext-list/refs/heads/master/fileextlist.txt' && sleep 1 || true
rw 'https://raw.githubusercontent.com/eshlomo1/Ransomware-NOTE/refs/heads/main/ransomware-extension-list.txt' && sleep 1 || true
rw 'https://raw.githubusercontent.com/giacomoarru/ransomware-extensions-2024/refs/heads/main/ransomware-extensions.txt' && sleep 1 || true
#rw 'https://raw.githubusercontent.com/kinomakino/ransomware_file_extensions/master/extensions.csv' && sleep 1 || true
rw 'https://raw.githubusercontent.com/nspoab/malicious_extensions/refs/heads/main/list1' && sleep 1 || true

# Normalize raw entries: keep only ASCII, trim whitespace, drop empty lines
grep -P '^[\x00-\x7F]*$' source_lst.txt | sed -E 's/[[:space:]]+$//; s/^[[:space:]]+//' | sed '/^$/d' | sort -u > acl/normalized_lst.txt
#rm -f source_lst.txt

# Treat "ext", ".ext", "_ext", "-ext" and "*.ext" as the same idea:
# normalize all to "*.ext"
# - "ext"   (bare alnum start, no dot/asterisk) -> "*.ext"
# - ".ext"  (leading dot, no asterisk)          -> "*.ext"
# - "_ext"/"-ext" (leading underscore/hyphen)   -> "*._ext" / "*.-ext"
# - "*.ext" (already correct)                   -> unchanged
sed -E 's/^([a-zA-Z0-9][^*[:space:]]*)$/*.\1/; s/^\.([^*[:space:]]*)$/*.\1/; s/^([_-][^*[:space:]]*)$/*.\1/' acl/normalized_lst.txt | sort -u > acl/normalized_lst2.txt
mv acl/normalized_lst2.txt acl/normalized_lst.txt

# Keep only simple "*.ext" patterns (single leading wildcard, no internal
# wildcards or whitespace). Anything else (bare filenames, multi-wildcard
# patterns, patterns with embedded spaces) is not supported by the
# Squid/Samba generation below and is set aside for manual review instead
# of silently corrupting the generated ACLs.
#
# Entries containing bracketed ID/key placeholders such as "[ID-KEY]" or
# "[ID]" are also routed to discarded_lst.txt: external source lists use
# this as template notation (the attacker substitutes a real ID/key at
# infection time), so it never appears literally in real file extensions
# and would only generate a dead rule.
#
# Entries containing other unescaped regex/glob metacharacters
# ([ ] @ { } ( ) ? ^) are routed to discarded_lst.txt as well: square
# brackets are character classes (not literals) in both Squid regex and
# Samba veto glob patterns, '?' and '^' are active wildcards/anchors in
# both, and '@'/'{'/'}'/'('/')' combined with brackets produce malformed
# or unintended ACL rules, e.g. "*.[attacker@tuta.io].kix" or "*.CROWN!?".
UNSAFE_RE='\[[A-Za-z]*ID[A-Za-z_-]*\]|\[KEY\]|[][@{}()?^]'
grep -E '^\*\.[^*[:space:]]+$' acl/normalized_lst.txt | grep -E -v "${UNSAFE_RE}" > acl/output_lst.txt
grep -E -v '^\*\.[^*[:space:]]+$' acl/normalized_lst.txt > acl/discarded_lst.txt
grep -E '^\*\.[^*[:space:]]+$' acl/normalized_lst.txt | grep -E "${UNSAFE_RE}" >> acl/discarded_lst.txt
sort -u -o acl/discarded_lst.txt acl/discarded_lst.txt
#rm -f acl/normalized_lst.txt

# Discarded lst
if [ -s acl/discarded_lst.txt ]; then
    echo "NOTE: $(wc -l < acl/discarded_lst.txt) entries discarded (unsupported pattern format): acl/discarded_lst.txt"
fi

# Apply administrator-defined whitelist (exact match exclusions)
grep -Fivx -f acl/rw/wl.txt acl/output_lst.txt > acl/output_lst.tmp
mv acl/output_lst.tmp acl/output_lst.txt

# Discard entries that look like ransom-note filenames rather than real
# encryption extensions:
# - ends in a whitelisted document extension (*.ext), or
# - ends in an extra segment plus a whitelisted extension (*.algo.ext),
#   e.g. "*.DATA_RECOVERY.html", "*.README.txt"
# - the extension segment itself is implausibly long (ransom note names
#   or attacker IDs, e.g. "*.NEED_TO_MAKE_THE_PAYMENT_IN_MAXIM_24_HOURS...")
WL_EXTS=$(sed 's/^\*\.//' acl/rw/wl.txt | paste -sd '|' -)
grep -iE -v "^\*\.(${WL_EXTS})\*?\$|^\*\.[^.]+\.(${WL_EXTS})\*?\$" acl/output_lst.txt > acl/output_lst.tmp
mv acl/output_lst.tmp acl/output_lst.txt

awk -F'.' '{seg=$0; sub(/^\*\./,"",seg); sub(/\*$/,"",seg); if (length(seg) <= 35) print}' acl/output_lst.txt > acl/output_lst.tmp
mv acl/output_lst.tmp acl/output_lst.txt

# For Squid Extensions/Patterns
sed -E 's/^\*\.//; s/([][(){}+])/\\\1/g; s/^/\\./; s/(.*)/\1([a-zA-Z][0-9]*)?(\\?.*)?$/' acl/output_lst.txt | sort -u > acl/squid/rwext.txt
echo "Ransomware ACL for Squid: rwext.txt"

# For Samba Veto Files
echo "veto files = $(sed 's/^\*\.//' acl/output_lst.txt | sort -u | sed 's/^/*./' | paste -sd '' - | sed 's/*/\/&/g; s/$/\//')" > acl/smb/ransom_veto.txt
echo "Ransomware ACL for Samba: ransom_veto.txt"

# Merge Samba veto lists (ransom_veto.txt + common_veto.txt -> vetofiles.txt)
merge_veto() {
    local dynamic="acl/smb/ransom_veto.txt"
    local static="acl/smb/common_veto.txt"
    local output="acl/smb/vetofiles.txt"

    local static_clean dynamic_clean combined final_output

    static_clean=$(sed 's/^veto files = //' "$static")
    dynamic_clean=$(sed 's/^veto files = //' "$dynamic")

    combined="${static_clean}${dynamic_clean}"
    final_output=$(echo "$combined" | sed 's/\/\//\//g')
    final_output="veto files = $final_output"

    echo "$final_output" > "$output"
}
merge_veto
echo "Merged Samba ACL: vetofiles.txt"

#rm -f acl/output_lst.txt

echo "Done"
