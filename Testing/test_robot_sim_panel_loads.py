"""
Headless load test for RobotSimPanel.qml (the "act as the robot" backdoor).

Instantiates the QML component offscreen with a real RobotCommBridge bound as
the `RobotComm` context property, forces it visible (which triggers refresh()
and all the Repeater/binding evaluation), drives the simulation, and fails if
QML emits ANY warning/error referencing the panel.

Run: .venv\\Scripts\\python.exe Testing\\test_robot_sim_panel_loads.py
"""

import os
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ["QT_QUICK_CONTROLS_STYLE"] = "Basic"

MURPHY = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
UI_QML = os.path.join(MURPHY, "ui_qml")
for p in (UI_QML, MURPHY):
    if p not in sys.path:
        sys.path.insert(0, p)

from PySide6.QtCore import QUrl, QTimer, QtMsgType, qInstallMessageHandler, QMetaObject, Qt, Q_ARG  # noqa: E402
from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtQml import QQmlEngine, QQmlComponent  # noqa: E402
from robot_comm.robot_comm_bridge import RobotCommBridge  # noqa: E402

qml_messages = []


def _handler(mode, ctx, msg):
    tag = {QtMsgType.QtDebugMsg: "DEBUG", QtMsgType.QtInfoMsg: "INFO",
           QtMsgType.QtWarningMsg: "WARN", QtMsgType.QtCriticalMsg: "CRIT",
           QtMsgType.QtFatalMsg: "FATAL"}.get(mode, "?")
    qml_messages.append((tag, msg))
    print(f"[QML {tag}] {msg}")


qInstallMessageHandler(_handler)

app = QGuiApplication(sys.argv)
engine = QQmlEngine()
engine.addImportPath(UI_QML)  # so 'import RobotUI 1.0' resolves

bridge = RobotCommBridge()
engine.rootContext().setContextProperty("RobotComm", bridge)

wrapper_qml = b"""
import QtQuick 2.15
import RobotUI 1.0
Item {
    width: 1200; height: 900
    visible: true
    RobotSimPanel { objectName: "simpanel"; anchors.fill: parent; visible: true }
}
"""

comp = QQmlComponent(engine)
comp.setData(wrapper_qml, QUrl.fromLocalFile(os.path.join(UI_QML, "RobotUI", "_simpanel_test.qml")))

if comp.isError():
    print("COMPONENT ERRORS:")
    for e in comp.errors():
        print("  ", e.toString())
    sys.exit(1)

obj = comp.create()
if obj is None:
    print("FAIL: component.create() returned None")
    for e in comp.errors():
        print("  ", e.toString())
    sys.exit(1)

panel = obj.findChild(object, "simpanel")
if panel is None:
    print("FAIL: could not find RobotSimPanel child")
    sys.exit(1)

# Drive the simulation to exercise live bindings/refresh paths.
bridge.simulateRobot(0)
QMetaObject.invokeMethod(panel, "open", Qt.DirectConnection, Q_ARG("QVariant", 0))
bridge.setInputBit(0, 20, True)   # C-Stop ack HIGH
bridge.setInputPos(0, 137)
bridge.setOutputWord(0, 1, 1 << 3)  # HMI C-Stop output HIGH
QMetaObject.invokeMethod(panel, "refresh", Qt.DirectConnection)


def finish():
    bad = [m for (tag, m) in qml_messages
           if any(t in tag for t in ("WARN", "CRIT", "FATAL"))
           and ("RobotSimPanel" in m or "_simpanel_test" in m)]
    print()
    if bad:
        print(f"FAIL: {len(bad)} QML warning(s)/error(s) reference the panel:")
        for m in bad:
            print("  ", m)
        app.exit(1)
    else:
        print("PASS: RobotSimPanel loaded and ran with no panel-related QML warnings.")
        app.exit(0)


QTimer.singleShot(600, finish)
sys.exit(app.exec())
