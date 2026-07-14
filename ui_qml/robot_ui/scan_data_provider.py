"""
ScanDataProvider - QObject that loads scan XML data and exposes it to QML.
Parses base_points.xml and offsets_norm.xml, computes actual positions,
and provides data for the Qt Quick 3D scan plot.
"""
import os
import sys
import xml.etree.ElementTree as ET

from PySide6.QtCore import QObject, Signal, Slot, Property

from robot_comm.scan_plot_helpers import fetch_offsets_xml_from_robot, normalize_offsets_xml

MAX_POINTS = 180
OFFSETS_XML = "offsets_norm.xml"
BASE_XML = "base_points.xml"
INCH_TO_MM = 25.4
DEFAULT_CYL_DIAM_IN = 45.0


def _find_base_dir():
    if getattr(sys, "frozen", False):
        return os.path.dirname(sys.executable)
    return os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def _load_xml_points(path, max_points=MAX_POINTS):
    if not os.path.exists(path):
        raise FileNotFoundError(f"Could not find {path}")
    tree = ET.parse(path)
    root = tree.getroot()
    positions, xs, ys, zs = [], [], [], []
    for el in root.iter("row"):
        try:
            pos = int(float(el.attrib.get("pos", "0").strip() or "0"))
            x = float(el.attrib.get("x", "0").strip() or "0")
            y = float(el.attrib.get("y", "0").strip() or "0")
            z = float(el.attrib.get("z", "0").strip() or "0")
        except ValueError:
            continue
        positions.append(pos)
        xs.append(x); ys.append(y); zs.append(z)
        if len(positions) >= max_points:
            break
    return positions, xs, ys, zs


def _load_offsets_xml(path, max_points=MAX_POINTS):
    if not os.path.exists(path):
        raise FileNotFoundError(f"Could not find {path}")
    tree = ET.parse(path)
    root = tree.getroot()
    positions, xs, ys, zs, gaps, scheds = [], [], [], [], [], []
    for el in root.iter("row"):
        try:
            pos = int(float(el.attrib.get("pos", "0").strip() or "0"))
            x = float(el.attrib.get("x", "0").strip() or "0")
            y = float(el.attrib.get("y", "0").strip() or "0")
            z = float(el.attrib.get("z", "0").strip() or "0")
            g = float(el.attrib.get("g", "0").strip() or "0")
            s = float(el.attrib.get("s", "0").strip() or "0")
        except ValueError:
            continue
        positions.append(pos)
        xs.append(x); ys.append(y); zs.append(z)
        gaps.append(g); scheds.append(s)
        if len(positions) >= max_points:
            break
    return positions, xs, ys, zs, gaps, scheds


class ScanDataProvider(QObject):
    dataChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._base_dir = _find_base_dir()
        self._loaded = False
        self._error = ""

        # Raw aligned data
        self._positions = []
        self._base_x = []
        self._base_y = []
        self._base_z = []
        self._actual_x = []
        self._actual_y = []
        self._actual_z = []
        self._offset_x = []
        self._offset_y = []
        self._offset_z = []
        self._gaps = []
        self._schedules = []

        # Computed bounds
        self._gap_min = 0.0
        self._gap_max = 1.0
        self._center_x = 0.0
        self._center_y = 0.0
        self._center_z = 0.0
        self._y_min = 0.0
        self._y_max = 0.0
        self._scene_radius = 500.0

    @Slot(result=bool)
    def refreshFromRobot(self):
        """Fetch the latest scan offsets XML from the robot and load it into the provider."""
        try:
            robot_ip = os.environ.get("MURPHY_ROBOT_IP", "192.168.2.1")
            ftp_user = os.environ.get("MURPHY_FTP_USER", "PC")
            ftp_pass = os.environ.get("MURPHY_FTP_PASS", "1234")
            local_xml = fetch_offsets_xml_from_robot(robot_ip, ftp_user, ftp_pass, self._base_dir)
            normalized_xml = normalize_offsets_xml(local_xml, self._base_dir)
            if not os.path.exists(normalized_xml):
                raise FileNotFoundError(f"Normalized scan XML missing: {normalized_xml}")
            self.loadData(force_path=normalized_xml)
            return True
        except Exception as e:
            self._error = f"Scan fetch failed: {e}"
            self._loaded = False
            self.dataChanged.emit()
            return False

    @Slot()
    def loadData(self, force_path=None):
        """Load and process XML data files."""
        try:
            offsets_path = force_path or os.path.join(self._base_dir, OFFSETS_XML)
            base_path = os.path.join(self._base_dir, BASE_XML)

            o_pos, o_x, o_y, o_z, o_gap, o_sched = _load_offsets_xml(offsets_path)
            b_pos, b_x, b_y, b_z = _load_xml_points(base_path)

            base_map = {int(p): (bx, by, bz) for p, bx, by, bz in zip(b_pos, b_x, b_y, b_z)}

            self._positions = []
            self._base_x = []; self._base_y = []; self._base_z = []
            self._actual_x = []; self._actual_y = []; self._actual_z = []
            self._offset_x = []; self._offset_y = []; self._offset_z = []
            self._gaps = []; self._schedules = []

            for p, x, y, z, g, s in zip(o_pos, o_x, o_y, o_z, o_gap, o_sched):
                if p in base_map:
                    bx, by, bz = base_map[p]
                    self._positions.append(p)
                    self._base_x.append(bx); self._base_y.append(by); self._base_z.append(bz)
                    self._offset_x.append(x); self._offset_y.append(y); self._offset_z.append(z)
                    self._actual_x.append(bx + x); self._actual_y.append(by + y); self._actual_z.append(bz + z)
                    self._gaps.append(g); self._schedules.append(s)
                if len(self._positions) >= MAX_POINTS:
                    break

            if not self._positions:
                self._error = "No overlapping positions between base and offsets"
                self._loaded = False
                self.dataChanged.emit()
                return

            # Compute bounds
            all_x = self._base_x + self._actual_x
            all_y = self._base_y + self._actual_y
            all_z = self._base_z + self._actual_z

            self._center_x = 0.5 * (min(all_x) + max(all_x))
            self._center_y = 0.5 * (min(all_y) + max(all_y))
            self._center_z = 0.5 * (min(all_z) + max(all_z))

            self._y_min = min(all_y)
            self._y_max = max(all_y)

            x_range = max(all_x) - min(all_x)
            y_range = max(all_y) - min(all_y)
            z_range = max(all_z) - min(all_z)
            self._scene_radius = max(x_range, y_range, z_range) * 0.6

            if self._gaps:
                self._gap_min = min(self._gaps)
                self._gap_max = max(self._gaps)
                if self._gap_max == self._gap_min:
                    self._gap_max = self._gap_min + 1.0

            self._loaded = True
            self._error = ""
            self.dataChanged.emit()

        except Exception as e:
            self._error = str(e)
            self._loaded = False
            self.dataChanged.emit()

    # --- Properties exposed to QML ---

    @Slot(result=bool)
    def isLoaded(self):
        return self._loaded

    @Slot(result=str)
    def errorString(self):
        return self._error

    @Slot(result=int)
    def pointCount(self):
        return len(self._positions)

    @Slot(result=float)
    def gapMin(self):
        return self._gap_min

    @Slot(result=float)
    def gapMax(self):
        return self._gap_max

    @Slot(result=float)
    def centerX(self):
        return self._center_x

    @Slot(result=float)
    def centerY(self):
        return self._center_y

    @Slot(result=float)
    def centerZ(self):
        return self._center_z

    @Slot(result=float)
    def sceneRadius(self):
        return self._scene_radius

    @Slot(result=float)
    def yMin(self):
        return self._y_min

    @Slot(result=float)
    def yMax(self):
        return self._y_max

    @Slot(result=float)
    def cylinderRadius(self):
        return (DEFAULT_CYL_DIAM_IN * INCH_TO_MM) / 2.0

    # --- Point data accessors ---

    @Slot(result=list)
    def getBasePoints(self):
        """Returns list of [x, y, z] for base path."""
        return [[self._base_x[i], self._base_y[i], self._base_z[i]]
                for i in range(len(self._positions))]

    @Slot(result=list)
    def getActualPoints(self):
        """Returns list of [x, y, z] for actual path."""
        return [[self._actual_x[i], self._actual_y[i], self._actual_z[i]]
                for i in range(len(self._positions))]

    @Slot(result=list)
    def getGaps(self):
        """Returns list of gap values."""
        return list(self._gaps)

    @Slot(result=list)
    def getSchedules(self):
        """Returns list of schedule values."""
        return list(self._schedules)

    @Slot(result=list)
    def getPositions(self):
        """Returns list of position indices."""
        return list(self._positions)

    @Slot(int, result=str)
    def getPointInfo(self, index):
        """Returns formatted info string for a point at the given index."""
        if index < 0 or index >= len(self._positions):
            return ""
        pos = self._positions[index]
        gap = self._gaps[index]
        sched = self._schedules[index]
        ox = self._offset_x[index]
        oy = self._offset_y[index]
        oz = self._offset_z[index]
        return (f"Pos: {pos}  |  Gap: {gap:.3f}mm  |  Sched: {sched:g}  |  "
                f"Offset: X={ox:.3f}, Y={oy:.3f}, Z={oz:.3f}")

    @Slot(int, result=str)
    def getGapColor(self, index):
        """Returns hex color for a point based on its gap value (green→yellow→orange→red)."""
        if index < 0 or index >= len(self._gaps):
            return "#00ff00"
        gap = self._gaps[index]
        t = (gap - self._gap_min) / (self._gap_max - self._gap_min) if self._gap_max > self._gap_min else 0.0
        t = max(0.0, min(1.0, t))
        return _gap_to_color(t)


def _gap_to_color(t):
    """Map normalized value 0..1 to green→yellow→orange→red."""
    if t < 0.33:
        # Green to Yellow
        f = t / 0.33
        r = int(f * 255)
        g = 255
        b = 0
    elif t < 0.66:
        # Yellow to Orange
        f = (t - 0.33) / 0.33
        r = 255
        g = int(255 - f * 100)
        b = 0
    else:
        # Orange to Red
        f = (t - 0.66) / 0.34
        r = 255
        g = int(155 - f * 155)
        b = 0
    return f"#{r:02x}{g:02x}{b:02x}"
