"""robot_ui.user_service

QML-exposed user management service.
"""

from PySide6.QtCore import QObject, Signal, Slot
from pathlib import Path
from robot_ui.user_manager import UserManager
from robot_ui.config import USERS_JSON


class UserService(QObject):
    """Exposes user management operations to QML."""
    
    # Signals
    usersChanged = Signal()  # Emitted when user list changes
    errorOccurred = Signal(str)  # Emitted on error
    successOccurred = Signal(str)  # Emitted on success
    
    def __init__(self):
        super().__init__()
        self.manager = UserManager(USERS_JSON)
    
    @Slot(result=list)
    def getAllUsers(self) -> list:
        """Get list of all users as dicts with username, firstName, and lastName."""
        users = self.manager.get_all_users()
        # Return simplified list for QML combobox
        return [{'username': u['username'], 'firstName': u.get('firstName', ''),
                 'lastName': u.get('lastName', ''), 'role': u['role']}
                for u in users]
    
    @Slot(str, result=dict)
    def getUserByUsername(self, username: str) -> dict:
        """Get a user by username."""
        user = self.manager.get_user_by_username(username)
        if user:
            return {
                'username': user['username'],
                'firstName': user.get('firstName', ''),
                'lastName': user.get('lastName', ''),
                'role': user['role'],
                'pin': user.get('pin', '')
            }
        return {}
    
    @Slot(str, str, str, str, str)
    def addUser(self, username: str, first_name: str, last_name: str, role: str, passcode_6: str):
        """Add a new user."""
        if self.manager.add_user(username, first_name, last_name, role, passcode_6):
            self.successOccurred.emit(f"User '{username}' added successfully")
            self.usersChanged.emit()
        else:
            self.errorOccurred.emit(f"Failed to add user '{username}'")
    
    @Slot(str)
    def deleteUser(self, username: str):
        """Delete a user."""
        if self.manager.delete_user(username):
            self.successOccurred.emit(f"User '{username}' deleted successfully")
            self.usersChanged.emit()
        else:
            self.errorOccurred.emit(f"Failed to delete user '{username}'")
    
    @Slot(str, str, str, str, str)
    def updateUser(self, username: str, first_name: str, last_name: str, passcode_6: str, role: str):
        """Update a user's first name, last name, passcode, and/or role."""
        if self.manager.update_user(username, first_name=first_name, last_name=last_name,
                                    passcode_6=passcode_6, role=role):
            self.successOccurred.emit(f"User '{username}' updated successfully")
            self.usersChanged.emit()
        else:
            self.errorOccurred.emit(f"Failed to update user '{username}'")
