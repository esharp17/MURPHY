# ui_qml/robot_comm/robot_state.py
from PySide6.QtCore import QObject, Signal, Slot

class RobotState(QObject):
    ioChanged    = Signal(int)  # robot index
    stateChanged = Signal(int)
    faultChanged = Signal(int)

    def __init__(self):
        super().__init__()
        self._state = [0]*4
        self._fault = [""]*4
        self._lastRxMs = [0]*4
        self._inputs = [[] for _ in range(4)]
        self._outputs = [[] for _ in range(4)]

    @Slot(int, "QVariantList", "QVariantList", int)
    def setIO(self, i, inputs, outputs, lastRxMs):
        i = int(i)
        self._inputs[i] = list(inputs)
        self._outputs[i] = list(outputs)
        self._lastRxMs[i] = int(lastRxMs)
        self.ioChanged.emit(i)

    @Slot(int, int)
    def setState(self, i, st):
        i = int(i)
        self._state[i] = int(st)
        self.stateChanged.emit(i)

    @Slot(int, str)
    def setFault(self, i, msg):
        i = int(i)
        self._fault[i] = str(msg)
        self.faultChanged.emit(i)

    # QML getters
    @Slot(int, result=int)
    def state(self, i): return int(self._state[int(i)])

    @Slot(int, result=str)
    def fault(self, i): return str(self._fault[int(i)])

    @Slot(int, result=int)
    def lastRxMs(self, i): return int(self._lastRxMs[int(i)])

    @Slot(int, result="QVariantList")
    def inputs(self, i): return self._inputs[int(i)]

    @Slot(int, result="QVariantList")
    def outputs(self, i): return self._outputs[int(i)]
