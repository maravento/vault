#!/usr/bin/env python
# maravento.com
"""
------------
linkcheck.py
------------
Recursively crawls a public website and detects broken links.
Classifies every error by type: HTTP errors (4xx/5xx),
broken redirects, timeouts, SSL failures, DNS failures,
and connection errors.

Usage: python linkcheck.py
Replace: BASE_URL
"""

import requests
from requests.exceptions import (
    Timeout, ConnectionError, SSLError, TooManyRedirects
)
from bs4 import BeautifulSoup
from urllib.parse import urljoin, urlparse
from collections import deque, defaultdict
from datetime import datetime

# ============================================================
#  CONFIGURATION — edit these values before running
# ============================================================
BASE_URL  = "https://www.anysite.com"         # Target website URL
MAX_PAGES = 500                               # Maximum pages to crawl (set to None for unlimited)
TIMEOUT   = 10                                # Seconds to wait for a response
# ============================================================

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                  "AppleWebKit/537.36 (KHTML, like Gecko) "
                  "Chrome/120.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
}

# All recognized error categories
ERROR_LABELS = {
    # 3xx
    "redirect_broken":    "Broken Redirect (3xx — no valid destination)",
    "too_many_redirects": "Too Many Redirects",
    # 4xx
    "400": "400 Bad Request",
    "401": "401 Unauthorized (login required)",
    "403": "403 Forbidden (access denied)",
    "404": "404 Not Found",
    "405": "405 Method Not Allowed",
    "408": "408 Request Timeout",
    "410": "410 Gone (permanently removed)",
    "429": "429 Too Many Requests (rate limited)",
    "4xx": "4xx Client Error (other)",
    # 5xx
    "500": "500 Internal Server Error",
    "502": "502 Bad Gateway",
    "503": "503 Service Unavailable",
    "504": "504 Gateway Timeout",
    "5xx": "5xx Server Error (other)",
    # Connection
    "ssl":     "SSL/TLS Error (invalid or expired certificate)",
    "dns":     "DNS Error (domain not resolved)",
    "refused": "Connection Refused",
    "timeout": "Timeout (no response)",
    "conn":    "Connection Error (other)",
}


def normalize_url(url):
    p = urlparse(url)
    # Keep query string because SharePoint uses it to identify pages
    return p.scheme + "://" + p.netloc + p.path + (("?" + p.query) if p.query else "")

def same_domain(url, base_domain):
    return urlparse(url).netloc == base_domain

def classify_http(status):
    """Return an error key for a given HTTP status code, or None if healthy."""
    if status < 300:
        return None
    mapping = {
        400: "400", 401: "401", 403: "403", 404: "404",
        405: "405", 408: "408", 410: "410", 429: "429",
        500: "500", 502: "502", 503: "503", 504: "504",
    }
    if status in mapping:
        return mapping[status]
    if 400 <= status < 500:
        return "4xx"
    if 500 <= status < 600:
        return "5xx"
    return None

def check_link(url, session):
    """
    Check a single URL.
    Returns (status_code_or_None, error_key_or_None).
    error_key is a key from ERROR_LABELS; None means the link is healthy.
    """
    try:
        resp = session.get(url, timeout=TIMEOUT, allow_redirects=False)

        # Handle redirects manually
        if 300 <= resp.status_code < 400:
            location = resp.headers.get("Location", "").strip()
            if not location:
                return resp.status_code, "redirect_broken"
            try:
                final = session.get(url, timeout=TIMEOUT, allow_redirects=True)
                error = classify_http(final.status_code)
                return final.status_code, error if error else None
            except Timeout:
                return None, "timeout"
            except SSLError:
                return None, "ssl"
            except Exception:
                return None, "redirect_broken"

        error = classify_http(resp.status_code)
        return resp.status_code, error

    except Timeout:
        return None, "timeout"
    except SSLError:
        return None, "ssl"
    except TooManyRedirects:
        return None, "too_many_redirects"
    except ConnectionError as e:
        msg = str(e).lower()
        if any(x in msg for x in ["nodename nor servname", "name or service not known",
                                   "getaddrinfo", "name resolution"]):
            return None, "dns"
        if any(x in msg for x in ["connection refused", "actively refused"]):
            return None, "refused"
        return None, "conn"
    except Exception:
        return None, "conn"


def collect_links(url, session):
    """Download a page and extract all internal links."""
    try:
        resp = session.get(url, timeout=TIMEOUT, allow_redirects=True)
        resp.raise_for_status()
        soup = BeautifulSoup(resp.text, "html.parser")
        domain = urlparse(url).netloc
        links = set()
        for tag in soup.find_all("a", href=True):
            href = urljoin(url, tag["href"])
            norm = normalize_url(href)
            if norm.startswith("http") and same_domain(norm, domain):
                ext = norm.split("?")[0].lower()
                if not any(ext.endswith(e) for e in [
                    ".jpg", ".jpeg", ".png", ".gif", ".svg", ".ico",
                    ".pdf", ".docx", ".xlsx", ".zip", ".mp4", ".css", ".js"
                ]):
                    links.add(norm)
        return links
    except Exception:
        return set()


def scan():
    domain = urlparse(BASE_URL).netloc
    visited = set()
    pending = deque([normalize_url(BASE_URL)])
    broken  = []                        # List of (url, status, error_key)
    by_type = defaultdict(list)         # error_key → [(url, status)]

    session = requests.Session()
    session.headers.update(HEADERS)

    limit_label = str(MAX_PAGES) if MAX_PAGES is not None else "unlimited"
    print(f"\n🔍 Scanning for broken links")
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

        status, error_key = check_link(current_url, session)

        if error_key:
            label = ERROR_LABELS.get(error_key, "Unknown Error")
            broken.append((current_url, status, label))
            by_type[error_key].append((current_url, status))
            print(f"        ❌ {label}")
        else:
            # Only follow links on healthy pages
            new_links = collect_links(current_url, session)
            for link in new_links:
                if link not in visited:
                    pending.append(link)

    # ── Final report ─────────────────────────────────────────
    print("\n" + "="*65)
    print(f"📊 SUMMARY")
    print(f"   Pages scanned      : {count}")
    print(f"   Broken links found : {len(broken)}")

    if by_type:
        print(f"\n   Breakdown by error type:")
        for key, urls in sorted(by_type.items()):
            label = ERROR_LABELS.get(key, key)
            print(f"   {len(urls):>4}x  {label}")
    print("="*65)

    if broken:
        print(f"\n❌ Broken links grouped by error type:\n")
        for key, urls in sorted(by_type.items()):
            label = ERROR_LABELS.get(key, key)
            print(f"  ── {label} ({len(urls)}) ──")
            for url, status in urls:
                code = str(status) if status else "—"
                print(f"     [{code}] {url}")
            print()

        # Save to TXT
        filename = f"broken_links_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
        with open(filename, "w", encoding="utf-8") as f:
            f.write("Broken Link Report\n")
            f.write("==================\n")
            f.write(f"Site scanned : {BASE_URL}\n")
            f.write(f"Date         : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"Pages scanned: {count}\n")
            f.write(f"Broken links : {len(broken)}\n\n")

            f.write("Breakdown by error type:\n")
            for key, urls in sorted(by_type.items()):
                label = ERROR_LABELS.get(key, key)
                f.write(f"  {len(urls):>3}x  {label}\n")
            f.write("\n")

            f.write("Broken links grouped by error type:\n")
            f.write("-"*60 + "\n\n")
            for key, urls in sorted(by_type.items()):
                label = ERROR_LABELS.get(key, key)
                f.write(f"── {label} ({len(urls)}) ──\n")
                for url, status in urls:
                    code = str(status) if status else "—"
                    f.write(f"   [{code}] {url}\n")
                f.write("\n")

        print(f"💾 Results saved to: {filename}")
    else:
        print("\n✅ No broken links found.")

if __name__ == "__main__":
    scan()
