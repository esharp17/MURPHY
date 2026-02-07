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

    @Slot()
    def showScanDataLocal(self):
        """Launch the plot using local XML files (no FTP fetch)."""
        def job():
            offsets_norm = os.path.join(self._base_dir, "offsets_norm.xml")
            base_points = os.path.join(self._base_dir, "base_points.xml")

            if not os.path.exists(offsets_norm):
                raise FileNotFoundError(f"Missing local file: {offsets_norm}")
            if not os.path.exists(base_points):
                raise FileNotFoundError(f"Missing local file: {base_points}")
            if not os.path.exists(self._plot_script):
                raise FileNotFoundError(f"Missing plot script: {self._plot_script}")

            subprocess.Popen([sys.executable, self._plot_script], cwd=self._base_dir)

        self._pool.start(_Worker(job, self.launched, self.error))

    @Slot(result=str)
    def renderScanPlotLocal(self):
        """Render the plot to a PNG image with default view and return the file path."""
        return self._renderPlot(20.0, 140.0, 1.0)

    @Slot(float, float, float, result=str)
    def renderScanPlotView(self, elev, azim, zoom):
        """Render the plot to a PNG image with specified view and return the file path."""
        return self._renderPlot(elev, azim, zoom)

    def _renderPlot(self, elev, azim, zoom):
        render_script = os.path.join(self._base_dir, "Plot_to_image.py")
        output_path = os.path.join(self._base_dir, "scan_plot.png")

        offsets_norm = os.path.join(self._base_dir, "offsets_norm.xml")
        base_points = os.path.join(self._base_dir, "base_points.xml")

        if not os.path.exists(offsets_norm):
            return ""
        if not os.path.exists(base_points):
            return ""
        if not os.path.exists(render_script):
            return ""

        try:
            result = subprocess.run(
                [sys.executable, render_script, output_path,
                 "--elev", str(elev), "--azim", str(azim), "--zoom", str(zoom)],
                cwd=self._base_dir,
                capture_output=True, text=True, timeout=30
            )
            if result.returncode == 0 and os.path.exists(output_path):
                return output_path.replace("\\", "/")
            return ""
        except Exception:
            return ""
