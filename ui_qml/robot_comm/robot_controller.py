# ui_qml/robot_comm/robot_controller.py
from PySide6.QtCore import QObject, Signal, Slot

class RobotController(QObject):
    actionError = Signal(str)

    def __init__(self, bridge, state):
        super().__init__()
        self.bridge = bridge
        self.state = state

        # hook to YOUR signals
        self.bridge.ioUpdated.connect(self._on_io)
        self.bridge.stateChanged.connect(self._on_state)
        self.bridge.faulted.connect(self._on_fault)

        # optional: prime state for all robots at startup
        for i in range(4):
            self._refresh_all(i)

    @Slot(int)
    def _on_io(self, i: int):
        self._refresh_io(i)

    @Slot(int)
    def _on_state(self, i: int):
        self._refresh_state(i)

    @Slot(int, str)
    def _on_fault(self, i: int, msg: str):
        self.state.setFault(i, msg)

    def _refresh_io(self, i: int):
        ins_ = self.bridge.getInputs(i)     # <- YOUR getter
        outs = self.bridge.getOutputs(i)    # <- YOUR getter
        last = self.bridge.getLastRxMs(i)
        self.state.setIO(i, ins_, outs, last)

    def _refresh_state(self, i: int):
        st = self.bridge.getState(i)
        self.state.setState(i, st)

    def _refresh_all(self, i: int):
        self._refresh_state(i)
        self._refresh_io(i)
        self.state.setFault(i, self.bridge.getFault(i))

    # ---------------- actions QML can call ----------------
    @Slot(int)
    def connectRobot(self, i: int):
        self.bridge.connectRobot(i)

    @Slot(int)
    def disconnectRobot(self, i: int):
        self.bridge.disconnectRobot(i)

    @Slot(int, int, int)
    def setOutputWord(self, robot_i: int, word_i: int, value: int):
        # requires you to add setOutputWord() to the bridge (next section)
        if hasattr(self.bridge, "setOutputWord"):
            self.bridge.setOutputWord(robot_i, word_i, value)
        else:
            self.actionError.emit("Bridge missing setOutputWord()")
