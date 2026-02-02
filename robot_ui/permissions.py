"""robot_ui.permissions

Role-based page access control.
"""

from robot_ui.models import Role


PAGE_PERMISSIONS = {
    "Login": [Role.NONE, Role.OPERATOR, Role.TECHNICIAN, Role.ADMIN],
    "Admin": [Role.ADMIN],
    "Robot Comm": [Role.TECHNICIAN, Role.ADMIN, Role.OPERATOR],
    "Cell Status": [Role.NONE, Role.OPERATOR, Role.TECHNICIAN, Role.ADMIN],
    "Welding": [Role.NONE,Role.OPERATOR, Role.TECHNICIAN, Role.ADMIN],
}

PAGE_NAMES = ["Login", "Robot Comm", "Cell Status", "Welding"]


def can_access_page(page_name: str, role: Role) -> bool:
    """Check if a role can access a page."""
    return role in PAGE_PERMISSIONS.get(page_name, [])


def can_access_page_by_index(page_index: int, role: Role) -> bool:
    """Check if a role can access a page by index."""
    if 0 <= page_index < len(PAGE_NAMES):
        page_name = PAGE_NAMES[page_index]
        return can_access_page(page_name, role)
    return False

