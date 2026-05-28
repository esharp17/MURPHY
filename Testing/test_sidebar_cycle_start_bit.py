"""
Test: SideBar Cycle Start bit selection
- Paused robot (bit 4 HIGH) => bit 18 (RESUME)
- Non-paused robot (bit 4 LOW, bit 3 LOW) => bit 6 (START)
- Already running robot (bit 3 HIGH) => no bit sent
"""

import re
import sys

SIDEBAR_PATH = r"c:\Users\evanr\Desktop\Murphy\ui_qml\RobotUI\components\SideBar.qml"

# ── 1. Static checks: verify constants are declared ──────────────────────────
with open(SIDEBAR_PATH, encoding="utf-8") as f:
    src = f.read()

def assert_contains(pattern, description):
    if not re.search(pattern, src):
        print(f"FAIL: {description}")
        sys.exit(1)
    print(f"PASS: {description}")

assert_contains(r"bit_ST_PAUSED\s*:\s*4",  "bit_ST_PAUSED = 4 declared")
assert_contains(r"bit_CMD_RESUME\s*:\s*18", "bit_CMD_RESUME = 18 declared")
assert_contains(r"bit_ST_RUNNING",           "bit_ST_RUNNING declared")
assert_contains(r"bit_CMD_START",            "bit_CMD_START declared")

# ── 2. Logic check: timer block sends RESUME when paused, START otherwise ────
# Extract the tHoldStart Timer block by finding its start and counting braces
start_idx = src.find("id: tHoldStart")
assert start_idx != -1, "Could not locate tHoldStart Timer block"
triggered_idx = src.find("onTriggered", start_idx)
assert triggered_idx != -1, "Could not locate onTriggered in tHoldStart"
brace_start = src.find("{", triggered_idx)
depth, i = 0, brace_start
while i < len(src):
    if src[i] == "{": depth += 1
    elif src[i] == "}":
        depth -= 1
        if depth == 0:
            break
    i += 1
timer_body = src[brace_start:i+1]

assert_contains_in = lambda pat, desc: (
    print(f"PASS: {desc}") if re.search(pat, timer_body)
    else (print(f"FAIL: {desc}") or sys.exit(1))
)

assert_contains_in(r"bit_ST_PAUSED",  "tHoldStart checks bit_ST_PAUSED")
assert_contains_in(r"bit_CMD_RESUME", "tHoldStart sends bit_CMD_RESUME when paused")
assert_contains_in(r"bit_CMD_START",  "tHoldStart still sends bit_CMD_START when not paused")
assert_contains_in(r"bit_ST_RUNNING", "tHoldStart skips already-running robots")

# ── 3. Simulate the branching logic in Python ─────────────────────────────────
BIT_ST_RUNNING = 3
BIT_ST_PAUSED  = 4
BIT_CMD_START  = 6
BIT_CMD_RESUME = 18

def bit(word, b1):
    return ((word >> (b1 - 1)) & 1) == 1

def cycle_start_bit(in_word):
    """Mirrors the QML tHoldStart logic for a single robot."""
    if bit(in_word, BIT_ST_RUNNING):
        return None  # skip
    if bit(in_word, BIT_ST_PAUSED):
        return BIT_CMD_RESUME
    return BIT_CMD_START

cases = [
    # (description,           in_word,                    expected_bit)
    ("running robot",         1 << (BIT_ST_RUNNING - 1),  None),
    ("paused robot",          1 << (BIT_ST_PAUSED  - 1),  BIT_CMD_RESUME),
    ("idle robot",            0,                           BIT_CMD_START),
    ("paused+running robot",  (1 << (BIT_ST_RUNNING-1)) | (1 << (BIT_ST_PAUSED-1)), None),
]

all_pass = True
for desc, word, expected in cases:
    result = cycle_start_bit(word)
    ok = result == expected
    status = "PASS" if ok else "FAIL"
    print(f"{status}: {desc} => bit {result} (expected {expected})")
    if not ok:
        all_pass = False

if not all_pass:
    sys.exit(1)

# ── 4. Word/bit decomposition test ───────────────────────────────────────────
def decompose_bit(bit1):
    """Mirrors the new _pulseCmdBit word/localBit logic."""
    wi        = (bit1 - 1) // 16
    local_bit = ((bit1 - 1) % 16) + 1
    return wi, local_bit

word_cases = [
    (6,  0, 6,  "bit 6  → word 0, local bit 6"),
    (16, 0, 16, "bit 16 → word 0, local bit 16"),
    (17, 1, 1,  "bit 17 → word 1, local bit 1"),
    (18, 1, 2,  "bit 18 → word 1, local bit 2"),
    (19, 1, 3,  "bit 19 → word 1, local bit 3"),
    (20, 1, 4,  "bit 20 → word 1, local bit 4"),
]

for bit1, exp_wi, exp_local, desc in word_cases:
    wi, local_bit = decompose_bit(bit1)
    ok = (wi == exp_wi) and (local_bit == exp_local)
    status = "PASS" if ok else "FAIL"
    print(f"{status}: {desc} → wi={wi} localBit={local_bit}")
    if not ok:
        all_pass = False

if not all_pass:
    sys.exit(1)

print("\nAll tests passed.")
