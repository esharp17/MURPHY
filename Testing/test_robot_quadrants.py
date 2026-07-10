import re, sys

QML = r"c:\Users\evanr\Desktop\Murphy\ui_qml\RobotUI\screens\CellStatusScreen_4.qml"
src = open(QML, encoding="utf-8").read()

fails = []

# 1) Arm render model order: R1 top-right, R2 top-left, R3 bottom-left, R4 bottom-right
m = re.search(r"4 ROBOTS.*?model:\s*\[(.*?)\]", src, re.S)
entries = re.findall(r"\{\s*sx:\s*([+-]1),\s*sy:\s*([+-]1)", m.group(1))
expected = [("+1", "-1"), ("-1", "-1"), ("-1", "+1"), ("+1", "+1")]
if [tuple(e) for e in entries] != expected:
    fails.append(f"arm model order wrong: {entries}")

# 2) Panel loaders: which loader holds which robot, and its x/y anchoring
def panel_info(loader_id):
    blk = re.search(rf'Loader\s*\{{\s*id:\s*{loader_id}.*?^\}}', src, re.S | re.M).group(0)
    name = re.search(r'item\.name = "(.*?)"', blk).group(1)
    idx = int(re.search(r'item\.robotIndex = (\d)', blk).group(1))
    right = "ringArea.width -" in blk
    bottom = "ringArea.height -" in blk
    return name, idx, right, bottom

# corner -> (expected name, expected index, right?, bottom?)
checks = {
    "panelBL": ("Robot 1", 0, True, False),   # top-right
    "panelTL": ("Robot 2", 1, False, False),  # top-left
    "panelTR": ("Robot 3", 2, False, True),   # bottom-left
    "panelBR": ("Robot 4", 3, True, True),    # bottom-right
}
for lid, exp in checks.items():
    got = panel_info(lid)
    if got != exp:
        fails.append(f"{lid}: expected {exp}, got {got}")

# 3) c-stop + control content live inside robotPanel component (moves with panel)
panel_blk = src[src.index("id: robotPanel"):]
if "cStopActive" not in panel_blk.split("Loader {")[0]:
    fails.append("cStop content not inside robotPanel component")

if fails:
    print("FAIL:\n" + "\n".join(fails)); sys.exit(1)
print("PASS: Robot 1=top-right, 2=top-left, 3=bottom-left, 4=bottom-right; panels contain c-stop/controls; arm renders match.")
