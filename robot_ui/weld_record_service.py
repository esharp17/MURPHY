import os
import csv
from datetime import datetime
from PySide6.QtCore import QObject, Slot, Signal


class WeldRecordService(QObject):
    """Handles saving weld record data to a local CSV file."""

    saveSuccess = Signal(str)       # emits the file path on success
    saveError = Signal(str)         # emits error message on failure

    CSV_HEADERS = [
        "Timestamp",
        "Weld ID",
        "Project",
        "Client",
        "Operator",
        "Location Coords",
        "Upstream Heat #",
        "Downstream Heat #",
        "Comments",
        "Pipe Diameter",
        "Wall Thickness",
        "Bevel Prep",
        "Pre-Heat Temp",
        "Wire Type",
        "Wire Diameter",
        "Wire Brand",
        "Shield Gas",
    ]

    def __init__(self, save_dir: str = "", parent=None):
        super().__init__(parent)
        if save_dir:
            self._save_dir = save_dir
        else:
            self._save_dir = os.path.join(
                os.path.dirname(os.path.abspath(__file__)), "..", "weld_records"
            )
        os.makedirs(self._save_dir, exist_ok=True)
        self._csv_path = os.path.join(self._save_dir, "weld_records.csv")

    @Slot(str, str, str, str, str, str, str, str, result=str)
    def saveWeldRecord(
        self,
        weld_id: str,
        project: str,
        client: str,
        operator: str,
        upstream_heat: str,
        downstream_heat: str,
        comments: str,
        location_coords: str,
    ) -> str:
        """
        Validate required fields and append a row to the CSV.
        Returns empty string on success, or an error message string.
        """
        # --- Validation ---
        missing = []
        if not weld_id.strip():
            missing.append("Weld ID")
        if not project.strip():
            missing.append("Project")
        if not client.strip():
            missing.append("Client")
        

        if missing:
            msg = "Missing required fields: " + ", ".join(missing)
            self.saveError.emit(msg)
            return msg

        # --- Write CSV ---
        try:
            file_exists = os.path.isfile(self._csv_path)
            with open(self._csv_path, "a", newline="", encoding="utf-8") as f:
                writer = csv.writer(f)
                if not file_exists:
                    writer.writerow(self.CSV_HEADERS)
                writer.writerow([
                    datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                    weld_id.strip(),
                    project.strip(),
                    client.strip(),
                    operator.strip(),
                    location_coords.strip(),
                    upstream_heat.strip(),
                    downstream_heat.strip(),
                    comments.strip(),
                    "1,219mm / 48\"",
                    "15.88mm / 0.625\"",
                    "30°",
                    "100° C / 212°F",
                    "GMAW",
                    "1.2mm / 0.045\"",
                    "Lincoln",
                    "Ar/Co2 85/15",
                ])
            self.saveSuccess.emit(self._csv_path)
            return ""
        except Exception as e:
            msg = "Failed to save: " + str(e)
            self.saveError.emit(msg)
            return msg
