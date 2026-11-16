import json
import os
import sys
import urllib.error
import urllib.request

OWNER = "stefan-muri"
GITHUB_API = "https://api.github.com"
GITEA_API = "http://gitea.gitea.svc/api/v1"
# A migrate that fails leaves a repository without a mirror record, which the API reports as never synced.
NEVER_SYNCED = "0001-01-01T00:00:00Z"

github_token = os.environ["GITHUB_TOKEN"]
gitea_token = os.environ["GITEA_TOKEN"]


def call(method, url, auth, body=None):
    request = urllib.request.Request(url, method=method, headers={"Authorization": auth, "Accept": "application/json"})
    if body is not None:
        request.data = json.dumps(body).encode()
        request.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(request, timeout=600) as response:
        content = response.read()
    return json.loads(content) if content else None


def gitea(method, path, body=None):
    return call(method, GITEA_API + path, f"token {gitea_token}", body)


def gitea_repo(name):
    try:
        return gitea("GET", f"/repos/{OWNER}/{name}")
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise


def github_repos():
    repos, page = [], 1
    while True:
        url = f"{GITHUB_API}/user/repos?affiliation=owner&per_page=100&page={page}"
        batch = call("GET", url, f"Bearer {github_token}")
        repos += [repo for repo in batch if repo["owner"]["login"] == OWNER]
        if len(batch) < 100:
            return repos
        page += 1


repos = github_repos()
if not repos:
    sys.exit("GitHub returned no repositories")

failed = []
for repo in repos:
    name = repo["name"]
    existing = gitea_repo(name)
    if existing is None:
        try:
            gitea("POST", "/repos/migrate", {
                "clone_addr": repo["clone_url"],
                "repo_name": name,
                "repo_owner": OWNER,
                "service": "github",
                "auth_token": github_token,
                "mirror": True,
                "private": True,
            })
            print(f"{name}: created")
        except urllib.error.HTTPError as error:
            print(f"{name}: migrate failed with {error.code}")
            failed.append(name)
            leftover = gitea_repo(name)
            if error.code != 409 and leftover and leftover["mirror_updated"] == NEVER_SYNCED:
                gitea("DELETE", f"/repos/{OWNER}/{name}")
                print(f"{name}: removed the failed entry")
    elif not existing["mirror"]:
        print(f"{name}: not a mirror, skipped")
    elif existing["mirror_updated"] == NEVER_SYNCED:
        print(f"{name}: broken mirror entry, delete it in Gitea to recreate it")
        failed.append(name)
    else:
        gitea("PATCH", f"/repos/{OWNER}/{name}", {"mirror_token": github_token})
        print(f"{name}: token updated")

if failed:
    sys.exit(f"failed: {', '.join(failed)}")
