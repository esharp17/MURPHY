"""robot_ui.user_manager

User management service for loading, saving, adding, and deleting users.
"""

import json
from pathlib import Path
from typing import Optional, List, Dict, Any
from robot_ui.security import hash_passcode
from robot_ui.models import Role, User


class UserManager:
    """Manages user CRUD operations and JSON persistence."""
    
    def __init__(self, users_json_path: Path):
        self.users_json_path = users_json_path
        self.users: List[Dict[str, Any]] = []
        self.load_users()
    
    def load_users(self) -> bool:
        """Load users from JSON file."""
        try:
            if self.users_json_path.exists():
                with open(self.users_json_path, 'r') as f:
                    data = json.load(f)
                    self.users = data.get('users', [])
                return True
            return False
        except Exception as e:
            print(f"Error loading users: {e}")
            return False
    
    def save_users(self) -> bool:
        """Save users to JSON file."""
        try:
            with open(self.users_json_path, 'w') as f:
                json.dump({'users': self.users}, f, indent=2)
            return True
        except Exception as e:
            print(f"Error saving users: {e}")
            return False
    
    def get_all_users(self) -> List[Dict[str, Any]]:
        """Get all users."""
        return self.users
    
    def get_user_by_username(self, username: str) -> Optional[Dict[str, Any]]:
        """Get a user by username."""
        for user in self.users:
            if user.get('username') == username:
                return user
        return None
    
    def add_user(self, username: str, first_name: str, last_name: str, role: str, passcode_6: str) -> bool:
        """
        Add a new user.

        Args:
            username: Unique username (will be auto-generated from first and last name)
            first_name: User's first name
            last_name: User's last name
            role: "Operator", "Technician", or "Administrator"
            passcode_6: 6-digit numeric passcode

        Returns:
            True if successful, False otherwise
        """
        # Validate inputs - all fields required
        if not username or not first_name or not last_name or not role or not passcode_6:
            print("Invalid input: all fields required")
            return False

        if len(passcode_6) != 6 or not passcode_6.isdigit():
            print("Invalid passcode: must be 6 digits")
            return False

        if self.get_user_by_username(username):
            print(f"User '{username}' already exists")
            return False

        # Map role string to int
        role_int = self._map_role_to_int(role)
        if role_int is None:
            print(f"Invalid role: {role}")
            return False

        # Hash passcode
        hash_hex, salt_hex = hash_passcode(passcode_6)

        # Add user
        new_user = {
            'username': username,
            'firstName': first_name,
            'lastName': last_name,
            'role': role,
            'hash': hash_hex,
            'salt': salt_hex,
            'pin': passcode_6  # For compatibility with existing QML
        }

        self.users.append(new_user)
        return self.save_users()
    
    def delete_user(self, username: str) -> bool:
        """Delete a user by username."""
        user = self.get_user_by_username(username)
        if not user:
            print(f"User '{username}' not found")
            return False
        
        self.users.remove(user)
        return self.save_users()
    
    def update_user(self, username: str, first_name: Optional[str] = None,
                   last_name: Optional[str] = None, passcode_6: Optional[str] = None,
                   role: Optional[str] = None) -> bool:
        """
        Update a user's first name, last name, passcode, or role.

        Args:
            username: Username to update (cannot be changed)
            first_name: New first name (optional)
            last_name: New last name (optional)
            passcode_6: New 6-digit passcode (optional)
            role: New role (optional)

        Returns:
            True if successful, False otherwise
        """
        user = self.get_user_by_username(username)
        if not user:
            print(f"User '{username}' not found")
            return False

        # Update first name
        if first_name is not None:
            if not first_name:
                print("First name cannot be empty")
                return False
            user['firstName'] = first_name

        # Update last name
        if last_name is not None:
            if not last_name:
                print("Last name cannot be empty")
                return False
            user['lastName'] = last_name

        # Update passcode
        if passcode_6 is not None:
            if len(passcode_6) != 6 or not passcode_6.isdigit():
                print("Invalid passcode: must be 6 digits")
                return False
            hash_hex, salt_hex = hash_passcode(passcode_6)
            user['hash'] = hash_hex
            user['salt'] = salt_hex
            user['pin'] = passcode_6

        # Update role
        if role is not None:
            role_int = self._map_role_to_int(role)
            if role_int is None:
                print(f"Invalid role: {role}")
                return False
            user['role'] = role

        return self.save_users()
    
    @staticmethod
    def _map_role_to_int(role: str) -> Optional[int]:
        """Map role string to Role enum int."""
        role_map = {
            'Operator': Role.OPERATOR,
            'Technician': Role.TECHNICIAN,
            'Administrator': Role.ADMIN,
        }
        return role_map.get(role)
