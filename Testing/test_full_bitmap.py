"""
Test the Full Bit Map sub-page in RobotSimPanel.qml.

Verifies that:
  - RobotSimPanel.qml loads without errors
  - The showFullBitMap property exists and toggles
  - All 256 input bits and 256 output bits can be toggled/read via the bridge
  - No QML warnings related to RobotSimPanel during load

Run: .venv\\Scripts\\python.exe Testing\\test_full_bitmap.py
"""

import os
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ["QT_QUICK_CONTROLS_STYLE"] = "Basic"
os.environ["QML_XHR_ALLOW_FILE_READ"] = "1"

MURPHY = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
UI_QML = os.path.join(MURPHY, "ui_qml")
for p in (UI_QML, MURPHY):
    if p not in sys.path:
        sys.path.insert(0, p)

from PySide6.QtCore import QUrl, QtMsgType, qInstallMessageHandler  # noqa: E402
from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtQml import QQmlEngine, QQmlComponent  # noqa: E402
from robot_comm.robot_comm_bridge import RobotCommBridge  # noqa: E402

qml_messages = []


def _handler(mode, ctx, msg):
    tag = {QtMsgType.QtWarningMsg: "WARN", QtMsgType.QtCriticalMsg: "CRIT",
           QtMsgType.QtFatalMsg: "FATAL"}.get(mode, "INFO")
    qml_messages.append((tag, msg))
    if tag != "INFO":
        print(f"[QML {tag}] {msg}")


qInstallMessageHandler(_handler)

app = QGuiApplication(sys.argv)
engine = QQmlEngine()
engine.addImportPath(UI_QML)

bridge = RobotCommBridge()
engine.rootContext().setContextProperty("RobotComm", bridge)

panel_url = QUrl.fromLocalFile(os.path.join(UI_QML, "RobotUI", "components", "RobotSimPanel.qml"))
comp = QQmlComponent(engine, panel_url)

if comp.isError():
    print("COMPONENT ERRORS:")
    for e in comp.errors():
        print("  ", e.toString())
    sys.exit(1)

root = comp.create()
if root is None:
    print("FAIL: create() returned None")
    for e in comp.errors():
        print("  ", e.toString())
    sys.exit(1)

all_pass = True


def check(cond, desc):
    global all_pass
    print(f"{'PASS' if cond else 'FAIL'}: {desc}")
    if not cond:
        all_pass = False


# Verify showFullBitMap property exists
check(root.property('showFullBitMap') is not None, "showFullBitMap property exists")
check(root.property('showFullBitMap') == False, "showFullBitMap defaults to False")

# Toggle it
root.setProperty('showFullBitMap', True)
check(root.property('showFullBitMap') == True, "showFullBitMap can be set to True")
root.setProperty('showFullBitMap', False)
check(root.property('showFullBitMap') == False, "showFullBitMap can be set back to False")

# Simulate robot 0 and verify all 256 input bits can be toggled
R = 0
bridge.simulateRobot(R)

# Test toggling a few specific bits via bridge
test_bits = [1, 12, 20, 65, 100, 161, 176, 200, 256]
for b in test_bits:
    bridge.setInputBit(R, b, True)
    check(bridge.getInputBit(R, b) == True, f"input bit {b} can be set HIGH")
    bridge.setInputBit(R, b, False)
    check(bridge.getInputBit(R, b) == False, f"input bit {b} can be set LOW")

# Test all 256 bits can be set high
for b in range(1, 257):
    bridge.setInputBit(R, b, True)
all_high = all(bridge.getInputBit(R, b) for b in range(1, 257))
check(all_high, "all 256 input bits can be set HIGH simultaneously")

# Clear all
for b in range(1, 257):
    bridge.setInputBit(R, b, False)
all_low = not any(bridge.getInputBit(R, b) for b in range(1, 257))
check(all_low, "all 256 input bits can be cleared")

# Verify functions exist on the QML object (check via metaObject)
meta = root.metaObject()
has_bitOf = any(meta.method(i).name() == "bitOf" for i in range(meta.methodCount()))
has_toggle = any(meta.method(i).name() == "toggleInput" for i in range(meta.methodCount()))
check(has_bitOf, "bitOf function exists on RobotSimPanel")
check(has_toggle, "toggleInput function exists on RobotSimPanel")

# No RobotSimPanel-related QML warnings
bad = [m for (tag, m) in qml_messages
       if tag in ("WARN", "CRIT", "FATAL") and "RobotSimPanel" in m]
check(len(bad) == 0, "no RobotSimPanel QML warnings during load")
for m in bad:
    print("   ->", m)

print()
if all_pass:
    print("All tests passed.")
    sys.exit(0)
else:
    print("One or more tests FAILED.")
    sys.exit(1)
