#!/usr/bin/env python3
# maravento.com
"""
gitfolder.py
------------
Downloads a specific folder or file from a public GitHub repository
using the GitHub API. Supports recursive download of subfolders and
preserves the original directory structure locally.
Usage: python3 gitfolder.py <github_url>
Example: python3 gitfolder.py https://github.com/maravento/vault/project_name
"""
import requests
import os
from urllib.parse import urlparse
import sys

GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "")
REQUEST_TIMEOUT = 15
HEADERS = {
    "User-Agent": "gitfolder/1.0",
}
if GITHUB_TOKEN:
    HEADERS["Authorization"] = f"token {GITHUB_TOKEN}"


def sanitize_path_component(name):
    """Sanitize a path component to prevent path traversal attacks."""
    name = os.path.normpath(name).lstrip(os.sep)
    if name.startswith(".."):
        return ""
    return name


def sanitize_output_dir(path):
    """Sanitize an output directory path to prevent path traversal attacks."""
    parts = [sanitize_path_component(p) for p in path.split("/") if p and p != ".."]
    return os.path.join(*parts) if parts else "."


def fetch_all_pages(url):
    """Fetch every page of a GitHub Contents API listing (max 1000 entries
    per page), following the Link: rel="next" header. Returns (items, ok)."""
    items = []
    next_url = url
    while next_url:
        try:
            response = requests.get(next_url, headers=HEADERS, timeout=REQUEST_TIMEOUT)
        except requests.exceptions.RequestException as e:
            print(f"Request error: {next_url} → {e}")
            return items, False
        if response.status_code != 200:
            print(f"Failed to retrieve folder contents [{response.status_code}]: {next_url}")
            return items, False
        page = response.json()
        if isinstance(page, dict):
            # single-file response, not a paginated listing
            return page, True
        items.extend(page)
        next_url = response.links.get("next", {}).get("url")
    return items, True


def download_folder_from_github(repo_owner, repo_name, folder_path, output_dir, branch=""):
    ref_param = f"?ref={branch}" if branch else ""
    url = f"https://api.github.com/repos/{repo_owner}/{repo_name}/contents/{folder_path}{ref_param}"
    contents, fetch_ok = fetch_all_pages(url)
    if not fetch_ok and not contents:
        return False
    os.makedirs(output_dir, exist_ok=True)
    if isinstance(contents, dict) and contents.get("type") == "file":
        return download_item(contents, output_dir) and fetch_ok
    ok = fetch_ok
    for item in contents:
        if item["type"] == "file":
            ok = download_item(item, output_dir) and ok
        elif item["type"] == "dir":
            safe_name = sanitize_path_component(item["name"])
            if not safe_name:
                print(f"Skipped unsafe directory name: {item['name']!r}")
                ok = False
                continue
            subfolder_path = folder_path + '/' + item["name"]
            subfolder_output_dir = os.path.join(output_dir, safe_name)
            ok = download_folder_from_github(repo_owner, repo_name, subfolder_path, subfolder_output_dir, branch) and ok
        else:
            print(f"Skipped unsupported type '{item['type']}': {item['name']}")
            ok = False
    return ok


def download_item(item, output_dir):
    file_url = item.get("download_url")
    if not file_url:
        print(f"Skipped (no download_url): {item.get('name', '?')}")
        return False
    safe_name = sanitize_path_component(item["name"])
    if not safe_name:
        print(f"Skipped unsafe filename: {item.get('name', '?')!r}")
        return False
    try:
        response = requests.get(file_url, headers=HEADERS, timeout=REQUEST_TIMEOUT)
    except requests.exceptions.RequestException as e:
        print(f"Request error: {file_url} → {e}")
        return False
    if response.status_code != 200:
        print(f"Failed to download file [{response.status_code}]: {file_url}")
        return False
    os.makedirs(output_dir, exist_ok=True)
    file_path = os.path.join(output_dir, safe_name)
    tmp_path = file_path + ".part"
    with open(tmp_path, "wb") as file:
        file.write(response.content)
    os.replace(tmp_path, file_path)
    print(f"Downloaded file: {file_path}")
    return True


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 gitfolder.py <github_url>")
        sys.exit(1)
    url = sys.argv[1]
    parsed_url = urlparse(url)
    path_parts = parsed_url.path.strip("/").split("/")
    if len(path_parts) < 2:
        print("Error: URL must include at least owner and repository name.")
        sys.exit(1)
    repo_owner = path_parts[0]
    repo_name = path_parts[1]
    branch = ""
    if len(path_parts) < 3:
        folder_path = ""
        output_dir = repo_name
    elif path_parts[2] in ("tree", "blob"):
        if len(path_parts) < 4:
            folder_path = ""
            output_dir = repo_name
        elif len(path_parts) < 5:
            branch = path_parts[3]
            folder_path = ""
            output_dir = repo_name
        else:
            branch = path_parts[3]
            folder_path = "/".join(path_parts[4:])
            output_dir = sanitize_output_dir(folder_path)
    else:
        folder_path = "/".join(path_parts[2:])
        output_dir = sanitize_output_dir(folder_path)
    print(f"""
          Owner: {repo_owner}
          Repository: {repo_name}
          Branch: {branch or "(default)"}
          Directory: {folder_path or "(root)"}
    """)
    if not download_folder_from_github(repo_owner, repo_name, folder_path, output_dir, branch):
        sys.exit(1)
