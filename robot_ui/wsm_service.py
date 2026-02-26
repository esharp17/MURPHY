"""robot_ui.wsm_service

Reads the most-recently-modified PDF in a user-chosen WSM folder and
extracts the "Essential Variables" table into QML-friendly properties.

The service is exposed to QML as a context property so the WeldingScreen
can bind directly to the parsed values.
"""

from __future__ import annotations

import os
import re
import glob
import json
from pathlib import Path
from typing import Optional

from PySide6.QtCore import QObject, Signal, Slot, Property

import pdfplumber


# Default WSM folder relative to project root
_DEFAULT_WSM_DIRNAME = "WSM"

# Keys in the order they should appear in the UI
ALL_KEYS = [
    "pipeDiameter",
    "wallThickness",
    "bevelPrep",
    "preHeatTemp",
    "wireType",
    "wireDiameter",
    "wireBrand",
    "shieldGas",
]

# Persistence file for the chosen WSM folder path
_SETTINGS_FILE = "wsm_settings.json"


def _project_root() -> Path:
    """Return the Murphy project root (parent of robot_ui/)."""
    return Path(__file__).resolve().parent.parent


def _default_wsm_folder() -> str:
    """Return the default WSM folder if it exists."""
    candidate = _project_root() / _DEFAULT_WSM_DIRNAME
    if candidate.is_dir():
        return str(candidate)
    return ""


def _settings_path() -> Path:
    """Return path to the settings JSON next to this module."""
    return Path(__file__).resolve().parent / "data" / _SETTINGS_FILE


def _save_folder_setting(folder: str) -> None:
    path = _settings_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"wsm_folder": folder}, f)


def _load_folder_setting() -> str:
    """Load saved folder, falling back to default WSM folder."""
    path = _settings_path()
    if path.exists():
        try:
            with open(path, "r", encoding="utf-8") as f:
                saved = json.load(f).get("wsm_folder", "")
                if saved and os.path.isdir(saved):
                    return saved
        except Exception:
            pass
    return _default_wsm_folder()


def _find_latest_pdf(folder: str) -> Optional[str]:
    """Return the path to the most-recently-modified PDF in *folder*."""
    if not folder or not os.path.isdir(folder):
        return None
    pdfs = glob.glob(os.path.join(folder, "*.pdf")) + glob.glob(
        os.path.join(folder, "*.PDF")
    )
    if not pdfs:
        return None
    return max(pdfs, key=os.path.getmtime)


def _fmt_inches(val: float) -> str:
    """Format a value in inches with a trailing quote, stripping excess zeros."""
    s = f"{val:.3f}".rstrip("0").rstrip(".")
    return s + '"'


def _parse_essential_variables(pdf_path: str) -> dict[str, list[str]]:
    """
    Open *pdf_path* with pdfplumber and extract Essential Variables
    from the WSM format.

    The WSM PDF has:
      - Header rows (first 3 rows of table 0) as alternating key/value pairs
      - Additional rows in side tables (Wire Diamiter, Min Pre-Heat Temp, etc.)
    """
    result: dict[str, list[str]] = {k: [] for k in ALL_KEYS}

    try:
        with pdfplumber.open(pdf_path) as pdf:
            # Collect all table rows from all pages
            all_rows: list[list] = []
            for page in pdf.pages:
                for table in page.extract_tables():
                    all_rows.extend(table)

            # --- Parse header rows (alternating key-value pairs) ---
            header: dict[str, str] = {}
            for row in all_rows[:3]:
                if not row:
                    continue
                cells = [(c.strip() if c else "") for c in row]
                for i in range(0, len(cells) - 1, 2):
                    key = cells[i].lower()
                    val = cells[i + 1]
                    if key:
                        header[key] = val

            # --- Parse remaining rows for labeled fields ---
            side: dict[str, list[str]] = {}
            for row in all_rows[3:]:
                if not row or not row[0]:
                    continue
                label = re.sub(r"\s+", " ", row[0].strip().lower())
                vals = [(c.strip() if c else "") for c in row[1:]]
                side[label] = vals

            # --- Map to Essential Variables ---

            # Pipe Diameter: "diameter (in)" -> convert to mm + show inches
            diam_in = header.get("diameter (in)", "")
            if diam_in:
                try:
                    d = float(diam_in)
                    mm_val = d * 25.4
                    mm_rounded = round(mm_val)
                    result["pipeDiameter"] = [f"{mm_rounded:,}mm", f'{diam_in}"']
                except ValueError:
                    result["pipeDiameter"] = [diam_in]

            # Wall Thickness: "wall (mm)" -> keep mm + convert to inches
            wall_mm = header.get("wall (mm)", "")
            if wall_mm:
                try:
                    w = float(wall_mm)
                    inches = w / 25.4
                    result["wallThickness"] = [f"{wall_mm}mm", _fmt_inches(inches)]
                except ValueError:
                    result["wallThickness"] = [wall_mm]

            # Bevel Prep: "bevel design"
            bevel = header.get("bevel design", "")
            if bevel:
                # Normalize "30 degree" -> "30°"
                bevel_clean = re.sub(r"\s*degree[s]?\s*", "\u00b0", bevel, flags=re.IGNORECASE)
                result["bevelPrep"] = [bevel_clean]

            # Pre-Heat Temp: side table "min pre-heat temp c° / method"
            for label, vals in side.items():
                if "pre-heat temp" in label or "preheat temp" in label or "pre heat temp" in label:
                    temp_str = vals[0] if vals else ""
                    # Extract numeric temperature
                    m = re.search(r"(\d+(?:\.\d+)?)", temp_str)
                    if m:
                        c_val = float(m.group(1))
                        f_val = (c_val * 9.0 / 5.0) + 32
                        c_display = f"{int(c_val)}\u00b0 C" if c_val == int(c_val) else f"{c_val}\u00b0 C"
                        f_display = f"{int(f_val)}\u00b0F" if f_val == int(f_val) else f"{f_val:.1f}\u00b0F"
                        result["preHeatTemp"] = [c_display, f_display]
                    else:
                        result["preHeatTemp"] = [temp_str]
                    break

            # Wire Type: "process"
            process = header.get("process", "")
            if process:
                result["wireType"] = [process]

            # Wire Diameter: side table "wire diamiter" (note: misspelled in PDF)
            for label, vals in side.items():
                if "wire diam" in label:
                    raw = vals[0] if vals else ""
                    try:
                        d = float(raw)
                        inches = d / 25.4
                        result["wireDiameter"] = [f"{raw}mm", _fmt_inches(inches)]
                    except ValueError:
                        result["wireDiameter"] = [raw]
                    break

            # Wire Brand: "filler wire"
            filler = header.get("filler wire", "")
            if filler:
                result["wireBrand"] = [filler]

            # Shield Gas: "shield gas"
            gas = header.get("shield gas", "")
            if gas:
                result["shieldGas"] = [gas]

    except Exception as e:
        print(f"[WsmService] PDF parse error: {e}")

    return result


class WsmService(QObject):
    """
    QObject exposed to QML that:
      - Lets the user pick a WSM folder  (setFolder / folder property)
      - Finds the latest PDF in that folder
      - Parses Essential Variables from the PDF
      - Exposes each variable as a QML-readable property + a full model list
    """

    folderChanged = Signal()
    dataChanged = Signal()
    errorOccurred = Signal(str)
    pdfNameChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._folder: str = _load_folder_setting()
        self._pdf_name: str = ""
        self._data: dict[str, list[str]] = {k: [] for k in ALL_KEYS}
        # Auto-load if we already have a saved folder
        if self._folder:
            self._reload()

    # ---- folder property ----
    @Slot(str)
    def setFolder(self, folder: str) -> None:
        """Called from QML when the user picks a folder."""
        folder = folder.replace("file:///", "").replace("/", os.sep)
        if folder == self._folder:
            return
        self._folder = folder
        _save_folder_setting(folder)
        self.folderChanged.emit()
        self._reload()

    def _get_folder(self) -> str:
        return self._folder

    folder = Property(str, _get_folder, setFolder, notify=folderChanged)

    # ---- pdf name ----
    def _get_pdf_name(self) -> str:
        return self._pdf_name

    pdfName = Property(str, _get_pdf_name, notify=pdfNameChanged)

    # ---- reload ----
    @Slot()
    def reload(self) -> None:
        """Public slot for QML to trigger a refresh."""
        self._reload()

    def _reload(self) -> None:
        pdf = _find_latest_pdf(self._folder)
        if not pdf:
            self._pdf_name = ""
            self.pdfNameChanged.emit()
            self._data = {k: [] for k in ALL_KEYS}
            self.dataChanged.emit()
            self.errorOccurred.emit(
                "No PDF found in folder: " + self._folder
            )
            return

        self._pdf_name = os.path.basename(pdf)
        self.pdfNameChanged.emit()

        self._data = _parse_essential_variables(pdf)
        self.dataChanged.emit()
        print(f"[WsmService] Loaded: {pdf}")
        for k in ALL_KEYS:
            print(f"  {k}: {self._data[k]}")

    # ---- individual property helpers ----
    def _val(self, key: str, idx: int = 0) -> str:
        vals = self._data.get(key, [])
        if idx < len(vals):
            return vals[idx]
        return ""

    def _val1(self, key: str) -> str:
        return self._val(key, 0)

    def _val2(self, key: str) -> str:
        return self._val(key, 1)

    # ---- QML properties for each essential variable ----
    # Metric / primary value
    def _get_pipeDiameter1(self): return self._val1("pipeDiameter")
    def _get_wallThickness1(self): return self._val1("wallThickness")
    def _get_bevelPrep1(self): return self._val1("bevelPrep")
    def _get_preHeatTemp1(self): return self._val1("preHeatTemp")
    def _get_wireType1(self): return self._val1("wireType")
    def _get_wireDiameter1(self): return self._val1("wireDiameter")
    def _get_wireBrand1(self): return self._val1("wireBrand")
    def _get_shieldGas1(self): return self._val1("shieldGas")

    # Imperial / secondary value
    def _get_pipeDiameter2(self): return self._val2("pipeDiameter")
    def _get_wallThickness2(self): return self._val2("wallThickness")
    def _get_bevelPrep2(self): return self._val2("bevelPrep")
    def _get_preHeatTemp2(self): return self._val2("preHeatTemp")
    def _get_wireType2(self): return self._val2("wireType")
    def _get_wireDiameter2(self): return self._val2("wireDiameter")
    def _get_wireBrand2(self): return self._val2("wireBrand")
    def _get_shieldGas2(self): return self._val2("shieldGas")

    pipeDiameter1 = Property(str, _get_pipeDiameter1, notify=dataChanged)
    pipeDiameter2 = Property(str, _get_pipeDiameter2, notify=dataChanged)
    wallThickness1 = Property(str, _get_wallThickness1, notify=dataChanged)
    wallThickness2 = Property(str, _get_wallThickness2, notify=dataChanged)
    bevelPrep1 = Property(str, _get_bevelPrep1, notify=dataChanged)
    bevelPrep2 = Property(str, _get_bevelPrep2, notify=dataChanged)
    preHeatTemp1 = Property(str, _get_preHeatTemp1, notify=dataChanged)
    preHeatTemp2 = Property(str, _get_preHeatTemp2, notify=dataChanged)
    wireType1 = Property(str, _get_wireType1, notify=dataChanged)
    wireType2 = Property(str, _get_wireType2, notify=dataChanged)
    wireDiameter1 = Property(str, _get_wireDiameter1, notify=dataChanged)
    wireDiameter2 = Property(str, _get_wireDiameter2, notify=dataChanged)
    wireBrand1 = Property(str, _get_wireBrand1, notify=dataChanged)
    wireBrand2 = Property(str, _get_wireBrand2, notify=dataChanged)
    shieldGas1 = Property(str, _get_shieldGas1, notify=dataChanged)
    shieldGas2 = Property(str, _get_shieldGas2, notify=dataChanged)

    @Slot()
    def openPdf(self) -> None:
        """Open the current WSM PDF in the system's default viewer."""
        if not self._folder or not self._pdf_name:
            self.errorOccurred.emit("No WSM PDF loaded.")
            return
        full_path = os.path.join(self._folder, self._pdf_name)
        if not os.path.isfile(full_path):
            self.errorOccurred.emit(f"PDF not found: {full_path}")
            return
        import subprocess, sys
        try:
            if sys.platform == "win32":
                os.startfile(full_path)
            elif sys.platform == "darwin":
                subprocess.Popen(["open", full_path])
            else:
                subprocess.Popen(["xdg-open", full_path])
        except Exception as e:
            self.errorOccurred.emit(f"Failed to open PDF: {e}")

    @Slot(result="QVariantList")
    def essentialVariables(self) -> list:
        """
        Return the full table as a list of dicts for a QML Repeater:
        [{ label: "Pipe Diameter", val1: "1,219mm", val2: "48\"" }, ...]
        """
        labels = {
            "pipeDiameter": "Pipe Diameter",
            "wallThickness": "Wall Thickness",
            "bevelPrep": "Bevel Prep",
            "preHeatTemp": "Pre-Heat Temp",
            "wireType": "Wire Type",
            "wireDiameter": "Wire Diameter",
            "wireBrand": "Wire Brand",
            "shieldGas": "Shield Gas",
        }
        out = []
        for key in ALL_KEYS:
            out.append({
                "label": labels[key],
                "val1": self._val1(key),
                "val2": self._val2(key),
            })
        return out
