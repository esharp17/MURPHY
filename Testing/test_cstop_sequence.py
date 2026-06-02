"""
Test: C-Stop button sequence in CellStatusScreen_4.qml

Expected sequence when C-Stop is pressed:
  t=0ms    : bit 2 LOW  (drop OPERATE)
  t=250ms  : bit 2 HIGH (restore OPERATE)   [tCS1]
  t=500ms  : bit 4 HIGH (Cycle Stop)        [tCS2]
  t=750ms  : bit 4 LOW                      [tCS3]
  t=1000ms : bit 20 HIGH + bit 9 HIGH       [tCS4]
  t=1250ms : bit 9 LOW                      [tCS5]
"""

import re
import sys

QML_PATH = r"c:\Users\evanr\Desktop\Murphy\ui_qml\RobotUI\screens\CellStatusScreen_4.qml"

with open(QML_PATH, encoding="utf-8") as f:
    src = f.read()

all_pass = True

def check(condition, description):
    global all_pass
    status = "PASS" if condition else "FAIL"
    print(f"{status}: {description}")
    if not condition:
        all_pass = False

def extract_timer_body(timer_id):
    """Extract the onTriggered body of a Timer with the given id."""
    idx = src.find(f"id: {timer_id}")
    if idx == -1:
        return None
    trig = src.find("onTriggered", idx)
    if trig == -1:
        return None
    brace = src.find("{", trig)
    depth, i = 0, brace
    while i < len(src):
        if src[i] == "{": depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                break
        i += 1
    return src[brace:i+1]

# ── 1. Property declared ──────────────────────────────────────────────────────
check("cStopSeqRobot" in src, "cStopSeqRobot property declared")

# ── 2. All 5 timers exist with 250ms interval ─────────────────────────────────
for tid in ["tCS1", "tCS2", "tCS3", "tCS4", "tCS5"]:
    idx = src.find(f"id: {tid}")
    check(idx != -1, f"{tid} timer declared")
    if idx != -1:
        nearby = src[idx:idx+60]
        check("250" in nearby, f"{tid} has 250ms interval")

# ── 3. openCStop kicks off sequence correctly ─────────────────────────────────
oc_idx = src.find("function openCStop")
check(oc_idx != -1, "openCStop function present")
if oc_idx != -1:
    brace = src.find("{", oc_idx)
    depth, i = 0, brace
    while i < len(src):
        if src[i] == "{": depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                break
        i += 1
    oc_body = src[brace:i+1]

    check(re.search(r"setOutputBit.*2.*false", oc_body), "openCStop sets bit 2 LOW immediately")
    check("tCS1.restart()" in oc_body,                   "openCStop starts tCS1")
    check("cStopSeqRobot" in oc_body,                    "openCStop sets cStopSeqRobot")
    # bit 20 should NOT be set directly in openCStop anymore
    check(not re.search(r"setOutputBit.*20.*true", oc_body), "openCStop does NOT set bit 20 directly (delayed via tCS4)")

# ── 4. Per-timer bit operations ───────────────────────────────────────────────
tCS1_body = extract_timer_body("tCS1")
check(tCS1_body is not None, "tCS1 body extractable")
if tCS1_body:
    check(re.search(r"setOutputBit.*2.*true", tCS1_body),  "tCS1 restores bit 2 HIGH")
    check("tCS2.restart()" in tCS1_body,                   "tCS1 chains to tCS2")

tCS2_body = extract_timer_body("tCS2")
check(tCS2_body is not None, "tCS2 body extractable")
if tCS2_body:
    check(re.search(r"setOutputBit.*4.*true", tCS2_body),  "tCS2 sets bit 4 HIGH (Cycle Stop)")
    check("tCS3.restart()" in tCS2_body,                   "tCS2 chains to tCS3")

tCS3_body = extract_timer_body("tCS3")
check(tCS3_body is not None, "tCS3 body extractable")
if tCS3_body:
    check(re.search(r"setOutputBit.*4.*false", tCS3_body), "tCS3 clears bit 4 LOW")
    check("tCS4.restart()" in tCS3_body,                   "tCS3 chains to tCS4")

tCS4_body = extract_timer_body("tCS4")
check(tCS4_body is not None, "tCS4 body extractable")
if tCS4_body:
    check(re.search(r"setOutputBit.*20.*true", tCS4_body), "tCS4 sets bit 20 HIGH (C-Stop signal)")
    check(re.search(r"setOutputBit.*9.*true",  tCS4_body), "tCS4 sets bit 9 HIGH (Production Start)")
    check("tCS5.restart()" in tCS4_body,                   "tCS4 chains to tCS5")

tCS5_body = extract_timer_body("tCS5")
check(tCS5_body is not None, "tCS5 body extractable")
if tCS5_body:
    check(re.search(r"setOutputBit.*9.*false", tCS5_body),  "tCS5 clears bit 9 LOW (sequence complete)")
    check("cStopSeqRobot = -1" in tCS5_body,               "tCS5 resets cStopSeqRobot to -1")

# ── 5. Summary ────────────────────────────────────────────────────────────────
print()
if all_pass:
    print("All tests passed.")
else:
    print("One or more tests FAILED.")
    sys.exit(1)
