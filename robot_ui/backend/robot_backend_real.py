import random
from typing import Dict
from robot_ui.models import RobotIO, Alarm

class MockRobotBackend:
    """
    Placeholder backend so UI is testable before real comms exist.
    Replace this later with your real robot comm code.
    """
    def __init__(self):
        self._state: Dict[int, RobotIO] = {}
        for rid in range(1, 5):
            self._state[rid] = RobotIO(
                robot_id=rid,
                connected=True,
                inputs=[False] * 64,
                outputs=[False] * 64,
                alarms=[]
            )

    def tick(self):
        # random IO jitter + occasional alarm
        for rid, s in self._state.items():
            if random.random() < 0.02:
                s.connected = not s.connected
            for _ in range(2):
                idx = random.randint(0, 63)
                s.inputs[idx] = not s.inputs[idx]
            for _ in range(2):
                idx = random.randint(0, 63)
                s.outputs[idx] = not s.outputs[idx]

            if random.random() < 0.01:
                s.alarms.append(Alarm(robot_id=rid, code="A123", description="Mock alarm", active=True))

            # clear old alarms sometimes
            if s.alarms and random.random() < 0.05:
                s.alarms.pop(0)

    def get_robot_io(self, robot_id: int) -> RobotIO:
        return self._state[robot_id]
    
