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
import re
import requests
from bs4 import BeautifulSoup
from urllib.parse import urljoin, urlparse
from collections import deque
from datetime import datetime
# ============================================================
#  CONFIGURATION — edit these values before running
# ============================================================
BASE_URL     = "https://www.anysite.com"      # Target website URL
TARGET_EMAIL = "anymail@anysite.com"           # Email address to search for
MAX_PAGES    = 500                             # Maximum number of pages to crawl (set to None for unlimited)
REQUEST_TIMEOUT  = 15                         # Seconds to wait per request
REQUEST_DELAY    = 0                          # Seconds between requests (0 = no delay)
VERIFY_SSL       = True                       # Set to False only for sites with self-signed certs
# ============================================================
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                  "AppleWebKit/537.36 (KHTML, like Gecko) "
                  "Chrome/120.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
}
SKIP_EXTENSIONS = (
    ".jpg", ".jpeg", ".png", ".gif", ".svg", ".ico",
    ".pdf", ".docx", ".xlsx", ".zip", ".mp4", ".css", ".js",
    ".woff", ".woff2", ".ttf", ".eot", ".otf",
)
def normalize_url(url):
    p = urlparse(url)
    return p.scheme + "://" + p.netloc + p.path + (("?" + p.query) if p.query else "")
def same_domain(url, base_domain):
    return urlparse(url).netloc == base_domain
def email_in_html(email, html):
    pattern = r'(?<![A-Za-z0-9._%+\-])' + re.escape(email) + r'(?![A-Za-z0-9._%+\-@])'
    return bool(re.search(pattern, html, re.IGNORECASE))
def process_page(url, email, session):
    try:
        resp = session.get(url, timeout=REQUEST_TIMEOUT, allow_redirects=True, verify=VERIFY_SSL)
        resp.raise_for_status()
        resp.encoding = resp.apparent_encoding or resp.encoding
        html = resp.text
        soup = BeautifulSoup(html, "html.parser")
        found = email_in_html(email, html)
        links = set()
        domain = urlparse(url).netloc
        for tag in soup.find_all("a", href=True):
            href = urljoin(url, tag["href"])
            norm = normalize_url(href)
            if norm.startswith("http") and same_domain(norm, domain):
                path = norm.split("?")[0].lower()
                if not any(path.endswith(e) for e in SKIP_EXTENSIONS):
                    links.add(norm)
        return found, links
    except KeyboardInterrupt:
        raise
    except Exception as e:
        print(f"  [ERROR] {url} → {e}")
        return False, set()
def scan():
    import time
    domain = urlparse(BASE_URL).netloc
    visited = set()
    pending = deque([normalize_url(BASE_URL)])
    pending_set = {normalize_url(BASE_URL)}
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
            if link not in visited and link not in pending_set:
                pending.append(link)
                pending_set.add(link)
        if REQUEST_DELAY > 0:
            time.sleep(REQUEST_DELAY)
    print("\n" + "="*65)
    print(f"📊 SUMMARY")
    print(f"   Pages scanned     : {count}")
    print(f"   Pages with email  : {len(matches)}")
    print("="*65)
    if matches:
        print("\n📋 URLs where the email appears:\n")
        for u in matches:
            print(f"  • {u}")
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"scan_results_{timestamp}.txt"
        with open(filename, "w", encoding="utf-8") as f:
            f.write(f"Email searched: {TARGET_EMAIL}\n")
            f.write(f"Site scanned: {BASE_URL}\n")
            f.write(f"Pages scanned: {count}\n")
            f.write(f"Pages with email: {len(matches)}\n\n")
            for u in matches:
                f.write(u + "\n")
        print(f"\n💾 Results saved to: {filename}")
    else:
        print("\n⚠️  Email not found on any visited page.")
        print("    Possible reasons:")
        print("    - Content is loaded via JavaScript (SPA/React/Angular)")
        print("    - Email only appears inside PDFs or attached documents")
        print("    - The site blocks automated crawling")
if __name__ == "__main__":
    scan()
