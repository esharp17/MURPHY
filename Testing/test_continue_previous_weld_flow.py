"""
Regression test for the Welding tab "Continue Previous Weld" flow.

Verifies that continue skips the weld record screen, opens the scan workspace,
and treats Start Weld as unavailable because the weld is already in progress.
"""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
WELDING_QML = ROOT / "ui_qml" / "RobotUI" / "screens" / "WeldingScreen.qml"
MAIN_QML = ROOT / "ui_qml" / "RobotUI" / "Main.qml"


def require(text: str, snippet: str, description: str) -> bool:
    ok = snippet in text
    print(f"{'PASS' if ok else 'FAIL'}: {description}")
    return ok


def main() -> int:
    welding_src = WELDING_QML.read_text(encoding="utf-8")
    main_src = MAIN_QML.read_text(encoding="utf-8")

    checks = [
        require(welding_src, "property bool resumedWeldActive: false", "Welding screen tracks resumed weld state"),
        require(welding_src, "function showScanWorkspace()", "Welding screen has a shared scan workspace transition helper"),
        require(welding_src, "root.resumedWeldActive = true", "Continue Previous Weld enables resumed weld mode"),
        require(welding_src, "root.showWeldRecord = false", "Continue Previous Weld does not route to weld record view"),
        require(welding_src, "root.showScanWorkspace()", "Continue Previous Weld routes into the scan workspace"),
        require(welding_src, "visible: !root.showWeldRecord && !root.showScanView", "Pre-check action buttons are hidden while the scan workspace is visible"),
        require(welding_src, "property bool weldBlocked: root.resumedWeldActive || !root.weldReadyFromRobot || activeAlertsModel.count > 0", "Start Weld is blocked for resumed welds"),
        require(welding_src, 'text: root.resumedWeldActive ? "Weld In Progress" : "Start Weld"', "Start Weld label reflects an already-started weld"),
        require(main_src, "property bool weldResumedActive: false", "Main window persists resumed weld state"),
        require(main_src, "resumedWeldActive: win.weldResumedActive", "Main window passes resumed weld state into WeldingScreen"),
        require(main_src, "onResumedWeldActiveChanged: win.weldResumedActive = resumedWeldActive", "Main window stores resumed weld changes"),
    ]

    if all(checks):
        print("All tests passed.")
        return 0

    print("One or more tests FAILED.")
    return 1


if __name__ == "__main__":
    sys.exit(main())