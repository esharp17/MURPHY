from pathlib import Path
from datetime import datetime
import json
from typing import Optional, Dict, Any, List

# Mirror log file (human-readable markdown) alongside the JSONL log
_LOG_MD_PATH: Path | None = None

def _get_log_md_path() -> Path:
    """Resolve the path to ui_qml/log_files.md once and cache it."""
    global _LOG_MD_PATH
    if _LOG_MD_PATH is None:
        # storage_log.py lives in robot_ui/; log_files.md lives in ui_qml/
        _LOG_MD_PATH = Path(__file__).resolve().parent.parent / "ui_qml" / "log_files.md"
    return _LOG_MD_PATH

def _append_to_md(entry: Dict[str, Any]):
    """Append a human-readable line to log_files.md."""
    try:
        md_path = _get_log_md_path()
        md_path.parent.mkdir(parents=True, exist_ok=True)
        # Write header if file is empty or doesn't exist
        needs_header = not md_path.exists() or md_path.stat().st_size == 0
        with md_path.open("a", encoding="utf-8") as f:
            if needs_header:
                f.write("# System Log\n\n")
                f.write("| Timestamp | User | Action | Details |\n")
                f.write("|-----------|------|--------|---------|\n")
            ts = entry.get("ts", "")
            user = entry.get("user", "")
            action = entry.get("action", "")
            details = entry.get("details", {})
            det_str = json.dumps(details) if details else ""
            f.write(f"| {ts} | {user} | {action} | {det_str} |\n")
    except Exception:
        pass  # never let mirror-logging break the main log

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
    _append_to_md(entry)

def sync_md_from_jsonl(jsonl_path: Path):
    """Rebuild log_files.md from existing JSONL entries (idempotent)."""
    try:
        md_path = _get_log_md_path()
        if not jsonl_path.exists():
            return
        entries = []
        for ln in jsonl_path.read_text(encoding="utf-8").splitlines():
            try:
                entries.append(json.loads(ln))
            except Exception:
                continue
        if not entries:
            return
        with md_path.open("w", encoding="utf-8") as f:
            f.write("# System Log\n\n")
            f.write("| Timestamp | User | Action | Details |\n")
            f.write("|-----------|------|--------|---------|\n")
            for entry in entries:
                ts = entry.get("ts", "")
                user = entry.get("user", "")
                action = entry.get("action", "")
                details = entry.get("details", {})
                det_str = json.dumps(details) if details else ""
                f.write(f"| {ts} | {user} | {action} | {det_str} |\n")
    except Exception:
        pass

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
