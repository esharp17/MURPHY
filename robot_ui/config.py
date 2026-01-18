"""robot_ui.config

Single source of truth for touch-first UI sizing, fonts, and color tokens.

Rules:
- Import ONLY from robot_ui.config in UI modules (no ad-hoc constants).
- Prefer token-based colors (COL[...]) over raw hex scattered across files.
- Keep a single font family to minimize layout jitter on Windows.
"""

from __future__ import annotations

# ------------------------------
# App
# ------------------------------
APP_TITLE = "Robot UI"

# Legacy window size constants (backward compatibility)
# Older files expect WINDOW_W / WINDOW_H
WINDOW_W = 1000
WINDOW_H = 700

APP_MIN_W = WINDOW_W
APP_MIN_H = WINDOW_H

# ------------------------------
# Data file paths (backward compatibility)
# ------------------------------
import os
import sys
from pathlib import Path

if getattr(sys, "frozen", False):
    BASE_DIR = Path(sys.executable).parent
else:
    BASE_DIR = Path(__file__).resolve().parent

DATA_DIR = BASE_DIR / "data"

USERS_JSON = DATA_DIR / "users.json"
SIGNAL_NAMES_JSON = DATA_DIR / "signal_names.json"
SYSTEM_LOG_JSONL = DATA_DIR / "system_log.jsonl"


# ------------------------------
# Touch sizing (1920x1200, ~9x6 usable)
# ------------------------------
PAD = 12          # outer padding
GAP = 10          # spacing between elements

BTN_H = 72        # primary touch button height
BTN_H_SM = 56     # secondary button height
BTN_W_MIN = 160

# Legacy button width alias
BTN_W = BTN_W_MIN

RADIUS = 14
BORDER_W = 2

# ------------------------------
# Typography
# ------------------------------
# Use a single family to avoid layout shifts.
FONT_FAMILY = "Segoe UI"

FONT_XL = (FONT_FAMILY, 28, "bold")
FONT_L  = (FONT_FAMILY, 22, "bold")
FONT_M  = (FONT_FAMILY, 18, "bold")
FONT_S  = (FONT_FAMILY, 16, "normal")
FONT_XS = (FONT_FAMILY, 14, "normal")

# Legacy font aliases
FONT_SML = FONT_S


# Back-compat aliases (existing code may import these)
FONT_MED = FONT_M
FONT_BIG = FONT_L

# ------------------------------
# Color tokens (dark)
# ------------------------------
COL: dict[str, str] = {
    "bg": "#0f1115",
    "panel": "#151a22",
    "panel_2": "#11151c",
    "border": "#2a3442",

    "text": "#e8ecf2",
    "muted": "#a7b0bf",

    "accent": "#3b82f6",
    "accent_hover": "#2563eb",

    "ok": "#22c55e",
    "warn": "#f59e0b",
    "danger": "#ef4444",

    "btn": "#1b2430",
    "btn_hover": "#243246",
    "btn_text": "#e8ecf2",

    "chip_on": "#22c55e",
    "chip_off": "#223040",
}

# Legacy flat color aliases (older code may import these)
BG_COLOR = COL["bg"]
PANEL_COLOR = COL["panel"]
BORDER_COLOR = COL["border"]
TEXT_COLOR = COL["text"]
ACCENT_COLOR = COL["accent"]

# ------------------------------
# Tk helpers (optional)
# ------------------------------

def tk_frame_kwargs():
    """Common kwargs for tk.Frame containers."""
    return dict(bg=COL["bg"], highlightthickness=0)


def tk_panel_kwargs():
    """Common kwargs for tk.Frame panel-like containers."""
    return dict(bg=COL["panel"], highlightthickness=0)
