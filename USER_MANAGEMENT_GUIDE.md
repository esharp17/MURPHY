# User Management System - Implementation Summary

## What Was Added

### Backend Files
1. **[robot_ui/user_manager.py](robot_ui/user_manager.py)** - Core user management logic
   - `load_users()` - Load users from JSON
   - `save_users()` - Persist users to JSON
   - `get_all_users()` - Get all users
   - `add_user()` - Create new user (hashes passcode)
   - `delete_user()` - Delete a user
   - `update_user()` - Modify user details (display, passcode, role)

2. **[robot_ui/user_service.py](robot_ui/user_service.py)** - QML interface
   - Exposes user management to QML via Qt Signals/Slots
   - Signals: `usersChanged`, `errorOccurred`, `successOccurred`
   - Methods: `getAllUsers()`, `getUserByUsername()`, `addUser()`, `deleteUser()`, `updateUser()`

### Frontend Changes
1. **[ui_qml/main.py](ui_qml/main.py)** - Main application
   - Added `UserService` instance
   - Exposed to QML as `UserService`

2. **[ui_qml/RobotUI/screens/SplashAdminScreen.qml](ui_qml/RobotUI/screens/SplashAdminScreen.qml)** - Admin UI
   - Added user dropdown to select existing users
   - Added fields for Display Name, Passcode (6 digits), and Role
   - Three action buttons:
     - **ADD NEW USER** - Creates new user with validation
     - **UPDATE USER** - Modifies selected user's details
     - **DELETE USER** - Removes selected user
   - Logout button for admin

## How to Use

### Admin Page Features

#### 1. Select/View User
- Use the "Select User" dropdown to choose an existing user
- User's current details are automatically loaded into the edit fields

#### 2. Add New User
1. Enter username in "Username" field (unique)
2. Enter display name in "Display Name" field
3. Select role from "Role" dropdown (Operator, Technician, Administrator)
4. Enter 6-digit passcode
5. Click **ADD NEW USER**
6. User list updates automatically

#### 3. Update User
1. Select user from dropdown
2. Modify Display Name, Passcode, and/or Role as needed
3. Click **UPDATE USER**
4. Changes are saved to users.json

#### 4. Delete User
1. Select user from dropdown
2. Click **DELETE USER**
3. User is removed from the system

### Security Features
- Passcodes are hashed with PBKDF2-HMAC-SHA256
- Each user gets a unique random salt
- 150,000 iterations for brute-force resistance
- Stored in [robot_ui/data/users.json](robot_ui/data/users.json)

## Role Mapping
- **Operator** = Role 1
- **Technician** = Role 2
- **Administrator** = Role 3 (has access to admin panel)

## File Structure
```
users.json format:
{
  "users": [
    {
      "username": "unique_id",
      "display": "Display Name",
      "role": "Operator|Technician|Administrator",
      "hash": "pbkdf2_hash",
      "salt": "random_salt",
      "pin": "000000"  // legacy field for compatibility
    }
  ]
}
```

## Validation
- Username: Required, must be unique
- Display Name: Required
- Passcode: Must be exactly 6 digits
- Role: One of three valid options

## Integration with Permissions
The role-based access control system now works with the user management:
- Admin role (3) can access Admin tab
- Technician role (2) can access Robot Comm, Cell Status, Welding
- Operator role (1) can access Cell Status, Welding
- None role (0) can only access Login tab
