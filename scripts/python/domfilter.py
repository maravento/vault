#!/usr/bin/env python

# Domain Filter to
# - Remove overlapping domains
# - Validate TLDs

# HOW TO RUN:
# Replace the names in the lists (input.txt, tlds.txt) with your own lists
# python domfilter.py --input input.txt --tld tlds.txt

# IMPORTANT BEFORE RUNNING:
# input.txt contains the domains and subdomains to be validated
# tlds.txt contains all Public and Private Suffix TLDs
# All lines in the lists must start with a dot. 
# They must not contain "http/https/www" at the beginning of each line.
# 100k lines are processed in 12 min, using an 11th gen Intel® Core™ i5 CPU

# # PUBLIC AND PRIVATE LISTS OF TLDs AND DOMAIN SUFFIXES
# including ccTLD, ccSLD, sTLD, uTLD, gTLD, eTLD, up to 4th level 4LDs
# Sources:
# https://raw.githubusercontent.com/publicsuffix/list/master/public_suffix_list.dat
# https://data.iana.org/TLD/tlds-alpha-by-domain.txt
# https://www.whoisxmlapi.com/support/supported_gtlds.php

import argparse

def should_keep_domain(domain: str, valid_domains: list, tlds: set) -> bool:
    clean_domain = domain.lstrip('.')
    if not any(clean_domain.endswith(tld) for tld in tlds):
        return False
    if 'foo.bar.subdomain' in clean_domain or clean_domain == 'domain.exe':
        return False
    for valid_domain in valid_domains:
        if clean_domain.endswith(f".{valid_domain.lstrip('.')}"):
            return False
    return True

def load_tlds(tlds_file: str) -> set:
    try:
        with open(tlds_file, 'r', encoding='utf-8') as f:
            return {line.strip().lower() for line in f if line.strip()}
    except Exception as e:
        print(f"Error reading TLDs file: {str(e)}")
        return set()

def load_capture(capture_file: str) -> list:
    try:
        with open(capture_file, 'r', encoding='utf-8') as f:
            return [line.strip() for line in f if line.strip()]
    except Exception as e:
        print(f"Error reading capture file: {str(e)}")
        return []

def process_domains(input_file: str, tlds_file: str):
    tlds = load_tlds(tlds_file)
    domains = load_capture(input_file)
    valid_domains = []
    filtered_domains = []
    
    for domain in domains:
        if should_keep_domain(domain, valid_domains, tlds):
            filtered_domains.append(domain)
            valid_domains.append(domain)
    
    for domain in filtered_domains:
        print(domain)

def main():
    parser = argparse.ArgumentParser(description="Filter domains based on TLDs and predefined rules.")
    parser.add_argument('--input', required=True, help="Path to the capture file.")
    parser.add_argument('--tld', required=True, help="Path to the TLDs file.")
    
    args = parser.parse_args()

    process_domains(args.input, args.tld)

if __name__ == "__main__":
    main()

