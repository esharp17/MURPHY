from pathlib import Path
from datetime import datetime
import json
from typing import Optional, Dict, Any, List

def ensure_log_file(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        path.write_text("", encoding="utf-8")

def append_log(path: Path, action: str, username: Optional[str], details: Dict[str, Any] | None = None):
    ensure_log_file(path)
    entry = {
        "ts": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "user": username or "none",
        "action": action,
        "details": details or {},
    }
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(entry) + "\n")

def tail_log(path: Path, max_lines: int = 200) -> List[Dict[str, Any]]:
    if not path.exists():
        return []
    lines = path.read_text(encoding="utf-8").splitlines()
    out = []
    for ln in lines[-max_lines:]:
        try:
            out.append(json.loads(ln))
        except Exception:
            continue
    return out
