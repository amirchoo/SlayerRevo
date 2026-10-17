"""Manages the user's Roblox animation assets through Open Cloud (Assets API).

    python3 tools/roblox_assets.py info <assetId> [...]
    python3 tools/roblox_assets.py rename <assetId> <new name>
    python3 tools/roblox_assets.py archive <assetId> [...]
    python3 tools/roblox_assets.py restore <assetId> [...]
    python3 tools/roblox_assets.py upload <file.rbxmx> [...]   (new animation assets; prints their IDs)

The API key is read from ~/.config/slayerrevo/roblox-api-key (made on
create.roblox.com/dashboard/credentials with Assets API read + write); it never goes in the repo.
Open Cloud can't archive animations ("not an archivable asset type"): unused ones get renamed
"OLD <name>" instead, and can be archived by hand on the Creator Dashboard.
"""
import json
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

USER_ID = "7791876777"  # ColePalmer6954, who owns the game's animations
KEY_FILE = Path.home() / ".config" / "slayerrevo" / "roblox-api-key"
BASE = "https://apis.roblox.com/assets/v1/assets"


def key():
    return "".join(KEY_FILE.read_text().split())


def call(method, url, body=None, content_type=None):
    req = urllib.request.Request(url, data=body, method=method, headers={"x-api-key": key()})
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            text = resp.read().decode()
    except urllib.error.HTTPError as err:
        return err.code, err.read().decode()
    return 200, text


def info(asset_id):
    status, text = call("GET", f"{BASE}/{asset_id}")
    if status != 200:
        return f"{asset_id}: error {status} {text[:200]}"
    d = json.loads(text)
    return f"{asset_id}: {d.get('displayName')} ({d.get('assetType')}, {d.get('state')})"


def rename(asset_id, name):
    boundary = uuid.uuid4().hex
    request = json.dumps({"assetId": asset_id, "displayName": name})
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"request\"\r\n\r\n{request}\r\n--{boundary}--\r\n").encode()
    status, text = call("PATCH", f"{BASE}/{asset_id}?updateMask=displayName", body, f"multipart/form-data; boundary={boundary}")
    return f"{asset_id}: rename to {name}: {'ok' if status == 200 else f'error {status} {text[:200]}'}"


def set_archived(asset_id, archived):
    action = "archive" if archived else "restore"
    status, text = call("POST", f"{BASE}/{asset_id}:{action}", b"{}", "application/json")
    return f"{asset_id}: {action}: {'ok' if status == 200 else f'error {status} {text[:200]}'}"


def upload(path):
    """Creates a new Animation asset from a .rbxmx and waits for its ID."""
    path = Path(path)
    name = path.stem
    boundary = uuid.uuid4().hex
    request = json.dumps({"assetType": "Animation", "displayName": name, "description": f"Slayer Revo: {name}",
                          "creationContext": {"creator": {"userId": USER_ID}}})
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"request\"\r\n\r\n{request}\r\n"
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"fileContent\"; filename=\"{path.name}\"\r\n"
            f"Content-Type: model/x-rbxm\r\n\r\n").encode() + path.read_bytes() + f"\r\n--{boundary}--\r\n".encode()
    status, text = call("POST", BASE, body, f"multipart/form-data; boundary={boundary}")
    if status != 200:
        return f"{name}: upload error {status} {text[:300]}"
    operation = json.loads(text).get("path", "")
    for _ in range(30):
        status, text = call("GET", f"https://apis.roblox.com/assets/v1/{operation}")
        d = json.loads(text) if status == 200 else {}
        if d.get("done"):
            response = d.get("response", {})
            return f"{name}: {response.get('assetId')}" if response.get("assetId") else f"{name}: failed {text[:300]}"
        time.sleep(2)
    return f"{name}: still processing ({operation})"


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return
    command, args = argv[0], argv[1:]
    if command == "info":
        for a in args:
            print(info(a))
    elif command == "rename":
        print(rename(args[0], " ".join(args[1:])))
    elif command == "upload":
        for a in args:
            print(upload(a))
    elif command in ("archive", "restore"):
        for a in args:
            print(set_archived(a, command == "archive"))
    else:
        print(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
