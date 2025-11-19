#!/usr/bin/env python
# maravento.com

## Domain Filter Script

# What it does:
# - Downloads public suffix TLDs from multiple sources.
# - Removes invalid or duplicate TLDs.
# - Filters domains to ensure they end with a valid TLD.
# - Excludes duplicates from previously validated domains.
# - Outputs results to a file.

# Requirements:
# - Python 3.12.3

# Usage:
# Replace 'mylst.txt' with the name of your domain list
# python domfilter.py --input mylst.txt

# Optional parameters:
# By default, output goes to 'output.txt' and removed lines to 'removed.txt'.
# Customize output with:
# python domfilter.py --input mylst.txt --output outlst.txt --remove removelst.txt

# Important:
# Ensure the input list has no 'http://', 'https://', or 'www.' prefixes.

# TLD:
# Includes ccTLDs, gTLDs, sTLDs, eTLDs, and 4LDs.
# Created file: tlds.txt
# Sources:
# https://data.iana.org/TLD/tlds-alpha-by-domain.txt
# https://github.com/maravento/blackweb/blob/master/bwupdate/lst/tldsappx.txt
# https://github.com/publicsuffix/list/blob/master/public_suffix_list.dat
# https://www.whoisxmlapi.com/support/supported_gtlds.php

import requests
import re
from pathlib import Path
import warnings
from urllib3.exceptions import InsecureRequestWarning
import argparse
import sys
import os
from concurrent.futures import ThreadPoolExecutor

# Suppress InsecureRequestWarning warnings
warnings.simplefilter('ignore', InsecureRequestWarning)

# TLD
def download_public_suffix(url: str, output_file: str = "sourcetld.txt") -> None:
    try:
        head_response = requests.head(url, timeout=10, verify=False)
        head_response.raise_for_status()
        response = requests.get(url, timeout=10, verify=False)
        response.raise_for_status()
        with open(output_file, 'a', encoding='utf-8') as f:
            f.write(response.text)
    except requests.RequestException as e:
        print(f"ERROR {url}: {str(e)}")

def process_tlds_file(input_file: str = "sourcetld.txt", output_file: str = "tlds.txt") -> None:
    processed_lines = set()
    with open(input_file, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if (not line or 
                line.startswith('//') or 
                line.startswith('#') or 
                re.search(r'[^a-z0-9_.-]', line)):
                continue
            line = line.lstrip('.')
            if not line.startswith('.'):
                line = '.' + line
            processed_lines.add(line)
    with open(output_file, 'w', encoding='utf-8') as f:
        for line in sorted(processed_lines):
            f.write(line + '\n')

def generate_tlds():
    # Check if tlds.txt already exists
    if os.path.exists("tlds.txt") and os.path.getsize("tlds.txt") > 0:
        return  # If it exists and is not empty, do nothing.

    # If it does not exist, proceed with the download
    Path("sourcetld.txt").write_text("")
    urls = [
        'https://data.iana.org/TLD/tlds-alpha-by-domain.txt',
        'https://raw.githubusercontent.com/maravento/blackweb/refs/heads/master/bwupdate/lst/tldsappx.txt',
        'https://raw.githubusercontent.com/publicsuffix/list/master/public_suffix_list.dat',
        'https://www.whoisxmlapi.com/support/supported_gtlds.php'
    ]
    for url in urls:
        download_public_suffix(url)
    process_tlds_file()

# DOMAINS FILTER
def should_keep_domain(domain: str, valid_domains: set, tlds: set) -> bool:
    clean_domain = domain.lstrip('.')  # Remove the dot at the beginning, if it has one
    partial = ''
    tld = ''
    found = False
    for part in reversed(clean_domain.split('.')):
        partial = '.' + part + partial
        if partial in tlds:
            found = True
            tld = partial
            break

    if not found or tld == domain:
        return False

    partial = ''
    for part in reversed(clean_domain[:-len(tld)].split(".")):
        partial = '.' + part + partial

        if partial + tld in valid_domains:
            return False

    return True

def load_tlds(tlds_file: str) -> set:
    with open(tlds_file, 'r', encoding='utf-8') as f:
        return {line.strip().lower() for line in f if line.strip()}

def load_capture(capture_file: str) -> list:
    with open(capture_file, 'r', encoding='utf-8') as f:
        return [line.strip() for line in f if line.strip()]

# Check .dot input file
def add_dot_if_missing(filename: str):
    with open(filename, 'r', encoding='utf-8') as file:
        lines = file.readlines()

    with open(filename, 'w', encoding='utf-8') as file:
        for line in lines:
            line = line.strip()
            if not line.startswith('.'):
                line = '.' + line  # add .dot
            file.write(line + '\n')


def process_domains(input_file: str, tlds: set, output_file: str = None, removed_file: str = None):
    domains = load_capture(input_file)
    valid_domains = set()
    other_domains = set()

    domains.sort(key=lambda domain: len(domain))

    for domain in domains:
        if should_keep_domain(domain, valid_domains, tlds):
            valid_domains.add(domain)
        else:
            other_domains.add(domain)

    with open(output_file, 'w', encoding='utf-8') if output_file else sys.stdout as output:
        output.write("\n".join(sorted(valid_domains)))

    with open(removed_file, 'w', encoding='utf-8') if removed_file else sys.stderr as output:
        output.write("\n".join(sorted(other_domains)))

# MAIN
def main():
    parser = argparse.ArgumentParser(description="Generate TLD list and filter domains.")
    parser.add_argument('--input', required=True, help="Path to the capture file.")
    parser.add_argument('--output', help="Path to the output file (optional).", nargs="?", default="output.txt", type=str)
    parser.add_argument('--removed', help="Path to the output file for removed domains (optional).", nargs="?", default="removed.txt", type=str)
    args = parser.parse_args()

    # add .dot
    add_dot_if_missing(args.input)

    # generate tlds.txt
    generate_tlds()

    # Load TLDs and process domains
    tlds = load_tlds("tlds.txt")

    process_domains(args.input, tlds, args.output, args.removed)

if __name__ == "__main__":
    main()

