"""
End-to-end test: Cycle Start bit selection (bit 6 vs bit 18)

Tests the full chain:
  1. Input bit reading  - bridge stores robot inputs; paused/running detection
  2. Bit decomposition  - global 1-indexed bit → correct word index + local bit
  3. Output bit writing - bridge setOutputWord stores to correct word
  4. Full scenario      - simulates SideBar._pulseCmdBit logic for both paths
"""
import sys
import os
from pathlib import Path

# ROOT must come first so the real robot_ui package shadows the ui_qml stub
ROOT   = Path(__file__).resolve().parent.parent
UI_QML = ROOT / "ui_qml"
sys.path.insert(0, str(UI_QML))   # robot_comm lives here
sys.path.insert(0, str(ROOT))     # real robot_ui lives here (must be index 0)

# Suppress bridge startup prints
import io, contextlib
with contextlib.redirect_stdout(io.StringIO()):
    from robot_comm.robot_comm_bridge import RobotCommBridge

PASS = 0
FAIL = 0

def check(desc, got, expected):
    global PASS, FAIL
    ok = got == expected
    status = "PASS" if ok else "FAIL"
    print(f"{status}: {desc}  (got={got!r}, expected={expected!r})")
    if ok:
        PASS += 1
    else:
        FAIL += 1

# ── Helpers mirroring SideBar QML logic ──────────────────────────────────────

def set_bit(w, b1, on):
    """Mirrors SideBar._setBit (1-indexed)."""
    b = b1 - 1
    return (w | (1 << b)) if on else (w & ~(1 << b))

def decompose_bit(bit1):
    """Mirrors new _pulseCmdBit: returns (word_index, local_1based_bit)."""
    wi        = (bit1 - 1) // 16
    local_bit = ((bit1 - 1) % 16) + 1
    return wi, local_bit

def read_input_bit(bridge, robot, bit1):
    """Mirrors SideBar._robotBitOn (1-indexed)."""
    words = bridge.getInputs(robot)
    wi = (bit1 - 1) // 16
    bi = (bit1 - 1) % 16
    if wi >= len(words):
        return False
    return ((int(words[wi]) >> bi) & 1) == 1

def pulse_cmd_bit(bridge, robot, bit1):
    """
    Mirrors fixed _pulseCmdBit: sets the bit in the correct output word.
    Returns (word_index_written, value_written) for verification.
    """
    wi, local_bit = decompose_bit(bit1)
    outputs = bridge.getOutputs(robot)
    w_on = int(outputs[wi]) if wi < len(outputs) else 0
    value = set_bit(w_on, local_bit, True)
    bridge.setOutputWord(robot, wi, value)
    return wi, value

def cycle_start_logic(bridge, robot):
    """
    Mirrors tHoldStart per-robot decision (corrected semantics):
      Running  (bit 3 ON)       → skip (do nothing)
      Paused   (bit 4 ON)       → bit 6  (Start: resumes paused program)
      Aborted  (bits 3&4 both OFF) → bit 18 (Production Start: starts Main task)
    Returns the bit number that would be pulsed, or None if skipped.
    """
    BIT_ST_RUNNING    = 3
    BIT_ST_PAUSED     = 4
    BIT_CMD_START     = 6
    BIT_CMD_PROD_START = 18

    if read_input_bit(bridge, robot, BIT_ST_RUNNING):
        return None                  # running → skip
    if read_input_bit(bridge, robot, BIT_ST_PAUSED):
        return BIT_CMD_START         # paused → resume with bit 6
    return BIT_CMD_PROD_START        # aborted → start Main with bit 18

# ── Create bridge instance ────────────────────────────────────────────────────
bridge = RobotCommBridge()

print("\n─── 1. Bit decomposition ───────────────────────────────────────")
for bit1, exp_wi, exp_local in [
    (6,  0, 6),
    (16, 0, 16),
    (17, 1, 1),
    (18, 1, 2),
    (19, 1, 3),
    (20, 1, 4),
]:
    wi, lb = decompose_bit(bit1)
    check(f"bit {bit1:2d} → word {exp_wi}, localBit {exp_local}", (wi, lb), (exp_wi, exp_local))

print("\n─── 2. Output word storage (setOutputWord / getOutputs) ────────")
# Clear robot 0 outputs first
bridge.setOutputWord(0, 0, 0)
bridge.setOutputWord(0, 1, 0)

# Bit 6 → word 0, bit 5 set → value 32
wi6, val6 = pulse_cmd_bit(bridge, 0, 6)
check("bit 6 writes to word 0",     wi6, 0)
check("bit 6 value = 32 (0x0020)", val6, 32)
check("bridge getOutputs[0][0] = 32", int(bridge.getOutputs(0)[0]), 32)
check("bridge getOutputs[0][1] unchanged (0)", int(bridge.getOutputs(0)[1]), 0)

# Bit 18 → word 1, local bit 2, bit 1 set → value 2
wi18, val18 = pulse_cmd_bit(bridge, 0, 18)
check("bit 18 writes to word 1",    wi18, 1)
check("bit 18 value = 2 (0x0002)", val18, 2)
check("bridge getOutputs[0][0] unchanged (32)", int(bridge.getOutputs(0)[0]), 32)
check("bridge getOutputs[0][1] = 2", int(bridge.getOutputs(0)[1]), 2)

print("\n─── 3. Input bit reading (paused / running detection) ──────────")
# Directly set robot 1 input word 0 to simulate states
bridge._inputs[1][0] = 0   # idle: bit 3=0, bit 4=0
check("idle robot: running=False",  read_input_bit(bridge, 1, 3), False)
check("idle robot: paused=False",   read_input_bit(bridge, 1, 4), False)

bridge._inputs[1][0] = (1 << 2)   # bit 3 set (RUNNING, 1-indexed)
check("running robot: running=True", read_input_bit(bridge, 1, 3), True)
check("running robot: paused=False", read_input_bit(bridge, 1, 4), False)

bridge._inputs[1][0] = (1 << 3)   # bit 4 set (PAUSED, 1-indexed)
check("paused robot: running=False", read_input_bit(bridge, 1, 3), False)
check("paused robot: paused=True",   read_input_bit(bridge, 1, 4), True)

print("\n─── 4. Full cycle start scenarios ──────────────────────────────")
# Robot 2: aborted (bits 3&4 both OFF) → should get bit 18 (Production Start)
bridge._inputs[2][0] = 0
bridge.setOutputWord(2, 0, 0)
bridge.setOutputWord(2, 1, 0)
fired = cycle_start_logic(bridge, 2)
check("aborted robot fires bit 18 (Production Start)", fired, 18)
if fired:
    pulse_cmd_bit(bridge, 2, fired)
    check("aborted → word 0 unchanged (0)",          int(bridge.getOutputs(2)[0]), 0)
    check("aborted → word 1 has bit 18 (value 2)",   int(bridge.getOutputs(2)[1]), 2)

# Robot 3: paused (bit 4 ON) → should get bit 6 (Start/Resume)
bridge._inputs[3][0] = (1 << 3)   # bit 4 set (PAUSED, 1-indexed)
bridge.setOutputWord(3, 0, 0)
bridge.setOutputWord(3, 1, 0)
fired = cycle_start_logic(bridge, 3)
check("paused robot fires bit 6 (Start/Resume)", fired, 6)
if fired:
    pulse_cmd_bit(bridge, 3, fired)
    check("paused → word 0 has bit 6 (value 32)", int(bridge.getOutputs(3)[0]), 32)
    check("paused → word 1 unchanged (0)",         int(bridge.getOutputs(3)[1]), 0)

# Running robot: should be skipped (None)
bridge._inputs[2][0] = (1 << 2)   # bit 3 set (RUNNING, 1-indexed)
fired = cycle_start_logic(bridge, 2)
check("running robot is skipped (None)", fired, None)

# ── Summary ───────────────────────────────────────────────────────────────────
print(f"\n{'─'*55}")
print(f"Results: {PASS} passed, {FAIL} failed")
if FAIL:
    sys.exit(1)
print("All tests passed.")
