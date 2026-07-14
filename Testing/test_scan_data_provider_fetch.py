import sys
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
if str(ROOT / "ui_qml") not in sys.path:
    sys.path.insert(0, str(ROOT / "ui_qml"))

from ui_qml.robot_ui.scan_data_provider import ScanDataProvider


def test_refresh_from_robot_fetches_and_loads_xml():
    with TemporaryDirectory() as tmpdir:
        tmp = Path(tmpdir)
        (tmp / "base_points.xml").write_text(
            '<?xml version="1.0"?><root><row pos="1" x="0" y="0" z="0"/></root>',
            encoding="utf-8",
        )
        (tmp / "offsets.xml").write_text(
            '<row pos="1" x="1" y="2" z="3" g="0.5" h="0.1" s="1"/>',
            encoding="utf-8",
        )
        (tmp / "offsets_norm.xml").write_text(
            '<?xml version="1.0"?><offset_log><row pos="1" x="1" y="2" z="3" g="0.5" h="0.1" s="1"/></offset_log>',
            encoding="utf-8",
        )

        provider = ScanDataProvider()
        provider._base_dir = str(tmp)

        with patch("robot_ui.scan_data_provider.fetch_offsets_xml_from_robot", return_value=str(tmp / "offsets.xml")), patch(
            "robot_ui.scan_data_provider.normalize_offsets_xml", return_value=str(tmp / "offsets_norm.xml")
        ):
            ok = provider.refreshFromRobot()

        assert ok is True
        assert provider.isLoaded() is True
        assert provider.pointCount() == 1
