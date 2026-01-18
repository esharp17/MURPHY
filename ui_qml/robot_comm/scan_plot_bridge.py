import os
import sys
import subprocess
import traceback

from PySide6.QtCore import QObject, Signal, Slot, QRunnable, QThreadPool


class _Worker(QRunnable):
    def __init__(self, fn, ok_sig, err_sig):
        super().__init__()
        self._fn = fn
        self._ok = ok_sig
        self._err = err_sig

    def run(self):
        try:
            self._fn()
            self._ok.emit()
        except Exception:
            self._err.emit(traceback.format_exc())


class ScanPlotBridge(QObject):
    error = Signal(str)
    launched = Signal()

    def __init__(self, base_dir, fetch_offsets_xml_from_robot, normalize_offsets_xml,
                 plot_script_name="Plot_points.py"):
        super().__init__()
        self._base_dir = base_dir
        self._fetch = fetch_offsets_xml_from_robot
        self._norm = normalize_offsets_xml
        self._plot_script = os.path.join(base_dir, plot_script_name)
        self._pool = QThreadPool.globalInstance()

    @Slot()
    def showScanData(self):
        def job():
            xml_path = self._fetch()
            xml_path = self._norm(xml_path)

            if not os.path.exists(xml_path):
                raise FileNotFoundError(f"Normalized offsets missing: {xml_path}")

            if not os.path.exists(self._plot_script):
                raise FileNotFoundError(f"Missing plot script: {self._plot_script}")

            subprocess.Popen([sys.executable, self._plot_script], cwd=self._base_dir)

        self._pool.start(_Worker(job, self.launched, self.error))
