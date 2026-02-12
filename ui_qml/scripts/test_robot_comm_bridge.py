import sys
from PySide6.QtCore import QCoreApplication, QTimer

from robot_comm.robot_comm_bridge import RobotCommBridge


def main():
    app = QCoreApplication(sys.argv)
    bridge = RobotCommBridge()

    def on_io_updated(i):
        print(f"[ioUpdated] robot={i} outputs[0:4]={bridge.getOutputs(i)[:4]}")

    def on_in_words_changed():
        print(f"[inWordsChanged] in_words[0:4]={bridge.get_in_words()[:4]}")

    bridge.ioUpdated.connect(on_io_updated)
    bridge.inWordsChanged.connect(on_in_words_changed)

    print("Initial config:", bridge.getConfig(0))
    print("Initial state:", bridge.getState(0))

    bridge.setConfig(0, "127.0.0.1", 44818, 3, 16, 16)
    print("Updated config:", bridge.getConfig(0))

    bridge.setOutputWord(0, 0, 0x1234)
    bridge.setOutputWordAll(1, 0x00FF)
    print("Outputs[0] after set:", bridge.getOutputs(0)[:4])

    bridge._update_in_words([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16])

    QTimer.singleShot(500, app.quit)
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
