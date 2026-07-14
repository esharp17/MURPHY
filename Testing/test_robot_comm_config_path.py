import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT / "ui_qml") not in sys.path:
    sys.path.insert(0, str(ROOT / "ui_qml"))
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from robot_comm.robot_comm_bridge import RobotCommBridge


def test_uses_project_root_robot_comm_config_when_cwd_is_ui_qml():
    original_cwd = os.getcwd()
    os.chdir(ROOT / "ui_qml")
    try:
        bridge = RobotCommBridge()
    finally:
        os.chdir(original_cwd)

    assert bridge._cfg_path == str(ROOT / "robot_comm_config.json")
    assert bridge._cfgs[0].in_words == 20
    assert bridge._cfgs[0].out_words == 20
