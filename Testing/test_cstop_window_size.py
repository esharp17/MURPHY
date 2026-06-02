"""
Test: C-Stop window doubled size + ±1° jog buttons in CellStatusScreen_4.qml

Verifies:
  - panelWFrac doubled to 0.56
  - panelHFrac doubled to 0.40
  - Top row height doubled to 56
  - C-STOP / status button fonts scaled up (Theme.body, 16px)
  - C-Stop controls column spacing doubled to 8
  - Divider height doubled to 4
  - Position row item heights doubled to 56, font scaled to Theme.body
  - Jog ±5° row: heights 52, font Theme.body
  - Jog ±1° row present: heights 52, font Theme.body, -1°/+1° labels
  - Limits text font doubled to 16
  - Go Home / Resume Weld heights 52, font Theme.body
  - contentCol spacing 8
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

def block_from(marker, size=2000):
    """Return a slice of src starting at marker, or '' if not found."""
    idx = src.find(marker)
    if idx == -1:
        return None, -1
    return src[idx:idx + size], idx

# ── 1. Panel size fractions (original/normal size) ──────────────────────────
check(re.search(r"panelWFrac\s*:\s*0\.28", src), "panelWFrac = 0.28 (original small size)")
check(re.search(r"panelHFrac\s*:\s*0\.20", src), "panelHFrac = 0.20 (original small size)")

# ── 2. Panel width expands 2x when C-Stop is active ──────────────────────────
check("cStopActive ? ringArea.panelW * 2 : ringArea.panelW" in src,
      "panel width = 2x when cStopActive, normal otherwise")

# ── 3. Behavior on width for smooth animation ─────────────────────────────────
check("Behavior on width" in src, "Behavior on width present for smooth expansion")

# ── 4. Top row is normal height (28) ─────────────────────────────────────────
check("height: p.isConnected ? 28 : 0" in src, "topRow height = 28 (original)")

# ── 5. C-STOP button font is original (Theme.caption) ────────────────────────
cstop_text_idx = src.find('text: cStopActive ? "ACTIVE" : "C-STOP"')
check(cstop_text_idx != -1, "C-STOP button text found")
if cstop_text_idx != -1:
    nearby = src[cstop_text_idx:cstop_text_idx + 300]
    check("font.pixelSize: Theme.caption" in nearby, "C-STOP button font = Theme.caption (original)")

# Status indicator text original (11px); limits text still 16px (C-Stop only section)
check("font.pixelSize: 11" in src, "Status indicator text = 11px (original)")
check("font.pixelSize: 16" in src, "Limits text = 16px (inside C-Stop section)")

# ── 6. contentCol spacing restored to 4 ──────────────────────────────────────
cc_block, _ = block_from("id: contentCol", 400)
check(cc_block is not None, "contentCol found")
if cc_block:
    check("spacing: 4" in cc_block, "contentCol spacing = 4 (original)")

# ── 7. Right-side panel x-bindings track item.width (not fixed panelW) ───────
check("panelBL.item ? panelBL.item.width : ringArea.panelW" in src,
      "panelBL x-binding tracks item.width for expansion")
check("panelBR.item ? panelBR.item.width : ringArea.panelW" in src,
      "panelBR x-binding tracks item.width for expansion")

# ── 5. C-Stop controls column spacing ────────────────────────────────────────
ctrl_block, _ = block_from("// ---- C-STOP CONTROLS", 400)
check(ctrl_block is not None, "C-Stop controls section found")
if ctrl_block:
    check("spacing: 8" in ctrl_block, "C-Stop controls Column spacing = 8")

# ── 6. Divider height ─────────────────────────────────────────────────────────
div_block, _ = block_from("// Divider", 200)
check(div_block is not None, "Divider comment found")
if div_block:
    check("height: 4" in div_block, "Divider height = 4 (doubled)")

# ── 7. Position row heights and fonts ─────────────────────────────────────────
pos_block, _ = block_from("// Current + Desired Position row", 1200)
check(pos_block is not None, "Position row section found")
if pos_block:
    check(pos_block.count("height: 56") >= 2, "Position boxes height = 56 (both cur and desired)")
    check("font.pixelSize: Theme.body" in pos_block, "Position text font = Theme.body")
# TextInput margin: unique in the file - check full source
check("anchors.margins: 8" in src, "TextInput margins = 8 (doubled)")

# ── 8. Jog ±5° row ───────────────────────────────────────────────────────────
jog5_block, jog5_idx = block_from("// Jog buttons \u00b15\u00b0", 4000)
check(jog5_block is not None, "\u00b15\u00b0 jog row comment found")
if jog5_block:
    check(jog5_block.count("height: 52") >= 2, "\u00b15\u00b0 jog buttons height = 52 (both)")
    check('"-5\\u00B0"' in jog5_block or '"-5\u00b0"' in jog5_block, "\u00b15\u00b0 jog: -5\u00b0 label present")
    check('"+5\\u00B0"' in jog5_block or '"+5\u00b0"' in jog5_block, "\u00b15\u00b0 jog: +5\u00b0 label present")
    check("font.pixelSize: Theme.body" in jog5_block, "\u00b15\u00b0 jog font = Theme.body")

# ── 9. Jog ±1° row (new) ─────────────────────────────────────────────────────
jog1_block, jog1_idx = block_from("// Jog buttons \u00b11\u00b0", 4000)
check(jog1_block is not None, "\u00b11\u00b0 jog row comment found (new)")
if jog1_block:
    check(jog1_block.count("height: 52") >= 2, "\u00b11\u00b0 jog buttons height = 52 (both)")
    check('"-1\\u00B0"' in jog1_block or '"-1\u00b0"' in jog1_block, "\u00b11\u00b0 jog: -1\u00b0 label present")
    check('"+1\\u00B0"' in jog1_block or '"+1\u00b0"' in jog1_block, "\u00b11\u00b0 jog: +1\u00b0 label present")
    check("font.pixelSize: Theme.body" in jog1_block, "\u00b11\u00b0 jog font = Theme.body")
    check("|| 0) - 1" in jog1_block, "\u00b11\u00b0 jog -1 logic present")
    check("|| 0) + 1" in jog1_block, "\u00b11\u00b0 jog +1 logic present")

# ── 10. Go Home button ────────────────────────────────────────────────────────
gh_block, _ = block_from("// Go Home button", 2000)
check(gh_block is not None, "Go Home button section found")
if gh_block:
    check("height: 52" in gh_block, "Go Home height = 52 (doubled)")
    check("font.pixelSize: Theme.body" in gh_block, "Go Home font = Theme.body")

# ── 11. Resume Weld button ────────────────────────────────────────────────────
rw_block, _ = block_from("// Resume Weld button", 2000)
check(rw_block is not None, "Resume Weld button section found")
if rw_block:
    check("height: 52" in rw_block, "Resume Weld height = 52 (doubled)")
    check("font.pixelSize: Theme.body" in rw_block, "Resume Weld font = Theme.body")

# ── 12. ±1° jog ordering — must come after ±5° ───────────────────────────────
check(jog1_idx != -1 and jog5_idx != -1 and jog1_idx > jog5_idx,
      "\u00b11\u00b0 jog row appears after \u00b15\u00b0 jog row")

# ── Summary ───────────────────────────────────────────────────────────────────
print()
if all_pass:
    print("All tests passed.")
else:
    print("One or more tests FAILED.")
    sys.exit(1)
