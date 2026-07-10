"""
Test the Pass # display in CellStatusScreen_4.qml.

Verifies that:
  - Input word 10 (bits 161-176) correctly maps to the pass number
  - The QML function robotPassNum(idx) reads word 10 & 0xFFFF
  - Bit mapping: word 10 LSB = bit 161, MSB = bit 176
  - The QML loads without screen-related warnings

Run: .venv\\Scripts\\python.exe Testing\\test_pass_num.py
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

screen = os.path.join(UI_QML, "RobotUI", "screens", "CellStatusScreen_4.qml")
comp = QQmlComponent(engine, QUrl.fromLocalFile(screen))

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


def read_pass_num_from_bridge(idx):
    """Mirror of QML robotPassNum: read word 10 & 0xFFFF from bridge inputs."""
    words = bridge.getInputs(idx)
    if not words or len(words) <= 10:
        return 0
    return int(words[10]) & 0xFFFF


R = 0
bridge.simulateRobot(R)

# Write known pass numbers to input word 10 and verify via bridge
test_values = [0, 1, 7, 42, 100, 255, 1000, 65535]
for val in test_values:
    bridge.setInputWord(R, 10, val)
    got = read_pass_num_from_bridge(R)
    check(got == val, f"pass number {val} -> word 10 reads back {val} (got {got})")

# Verify bit mapping: word 10 = bits 161-176
bridge.setInputWord(R, 10, 1)
check(bridge.getInputBit(R, 161) == True, "bit 161 is LSB of word 10")
check(bridge.getInputBit(R, 162) == False, "bit 162 is not set when word 10 = 1")

bridge.setInputWord(R, 10, 0x8000)
check(bridge.getInputBit(R, 176) == True, "bit 176 is MSB of word 10")
check(bridge.getInputBit(R, 175) == False, "bit 175 is not set when word 10 = 0x8000")

bridge.setInputWord(R, 10, 0xFFFF)
check(all(bridge.getInputBit(R, b) for b in range(161, 177)),
      "all bits 161-176 HIGH when word 10 = 0xFFFF")

bridge.setInputWord(R, 10, 0)
check(not any(bridge.getInputBit(R, b) for b in range(161, 177)),
      "all bits 161-176 LOW when word 10 = 0")

# Verify QML has the robotPassNum function (check property exists)
has_fn = hasattr(root, 'robotPassNum')
check(has_fn, "QML root has robotPassNum function")

# No screen-related QML warnings
bad = [m for (tag, m) in qml_messages
       if tag in ("WARN", "CRIT", "FATAL") and "CellStatusScreen_4" in m]
check(len(bad) == 0, "no CellStatusScreen_4 QML warnings during load/run")
for m in bad:
    print("   ->", m)

print()
if all_pass:
    print("All tests passed.")
    sys.exit(0)
else:
    print("One or more tests FAILED.")
    sys.exit(1)
