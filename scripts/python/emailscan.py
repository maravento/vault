#!/usr/bin/env python
# maravento.com
"""
------------
emailscan.py
------------
Recursively crawls a public website and reports every page
where a given email address appears in the HTML source.
Follows all internal links up to a configurable page limit.
Compatible with static sites and SharePoint / GovCo portals.

Usage: python emailscan.py
Replace: BASE_URL and TARGET_EMAIL
"""

import requests
from bs4 import BeautifulSoup
from urllib.parse import urljoin, urlparse
from collections import deque

# ============================================================
#  CONFIGURATION — edit these values before running
# ============================================================
BASE_URL     = "https://www.anysite.com"      # Target website URL
TARGET_EMAIL = "anymail@anysite.com"           # Email address to search for
MAX_PAGES    = 500                             # Maximum number of pages to crawl (set to None for unlimited)
# ============================================================

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                  "AppleWebKit/537.36 (KHTML, like Gecko) "
                  "Chrome/120.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
}

def normalize_url(url):
    p = urlparse(url)
    # Keep query string because SharePoint uses it to identify pages
    return p.scheme + "://" + p.netloc + p.path + (("?" + p.query) if p.query else "")

def same_domain(url, base_domain):
    return urlparse(url).netloc == base_domain

def process_page(url, email, session):
    try:
        resp = session.get(url, timeout=15, allow_redirects=True)
        resp.raise_for_status()

        html = resp.text
        soup = BeautifulSoup(html, "html.parser")

        # Search for email in raw HTML (includes mailto: links and visible text)
        found = email.lower() in html.lower()

        # Collect all internal links
        links = set()
        domain = urlparse(url).netloc
        for tag in soup.find_all("a", href=True):
            href = urljoin(url, tag["href"])
            norm = normalize_url(href)
            if norm.startswith("http") and same_domain(norm, domain):
                # Skip static resources and downloadable files
                ext = norm.split("?")[0].lower()
                if not any(ext.endswith(e) for e in [
                    ".jpg", ".jpeg", ".png", ".gif", ".svg", ".ico",
                    ".pdf", ".docx", ".xlsx", ".zip", ".mp4", ".css", ".js"
                ]):
                    links.add(norm)

        return found, links

    except Exception as e:
        print(f"  [ERROR] {url} → {e}")
        return False, set()


def scan():
    domain = urlparse(BASE_URL).netloc
    visited = set()
    pending = deque([normalize_url(BASE_URL)])
    matches = []

    session = requests.Session()
    session.headers.update(HEADERS)

    limit_label = str(MAX_PAGES) if MAX_PAGES is not None else "unlimited"
    print(f"\n🔍 Searching for: '{TARGET_EMAIL}'")
    print(f"   Site     : {BASE_URL}")
    print(f"   Max pages: {limit_label}\n")

    count = 0
    while pending and (MAX_PAGES is None or count < MAX_PAGES):
        current_url = pending.popleft()
        if current_url in visited:
            continue

        visited.add(current_url)
        count += 1
        print(f"[{count:>4}] {current_url}")

        found, new_links = process_page(current_url, TARGET_EMAIL, session)

        if found:
            matches.append(current_url)
            print(f"        ✅ EMAIL FOUND!")

        for link in new_links:
            if link not in visited:
                pending.append(link)

    # Final report
    print("\n" + "="*65)
    print(f"📊 SUMMARY")
    print(f"   Pages scanned     : {count}")
    print(f"   Pages with email  : {len(matches)}")
    print("="*65)

    if matches:
        print("\n📋 URLs where the email appears:\n")
        for u in matches:
            print(f"  • {u}")

        with open("scan_results.txt", "w", encoding="utf-8") as f:
            f.write(f"Email searched: {TARGET_EMAIL}\n")
            f.write(f"Site scanned: {BASE_URL}\n")
            f.write(f"Pages scanned: {count}\n")
            f.write(f"Pages with email: {len(matches)}\n\n")
            for u in matches:
                f.write(u + "\n")
        print(f"\n💾 Results saved to: scan_results.txt")
    else:
        print("\n⚠️  Email not found on any visited page.")
        print("    Possible reasons:")
        print("    - Content is loaded via JavaScript (SPA/React/Angular)")
        print("    - Email only appears inside PDFs or attached documents")
        print("    - The site blocks automated crawling")

if __name__ == "__main__":
    scan()
