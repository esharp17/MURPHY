from dataclasses import dataclass
from enum import IntEnum
from typing import Optional, Dict, List

class Role(IntEnum):
    NONE = 0
    OPERATOR = 1
    TECHNICIAN = 2
    ADMIN = 3

@dataclass(frozen=True)
class User:
    username: str
    role: Role

@dataclass
class Alarm:
    robot_id: int
    code: str
    description: str
    active: bool = True
    raised_ts: Optional[str] = None

@dataclass
class RobotIO:
    robot_id: int
    connected: bool
    inputs: List[bool]   # len 64
    outputs: List[bool]  # len 64
    alarms: List[Alarm]
