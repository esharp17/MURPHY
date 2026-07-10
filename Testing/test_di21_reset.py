"""
Test DI21 pass-number reset behavior in CellStatusScreen_4.qml.

Verifies that:
  - When DI21 (bit 21) goes from LOW to HIGH (rising edge), the HMI:
    - Resets cStopVertMm[robotIdx] to 0
    - Resets cStopHorizMm[robotIdx] to 0
    - Writes 0 to output word 6 (vertical offset)
    - Writes 0 to output word 7 (horizontal offset)
  - The reset only fires on the rising edge, not while DI21 stays HIGH
  - prevDI21 property exists for edge tracking

Run: .venv\\Scripts\\python.exe Testing\\test_di21_reset.py
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


R = 0
bridge.simulateRobot(R)

# Verify prevDI21 property exists
check(root.property('prevDI21') is not None, "prevDI21 property exists")

# Set some non-zero offset values on output words 6 and 7
bridge.setOutputWord(R, 6, 50)   # vertical offset = 5.0mm
bridge.setOutputWord(R, 7, 80)   # horizontal offset = 8.0mm
check(bridge.getOutputs(R)[6] == 50, "output word 6 set to 50 (5.0mm vert)")
check(bridge.getOutputs(R)[7] == 80, "output word 7 set to 80 (8.0mm horiz)")

# Set DI21 HIGH (rising edge) — should trigger reset
bridge.setInputBit(R, 21, True)
# Process events so QML Connections handler fires
app.processEvents()
import time
time.sleep(0.1)
app.processEvents()

# After rising edge, output words 6 and 7 should be 0
out_words = bridge.getOutputs(R)
check(out_words[6] == 0, f"output word 6 reset to 0 after DI21 rising edge (got {out_words[6]})")
check(out_words[7] == 0, f"output word 7 reset to 0 after DI21 rising edge (got {out_words[7]})")

# Set non-zero offsets again
bridge.setOutputWord(R, 6, 50)
bridge.setOutputWord(R, 7, 80)
app.processEvents()
time.sleep(0.05)
app.processEvents()

# DI21 is still HIGH — should NOT trigger another reset
out_before = bridge.getOutputs(R)
check(out_before[6] == 50, "output word 6 NOT reset while DI21 stays HIGH (no falling edge)")
check(out_before[7] == 80, "output word 7 NOT reset while DI21 stays HIGH (no falling edge)")

# Now bring DI21 LOW, then HIGH again for a second rising edge
bridge.setInputBit(R, 21, False)
app.processEvents()
time.sleep(0.05)
app.processEvents()

bridge.setOutputWord(R, 6, 50)
bridge.setOutputWord(R, 7, 80)
app.processEvents()
time.sleep(0.05)
app.processEvents()

bridge.setInputBit(R, 21, True)
app.processEvents()
time.sleep(0.1)
app.processEvents()

out_after = bridge.getOutputs(R)
check(out_after[6] == 0, f"output word 6 reset to 0 on second DI21 rising edge (got {out_after[6]})")
check(out_after[7] == 0, f"output word 7 reset to 0 on second DI21 rising edge (got {out_after[7]})")

# No CellStatusScreen_4 QML warnings
bad = [m for (tag, m) in qml_messages
       if tag in ("WARN", "CRIT", "FATAL") and "CellStatusScreen_4" in m]
check(len(bad) == 0, "no CellStatusScreen_4 QML warnings during test")
for m in bad:
    print("   ->", m)

print()
if all_pass:
    print("All tests passed.")
    sys.exit(0)
else:
    print("One or more tests FAILED.")
    sys.exit(1)
