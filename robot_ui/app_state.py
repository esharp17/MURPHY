from dataclasses import dataclass
from datetime import datetime
from typing import Optional
from robot_ui.models import User, Role


@dataclass
class AppState:
    active_tab: str = "Splash"
    user: Optional[User] = None
    login_time: Optional[str] = None
    selected_robot: int = 1  # 1..4
    welding_step: int = 0

    def role(self) -> Role:
        if self.user is None:
            return Role.NONE
        return self.user.role

    def set_user(self, user: Optional[User]):
        self.user = user
        if user is None:
            self.login_time = None
        else:
            self.login_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
