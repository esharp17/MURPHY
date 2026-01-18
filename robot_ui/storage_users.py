import json
from pathlib import Path
from typing import Dict, Any, Optional, List
from robot_ui.models import Role

def _default_users():
    # Admin: 000000 (change immediately)
    return {
        "users": [
            {"username": "admin", "role": int(Role.ADMIN), "hash": "", "salt": ""},
            {"username": "operator", "role": int(Role.OPERATOR), "hash": "", "salt": ""},
            {"username": "tech", "role": int(Role.TECHNICIAN), "hash": "", "salt": ""},
        ]
    }

def ensure_users_file(path: Path, hash_fn):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        return
    data = _default_users()
    # set default passcodes
    for u in data["users"]:
        h, s = hash_fn("000000")
        u["hash"] = h
        u["salt"] = s
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")

def load_users(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))

def list_usernames(path: Path) -> List[str]:
    data = load_users(path)
    return [u["username"] for u in data.get("users", [])]

def get_user_record(path: Path, username: str) -> Optional[Dict[str, Any]]:
    data = load_users(path)
    for u in data.get("users", []):
        if u["username"] == username:
            return u
    return None

def upsert_user(path: Path, username: str, role: Role, passcode_6: str, hash_fn):
    data = load_users(path)
    users = data.get("users", [])
    h, s = hash_fn(passcode_6)
    found = False
    for u in users:
        if u["username"] == username:
            u["role"] = int(role)
            u["hash"] = h
            u["salt"] = s
            found = True
    if not found:
        users.append({"username": username, "role": int(role), "hash": h, "salt": s})
    data["users"] = users
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")

def delete_user(path: Path, username: str):
    data = load_users(path)
    users = [u for u in data.get("users", []) if u["username"] != username]
    data["users"] = users
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")
