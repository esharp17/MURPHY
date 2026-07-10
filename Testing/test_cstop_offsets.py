"""
Test the C-Stop fine-offset rows in CellStatusScreen_4.qml.

Loads the screen headlessly with a real RobotCommBridge bound as `RobotComm`,
then exercises the vertical/horizontal offset writers and verifies the
binary/decimal wire encoding:
  - Vertical   offset (mm) -> output word 6  (bits 97-112),  value = round(mm*10)
  - Horizontal offset (mm) -> output word 7  (bits 113-128), value = round(mm*10)
  - Negative values use 16-bit two's complement.
  - openCStop() resets both words to 0.
Also confirms the QML (including the new rows) instantiates with no
screen-related QML warnings.

Run: .venv\\Scripts\\python.exe Testing\\test_cstop_offsets.py
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

from PySide6.QtCore import (QUrl, QtMsgType, qInstallMessageHandler,  # noqa: E402
                            QMetaObject, Qt, Q_ARG)
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


def invoke(name, arg0, arg1):
    QMetaObject.invokeMethod(root, name, Qt.DirectConnection,
                             Q_ARG("QVariant", arg0), Q_ARG("QVariant", arg1))


def word(r, wi):
    outs = bridge.getOutputs(r)
    return int(outs[wi]) & 0xFFFF if outs and len(outs) > wi else None


R = 0
bridge.simulateRobot(R)

# ── Vertical -> word 6 ────────────────────────────────────────────────────────
invoke("writeVertOffset", R, 3.5)
check(word(R, 6) == 35, "vertical +3.5mm -> word 6 == 35")

invoke("writeVertOffset", R, 10.0)
check(word(R, 6) == 100, "vertical +10.0mm -> word 6 == 100")

invoke("writeVertOffset", R, -2.0)
check(word(R, 6) == (0x10000 - 20), "vertical -2.0mm -> word 6 == 0xFFEC (two's complement)")

invoke("writeVertOffset", R, -10.0)
check(word(R, 6) == (0x10000 - 100), "vertical -10.0mm -> word 6 == 0xFF9C (two's complement)")

# ── Horizontal -> word 7 ─────────────────────────────────────────────────────
invoke("writeHorizOffset", R, 7.3)
check(word(R, 7) == 73, "horizontal +7.3mm -> word 7 == 73")

invoke("writeHorizOffset", R, -5.1)
check(word(R, 7) == (0x10000 - 51), "horizontal -5.1mm -> word 7 == 0xFFCD (two's complement)")

# ── Bit mapping: word 6 == bits 97-112, word 7 == bits 113-128 ────────────────
invoke("writeVertOffset", R, 3.5)     # 35 = 0b0000000000100011
invoke("writeHorizOffset", R, 0.0)
bits_ok = (bridge.getOutputBit(R, 97) and bridge.getOutputBit(R, 98)
           and not bridge.getOutputBit(R, 99) and not bridge.getOutputBit(R, 100)
           and not bridge.getOutputBit(R, 101) and bridge.getOutputBit(R, 102))
check(bits_ok, "value 35 maps onto bits 97,98,102 (word 6 = bits 97-112)")

invoke("writeHorizOffset", R, 1.0)    # 10 = 0b1010 -> bits 114,116
h_ok = (not bridge.getOutputBit(R, 113) and bridge.getOutputBit(R, 114)
        and not bridge.getOutputBit(R, 115) and bridge.getOutputBit(R, 116))
check(h_ok, "value 10 maps onto bits 114,116 (word 7 = bits 113-128)")

# ── openCStop resets both offset words to 0 ──────────────────────────────────
invoke("writeVertOffset", R, 6.0)
invoke("writeHorizOffset", R, 6.0)
QMetaObject.invokeMethod(root, "openCStop", Qt.DirectConnection, Q_ARG("QVariant", R))
check(word(R, 6) == 0 and word(R, 7) == 0, "openCStop() resets vertical & horizontal words to 0")

# ── No screen-related QML warnings on load/run ───────────────────────────────
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
