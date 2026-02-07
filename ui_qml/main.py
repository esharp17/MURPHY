import os
os.environ["QML_XHR_ALLOW_FILE_READ"] = "1"
print("QML_XHR_ALLOW_FILE_READ =", os.environ.get("QML_XHR_ALLOW_FILE_READ"))

import sys
from pathlib import Path

# Add parent directory to path so we can import robot_ui and robot_comm packages
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

os.environ["QML_XHR_ALLOW_FILE_READ"] = "1"
os.environ["QT_QUICK_CONTROLS_STYLE"] = "Basic"

from PySide6.QtCore import Qt, QUrl, QObject, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

from robot_comm.robot_comm_bridge import RobotCommBridge
from robot_comm.robot_state import RobotState
from robot_comm.robot_controller import RobotController
from robot_comm.scan_plot_bridge import ScanPlotBridge
from robot_comm.scan_plot_helpers import fetch_offsets_xml_from_robot, normalize_offsets_xml
from robot_ui.permissions import can_access_page_by_index
from robot_ui.models import Role
from robot_ui.user_service import UserService
from robot_ui.weld_record_service import WeldRecordService


class PermissionChecker(QObject):
    """Exposes permission checks to QML."""
    
    @Slot(int, int, result=bool)
    def canAccessPage(self, page_index: int, role_value: int) -> bool:
        """Check if a role can access a page by index."""
        try:
            role = Role(role_value)
            return can_access_page_by_index(page_index, role)
        except ValueError:
            return False


def _runtime_root() -> Path:
    if getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
        return Path(sys._MEIPASS)
    return Path(__file__).resolve().parent

def find_base_dir():
    if getattr(sys, "frozen", False):
        return os.path.dirname(sys.executable)
    return os.path.abspath(os.path.dirname(__file__))

BASE_DIR = find_base_dir()

def main() -> int:
    # -----------------------------
    # Core objects
    # -----------------------------
    robotComm = RobotCommBridge()
    robotState = RobotState()
    robotCtl = RobotController(robotComm, robotState)
    permissionChecker = PermissionChecker()
    userService = UserService()
    weldRecordService = WeldRecordService()

    app = QGuiApplication(sys.argv)
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("robotComm", robotComm)


    # -----------------------------
    # Expose to QML (MUST be before load)
    # -----------------------------
    engine.rootContext().setContextProperty("RobotComm", robotComm)
    engine.rootContext().setContextProperty("RobotCommBridge", robotComm)  # <-- FIX
    engine.rootContext().setContextProperty("RobotState", robotState)
    engine.rootContext().setContextProperty("RobotCtl", robotCtl)
    engine.rootContext().setContextProperty("PermissionChecker", permissionChecker)
    engine.rootContext().setContextProperty("UserService", userService)
    engine.rootContext().setContextProperty("WeldRecordService", weldRecordService)

    root = _runtime_root()
    engine.addImportPath(str(root))

    main_qml = root / "RobotUI" / "Main.qml"
    engine.load(QUrl.fromLocalFile(str(main_qml)))

    if not engine.rootObjects():
        return 1

    robot_ip  = "192.168.2.1"
    ftp_user  = "PC"
    ftp_pass  = "1234"

    scan_plot = ScanPlotBridge(
        base_dir=BASE_DIR,
        fetch_offsets_xml_from_robot=lambda: fetch_offsets_xml_from_robot(robot_ip, ftp_user, ftp_pass, BASE_DIR),
        normalize_offsets_xml=lambda p: normalize_offsets_xml(p, BASE_DIR),
        plot_script_name="Plot_points.py",
    )

    engine.rootContext().setContextProperty("ScanPlot", scan_plot)


    win = engine.rootObjects()[0]
    win.setFlags(win.flags() | Qt.FramelessWindowHint)
    win.showMaximized()

    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
