#!/usr/bin/env python
import requests
import os
from urllib.parse import urlparse
import sys

def download_folder_from_github(repo_owner, repo_name, folder_path, output_dir):
    # Create the output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)

    # Make a GET request to the GitHub API to retrieve the contents of the folder
    url = f"https://api.github.com/repos/{repo_owner}/{repo_name}/contents/{folder_path}"
    response = requests.get(url)

    # Check if the request was successful
    if response.status_code == 200:
        contents = response.json()

        if isinstance(contents, dict) and contents.get("type") == "file":
            download_item(contents, output_dir)
            return

        # Iterate over the contents of the folder
        for item in contents:
            if item["type"] == "file":
                # Download the file
                download_item(item, output_dir)
            elif item["type"] == "dir":
                # Recursively download subfolders
                subfolder_path = folder_path + '/' + item["name"]
                subfolder_output_dir = os.path.join(output_dir, item["name"])
                download_folder_from_github(repo_owner, repo_name, subfolder_path, subfolder_output_dir)
    else:
        print(f"Failed to retrieve folder contents: {url}")

def download_item(item, output_dir):
    file_url = item["download_url"]
    file_path = os.path.join(output_dir, item["name"])
    response = requests.get(file_url)
    if response.status_code == 200:
        with open(file_path, "wb") as file:
            file.write(response.content)
            print(f"Downloaded file: {file_path}")
    else:
        print(f"Failed to download file: {file_url}")

# Usage example
if __name__ == "__main__":
    url = sys.argv[1]
    # Parse the GitHub URL
    parsed_url = urlparse(url)
    path_parts = parsed_url.path.split("/")

    # Extract the repository owner, repository name, and folder path
    repo_owner = path_parts[1]
    repo_name = path_parts[2]

    if len(path_parts) < 4:
        folder_path = ""
        output_dir = repo_name
    elif path_parts[3] == "tree" or path_parts[3] == "blob":
        folder_path = "/".join(path_parts[5:])
        output_dir = path_parts[5]
    else:
        folder_path = "/".join(path_parts[3:])
        output_dir = path_parts[3]

    print(f"""
          Owner: {repo_owner}
          Repository: {repo_name}
          Directory: {folder_path}
    """)

    download_folder_from_github(repo_owner, repo_name, folder_path, output_dir)
