"""
test_robot_state_display.py

Tests:
  1. robotStatus() logic  - running/paused/aborted state detection from input bits
  2. Hold button (bit 7)  - correct word/localBit decomposition and bridge storage
  3. Cycle Stop (bit 4)   - correct word/localBit decomposition and bridge storage
  4. _robotState() logic  - sidebar state strip helper mirrored in Python
"""
import sys
from pathlib import Path

ROOT   = Path(__file__).resolve().parent.parent
UI_QML = ROOT / "ui_qml"
sys.path.insert(0, str(UI_QML))
sys.path.insert(0, str(ROOT))

import io, contextlib
with contextlib.redirect_stdout(io.StringIO()):
    from robot_comm.robot_comm_bridge import RobotCommBridge

PASS = 0
FAIL = 0

def check(desc, got, expected):
    global PASS, FAIL
    ok = got == expected
    print(f"{'PASS' if ok else 'FAIL'}: {desc}  (got={got!r}, expected={expected!r})")
    if ok: PASS += 1
    else:  FAIL += 1

# ── Helpers ──────────────────────────────────────────────────────────────────

def set_bit(w, b1, on):
    b = b1 - 1
    return (w | (1 << b)) if on else (w & ~(1 << b))

def decompose_bit(bit1):
    wi        = (bit1 - 1) // 16
    local_bit = ((bit1 - 1) % 16) + 1
    return wi, local_bit

def robot_status(inputs_word0):
    """Mirror CellStatusScreen_4 robotStatus() for the 3-state model."""
    w = inputs_word0
    if (w >> 5) & 1: return "faulted"    # bit 6
    if (w >> 2) & 1: return "running"    # bit 3
    if (w >> 3) & 1: return "paused"     # bit 4
    return "aborted"

def sidebar_robot_state(inputs_word0):
    """Mirror SideBar._robotState()."""
    w = inputs_word0
    if (w >> 2) & 1: return "running"    # bit 3
    if (w >> 3) & 1: return "paused"     # bit 4
    return "aborted"

# ── Create bridge ─────────────────────────────────────────────────────────────
bridge = RobotCommBridge()

# ── 1. robotStatus logic ─────────────────────────────────────────────────────
print("\n─── 1. robotStatus() state detection ──────────────────────────")
check("aborted (bits 3&4 off)",  robot_status(0b00000000), "aborted")
check("running (bit 3 on)",      robot_status(0b00000100), "running")
check("paused  (bit 4 on)",      robot_status(0b00001000), "paused")
check("faulted (bit 6 on)",      robot_status(0b00100000), "faulted")
check("running takes priority over paused if both set",
      robot_status(0b00001100), "running")

# ── 2. Sidebar _robotState logic ─────────────────────────────────────────────
print("\n─── 2. Sidebar _robotState() ───────────────────────────────────")
check("aborted", sidebar_robot_state(0b00000000), "aborted")
check("running", sidebar_robot_state(0b00000100), "running")
check("paused",  sidebar_robot_state(0b00001000), "paused")

# ── 3. Hold button (bit 7) decomposition + storage ───────────────────────────
print("\n─── 3. Hold button bit 7 ───────────────────────────────────────")
wi7, lb7 = decompose_bit(7)
check("bit 7 → word 0",          wi7, 0)
check("bit 7 → localBit 7",      lb7, 7)
bridge.setOutputWord(0, 0, 0)
val = set_bit(0, lb7, True)
bridge.setOutputWord(0, wi7, val)
check("bit 7 value = 64 (0x0040)", val, 64)
check("bridge stores 64 in word 0", int(bridge.getOutputs(0)[0]), 64)

# ── 4. Cycle Stop (bit 4) decomposition + storage ────────────────────────────
print("\n─── 4. Cycle Stop bit 4 ────────────────────────────────────────")
wi4, lb4 = decompose_bit(4)
check("bit 4 → word 0",          wi4, 0)
check("bit 4 → localBit 4",      lb4, 4)
bridge.setOutputWord(1, 0, 0)
val4 = set_bit(0, lb4, True)
bridge.setOutputWord(1, wi4, val4)
check("bit 4 value = 8 (0x0008)", val4, 8)
check("bridge stores 8 in word 0", int(bridge.getOutputs(1)[0]), 8)

# ── 5. State transitions drive correct Cycle Start bit ───────────────────────
print("\n─── 5. Cycle Start bit selection per state ─────────────────────")
BIT_CMD_START      = 6
BIT_CMD_PROD_START = 18

def cycle_start_bit(inputs_word0):
    w = inputs_word0
    if (w >> 2) & 1: return None           # running → skip
    if (w >> 3) & 1: return BIT_CMD_START  # paused → bit 6
    return BIT_CMD_PROD_START              # aborted → bit 18

check("aborted → bit 18", cycle_start_bit(0b00000000), 18)
check("running → None",   cycle_start_bit(0b00000100), None)
check("paused  → bit 6",  cycle_start_bit(0b00001000), 6)

# ── Summary ───────────────────────────────────────────────────────────────────
print(f"\n{'─'*55}")
print(f"Results: {PASS} passed, {FAIL} failed")
if FAIL:
    sys.exit(1)
print("All tests passed.")
