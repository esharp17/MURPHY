import sys
from pathlib import Path

from PySide6.QtCore import QUrl
from PySide6.QtWidgets import QApplication
from PySide6.QtQml import QQmlApplicationEngine


def main() -> int:
    app = QApplication(sys.argv)

    base_dir = Path(__file__).resolve().parent  # ...\ui_qml
    qml_file = base_dir / "ui_qml" / "RobotUI" / "screens" / "test.qml"

    if not qml_file.exists():
        print(f"QML NOT FOUND: {qml_file}")
        return 2

    engine = QQmlApplicationEngine()

    # Allow `import QtQuick.Controls 2.15` and local imports if needed
    engine.addImportPath(str(base_dir / "RobotUI"))

    url = QUrl.fromLocalFile(str(qml_file))
    print("LOADING:", url.toString())

    engine.load(url)

    if not engine.rootObjects():
        print("QML LOAD FAILED (no rootObjects). Check console for QML errors.")
        return 3

    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
