"""robot_ui.log_service

QObject wrapper around storage_log so QML can write and read
persistent action logs via LogService context property.
"""

from __future__ import annotations

import json
from PySide6.QtCore import QObject, Signal, Slot

from robot_ui.config import SYSTEM_LOG_JSONL
from robot_ui.storage_log import append_log, tail_log


class LogService(QObject):
    """Singleton exposed to QML as LogService."""

    logChanged = Signal()

    def __init__(self, parent: QObject | None = None):
        super().__init__(parent)

    # ------------------------------------------------------------------
    # QML-callable slots
    # ------------------------------------------------------------------

    @Slot(str, str, str)
    def log(self, action: str, username: str, details_json: str = "{}"):
        """Log an action.  *details_json* is a JSON string from QML."""
        try:
            details = json.loads(details_json) if details_json else {}
        except Exception:
            details = {"raw": details_json}

        append_log(SYSTEM_LOG_JSONL, action, username or None, details)
        self.logChanged.emit()

    @Slot(str, str)
    def logSimple(self, action: str, username: str):
        """Convenience overload without details."""
        append_log(SYSTEM_LOG_JSONL, action, username or None)
        self.logChanged.emit()

    @Slot(int, result=str)
    def tail(self, max_lines: int = 200) -> str:
        """Return the last *max_lines* log entries as a JSON array string."""
        entries = tail_log(SYSTEM_LOG_JSONL, max_lines)
        return json.dumps(entries)

    @Slot(str, result=bool)
    def exportToFile(self, file_url: str) -> bool:
        """Export all log entries to a plain-text file chosen by the user.
        *file_url* comes from QML FileDialog (file:///... URL)."""
        from pathlib import Path
        from urllib.parse import unquote
        try:
            path_str = file_url
            if path_str.startswith("file:///"):
                path_str = unquote(path_str[8:])  # strip file:/// prefix
            elif path_str.startswith("file://"):
                path_str = unquote(path_str[7:])
            dest = Path(path_str)
            entries = tail_log(SYSTEM_LOG_JSONL, 10000)
            with dest.open("w", encoding="utf-8") as f:
                f.write(f"System Log Export  ({len(entries)} entries)\n")
                f.write("=" * 80 + "\n\n")
                for e in entries:
                    ts = e.get("ts", "")
                    user = e.get("user", "")
                    action = e.get("action", "")
                    details = e.get("details", {})
                    det_str = json.dumps(details) if details else ""
                    f.write(f"[{ts}]  {action:<24} user={user:<16} {det_str}\n")
            return True
        except Exception as ex:
            print(f"[LogService] exportToFile error: {ex}", flush=True)
            return False

    # ------------------------------------------------------------------
    # Python-callable helper (for bridge / backend use)
    # ------------------------------------------------------------------

    def log_from_python(self, action: str, username: str | None = None,
                        details: dict | None = None):
        append_log(SYSTEM_LOG_JSONL, action, username, details)
        self.logChanged.emit()
