#!/usr/bin/env python
# maravento.com
"""
gitfolder.py
------------
Downloads a specific folder or file from a public GitHub repository
using the GitHub API. Supports recursive download of subfolders and
preserves the original directory structure locally.
Usage: python gitfolder.py <github_url>
Example: python gitfolder.py https://github.com/maravento/vault/project_name
"""
import requests
import os
from urllib.parse import urlparse
import sys

GITHUB_TOKEN = ""
REQUEST_TIMEOUT = 15

HEADERS = {
    "User-Agent": "gitfolder/1.0",
}
if GITHUB_TOKEN:
    HEADERS["Authorization"] = f"token {GITHUB_TOKEN}"


def download_folder_from_github(repo_owner, repo_name, folder_path, output_dir):
    os.makedirs(output_dir, exist_ok=True)
    url = f"https://api.github.com/repos/{repo_owner}/{repo_name}/contents/{folder_path}"
    try:
        response = requests.get(url, headers=HEADERS, timeout=REQUEST_TIMEOUT)
    except requests.exceptions.RequestException as e:
        print(f"Request error: {url} → {e}")
        return
    if response.status_code == 200:
        contents = response.json()
        if isinstance(contents, dict) and contents.get("type") == "file":
            download_item(contents, output_dir)
            return
        for item in contents:
            if item["type"] == "file":
                download_item(item, output_dir)
            elif item["type"] == "dir":
                subfolder_path = folder_path + '/' + item["name"]
                subfolder_output_dir = os.path.join(output_dir, item["name"])
                download_folder_from_github(repo_owner, repo_name, subfolder_path, subfolder_output_dir)
    else:
        print(f"Failed to retrieve folder contents [{response.status_code}]: {url}")


def download_item(item, output_dir):
    file_url = item.get("download_url")
    if not file_url:
        print(f"Skipped (no download_url): {item.get('name', '?')}")
        return
    file_path = os.path.join(output_dir, item["name"])
    try:
        response = requests.get(file_url, headers=HEADERS, timeout=REQUEST_TIMEOUT)
    except requests.exceptions.RequestException as e:
        print(f"Request error: {file_url} → {e}")
        return
    if response.status_code == 200:
        with open(file_path, "wb") as file:
            file.write(response.content)
            print(f"Downloaded file: {file_path}")
    else:
        print(f"Failed to download file [{response.status_code}]: {file_url}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python gitfolder.py <github_url>")
        sys.exit(1)

    url = sys.argv[1]
    parsed_url = urlparse(url)
    path_parts = parsed_url.path.strip("/").split("/")

    if len(path_parts) < 2:
        print("Error: URL must include at least owner and repository name.")
        sys.exit(1)

    repo_owner = path_parts[0]
    repo_name = path_parts[1]

    if len(path_parts) < 3:
        folder_path = ""
        output_dir = repo_name
    elif path_parts[2] in ("tree", "blob"):
        if len(path_parts) < 5:
            folder_path = ""
            output_dir = repo_name
        else:
            folder_path = "/".join(path_parts[4:])
            output_dir = path_parts[4]
    else:
        folder_path = "/".join(path_parts[2:])
        output_dir = path_parts[2]

    print(f"""
          Owner: {repo_owner}
          Repository: {repo_name}
          Directory: {folder_path}
    """)
    download_folder_from_github(repo_owner, repo_name, folder_path, output_dir)
