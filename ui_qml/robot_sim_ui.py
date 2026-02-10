"""
robot_sim_ui.py - Simple GUI to simulate robot input bits for HMI testing.

Usage:
  1) Set HMI robot IP to 127.0.0.1 (Robot Comm screen -> CONFIG)
  2) Run: python robot_sim_ui.py
  3) Run HMI: python main.py

This UI starts the RobotSim server and lets you toggle input bits.
"""
import sys
from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QApplication,
    QWidget,
    QVBoxLayout,
    QHBoxLayout,
    QLabel,
    QComboBox,
    QCheckBox,
    QGroupBox,
    QLineEdit,
    QPushButton,
    QMessageBox,
)

from robot_sim import RobotSim


BIT_DEFS = [
    (1, "IMSTP_FB"),
    (2, "ENABLED_FB"),
    (3, "RUNNING"),
    (4, "PAUSED"),
    (5, "RESET_FB"),
    (6, "FAULT"),
    (7, "ALARM"),
    (8, "TPEN"),
    (9, "REMOTE"),
    (10, "AUTO_FB"),
    (11, "MANUAL_FB"),
]


class RobotSimWindow(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Robot Sim UI")
        self.setMinimumWidth(420)

        self.sim = RobotSim(num_robots=1)
        try:
            self.sim.start()
        except OSError as e:
            QMessageBox.critical(self, "RobotSim Error", f"Failed to start simulator:\n{e}")
            raise

        layout = QVBoxLayout(self)

        header = QLabel("Robot Simulator (ROBOT → HMI Inputs)")
        header.setStyleSheet("font-weight: bold; font-size: 16px;")
        layout.addWidget(header)

        row = QHBoxLayout()
        row.addWidget(QLabel("Robot:"))
        self.robot_select = QComboBox()
        self.robot_select.addItems(["Robot 1"])
        row.addWidget(self.robot_select)
        row.addStretch(1)
        layout.addLayout(row)

        bits_group = QGroupBox("Input Bits (Word 0)")
        bits_layout = QVBoxLayout(bits_group)

        self.bit_checks = {}
        for bit, name in BIT_DEFS:
            cb = QCheckBox(f"Bit {bit}: {name}")
            cb.stateChanged.connect(self._on_bit_changed)
            bits_layout.addWidget(cb)
            self.bit_checks[bit] = cb

        layout.addWidget(bits_group)

        word_row = QHBoxLayout()
        word_row.addWidget(QLabel("Set Word 0 (hex):"))
        self.word_edit = QLineEdit("0x0000")
        self.word_edit.setPlaceholderText("0x0000")
        word_row.addWidget(self.word_edit)
        apply_btn = QPushButton("Apply")
        apply_btn.clicked.connect(self._apply_word)
        word_row.addWidget(apply_btn)
        layout.addLayout(word_row)

        hint = QLabel("Tip: Start HMI after this. Configure robot IP to 127.0.0.1.")
        hint.setStyleSheet("color: #666;")
        layout.addWidget(hint)

    def _robot_index(self):
        return self.robot_select.currentIndex()

    def _on_bit_changed(self, _state):
        robot_i = self._robot_index()
        for bit, cb in self.bit_checks.items():
            self.sim.set_bit(robot_i, 0, bit, cb.isChecked())

    def _apply_word(self):
        text = self.word_edit.text().strip()
        try:
            value = int(text, 0)
        except ValueError:
            QMessageBox.warning(self, "Invalid Value", "Enter a hex or decimal value (e.g. 0x0024)")
            return
        robot_i = self._robot_index()
        self.sim.set_word(robot_i, 0, value)
        for bit, cb in self.bit_checks.items():
            mask = 1 << (bit - 1)
            cb.blockSignals(True)
            cb.setChecked(bool(value & mask))
            cb.blockSignals(False)

    def closeEvent(self, event):
        try:
            self.sim.stop()
        finally:
            event.accept()


def main():
    app = QApplication(sys.argv)
    win = RobotSimWindow()
    win.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
