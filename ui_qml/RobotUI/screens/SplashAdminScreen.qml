import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import RobotUI 1.0

Item {
    id: root
    anchors.fill: parent

    // app-level state
    property bool loggedIn: false
    property string loggedInUser: ""
    property string loggedInUserFirstName: ""
    property bool loggedInIsAdmin: false
    property int loggedInRole: 0  // Role enum: 0=NONE, 1=OPERATOR, 2=TECHNICIAN, 3=ADMIN

    // local UI state
    property string passcode: ""

    // keypad tuning knobs
    property int keyCols: 3
    property int keyW: 220
    property int keyH: 120
    property int keySpacing: Theme.gap
    property int padW: (keyW * keyCols) + (keySpacing * (keyCols - 1)) + (Theme.pad * 2)

    // login data (loaded from JSON)
    ListModel { id: usersModel }
    property int userIndex: 0
    property bool userChosen: false


    // passcode error UI (popup)
    property bool pinErrorVisible: false
    
    // user management UI
    property bool userManagementVisible: false
    ListModel { id: allUsersModel }

    function loadUsers() {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                usersModel.clear()

                if (xhr.status === 200 || xhr.status === 0) {
                    var obj = JSON.parse(xhr.responseText)
                    var arr = obj.users || []
                    for (var i = 0; i < arr.length; i++) {
                        usersModel.append(arr[i])   // expects username/display/role/pin fields
                    }
                    root.userIndex = 0
                    root.userChosen = (usersModel.count > 0)
                } else {
                    console.log("Failed to load users.json:", xhr.status)
                    root.userIndex = 0
                    root.userChosen = false
                }
            }
        }
        xhr.open("GET", Qt.resolvedUrl("../assets/users.json"))
        xhr.send()
    }

    Component.onCompleted: loadUsers()

    // Listen for user changes from UserService and reload
    Connections {
        target: UserService
        function onUsersChanged() {
            root.loadUsers()
        }
    }

    // derived
    readonly property string selectedUser: (usersModel.count > 0) ? (usersModel.get(userIndex).username || "") : ""
    readonly property string selectedFirstName: (usersModel.count > 0) ? (usersModel.get(userIndex).firstName || "") : ""
    readonly property string selectedLastName: (usersModel.count > 0) ? (usersModel.get(userIndex).lastName || "") : ""
    readonly property string selectedFullName: selectedFirstName + " " + selectedLastName
    readonly property string selectedRole: (usersModel.count > 0) ? (usersModel.get(userIndex).role || "") : ""
    readonly property string selectedPin: (usersModel.count > 0) ? (usersModel.get(userIndex).pin || "") : ""
    readonly property bool isAdminRole: selectedRole === "Administrator"

    // for Main.qml tab label swap
    property bool adminModeActive: loggedIn && loggedInIsAdmin

    Rectangle {
        anchors.fill: parent
        color: Theme.panel
        radius: Theme.radius

        Column {
            id: col
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: Theme.pad * 2
            spacing: Theme.gap * 2

            // ---- Logo (only shown when NOT in admin mode) ----
            Item {
                width: 600
                height: 380
                visible: !root.adminModeActive

                Image {
                    anchors.fill: parent
                    source: "../assets/images/pipecell.png"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }
            }

            // ---- User row (only shown when NOT in admin mode) ----
            Column {
                spacing: Theme.gap
                width: 600
                visible: !root.adminModeActive

                Text {
                    text: loggedIn
                          ? ("Logged in as: " + loggedInUser + " (" + selectedRole + ")")
                          : "Select user:"
                    color: Theme.text
                    font.pixelSize: Theme.fontMed
                }

                ComboBox {
                    id: userBox
                    width: parent.width
                    height: 64
                    enabled: !loggedIn

                    model: usersModel
                    textRole: "fullName"

                    // Add delegate to compute fullName from firstName and lastName
                    delegate: ItemDelegate {
                        width: userBox.width
                        text: model.firstName + " " + model.lastName
                        highlighted: userBox.highlightedIndex === index
                    }

                    displayText: (usersModel.count > 0 && currentIndex >= 0)
                                 ? (usersModel.get(currentIndex).firstName + " " + usersModel.get(currentIndex).lastName)
                                 : ""

                    currentIndex: root.userIndex

                    onCurrentIndexChanged: {
                        root.userIndex = (currentIndex >= 0 ? currentIndex : 0)
                        root.userChosen = (usersModel.count > 0)
                    }
                }
            }

            // ---- Login / Logout button (only shown when NOT in admin mode) ----
            Rectangle {
                width: 600
                height: 64
                radius: Theme.radius
                color: Theme.accent
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !root.adminModeActive

                Text {
                    anchors.centerIn: parent
                    text: loggedIn ? "LOG OUT" : "LOG IN"
                    color: Theme.panel
                    font.pixelSize: Theme.fontLg
                    font.bold: true
                }

                // ===========================
                // MAIN SCREEN BUTTON HANDLER
                // LOG IN / LOG OUT (opens popup for login)
                // ===========================
                MouseArea {
                    anchors.fill: parent
                    onPressed: {
                        // LOG OUT
                        if (root.loggedIn) {
                            root.loggedIn = false
                            root.loggedInUser = ""
                            root.loggedInUserFirstName = ""
                            root.loggedInIsAdmin = false
                            root.loggedInRole = 0
                            root.passcode = ""
                            return
                        }

                        // LOG IN requires user selection
                        if (!root.userChosen || usersModel.count === 0)
                            return

                        // all users require passcode -> open modal
                        root.pinErrorVisible = false
                        pinPopup.open()
                    }
                }
            }

            // ---- Admin Panel (only when admin logged in) ----
            Rectangle {
                id: adminPanel
                width: 900
                height: adminGrid.height + (Theme.pad * 2)
                visible: root.adminModeActive
                radius: Theme.radius
                color: "transparent"
                border.width: 0
                border.color: Theme.accent

                Grid {
                    id: adminGrid
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.pad
                    columns: 2
                    rows: 3
                    columnSpacing: Theme.gap
                    rowSpacing: Theme.gap

                        Rectangle {
                            width: (adminPanel.width - (Theme.pad * 2) - Theme.gap) / 2
                            height: 190
                            radius: Theme.radius
                            color: Theme.accent

                            Text {
                                anchors.centerIn: parent
                                text: "VIEW LOG FILES"
                                color: Theme.panel
                                font.pixelSize: Theme.fontMed
                                font.bold: true
                            }

                            MouseArea { anchors.fill: parent; onPressed: console.log("ADMIN: view logs") }
                        }

                        Rectangle {
                            width: (adminPanel.width - (Theme.pad * 2) - Theme.gap) / 2
                            height: 190
                            radius: Theme.radius
                            color: Theme.accent

                            Text {
                                anchors.centerIn: parent
                                text: "EXPORT LOGS"
                                color: Theme.panel
                                font.pixelSize: Theme.fontMed
                                font.bold: true
                            }

                            MouseArea { anchors.fill: parent; onPressed: console.log("ADMIN: export logs") }
                        }

                        Rectangle {
                            width: (adminPanel.width - (Theme.pad * 2) - Theme.gap) / 2
                            height: 190
                            radius: Theme.radius
                            color: Theme.accent

                            Text {
                                anchors.centerIn: parent
                                text: "SYSTEM INFO"
                                color: Theme.panel
                                font.pixelSize: Theme.fontMed
                                font.bold: true
                            }

                            MouseArea { anchors.fill: parent; onPressed: console.log("ADMIN: system info") }
                        }

                        Rectangle {
                            width: (adminPanel.width - (Theme.pad * 2) - Theme.gap) / 2
                            height: 190
                            radius: Theme.radius
                            color: Theme.accent

                            Text {
                                anchors.centerIn: parent
                                text: "RESTART UI"
                                color: Theme.panel
                                font.pixelSize: Theme.fontMed
                                font.bold: true
                            }

                            MouseArea { anchors.fill: parent; onPressed: console.log("ADMIN: restart ui") }
                        }

                        Rectangle {
                            width: (adminPanel.width - (Theme.pad * 2) - Theme.gap) / 2
                            height: 190
                            radius: Theme.radius
                            color: Theme.accent

                            Text {
                                anchors.centerIn: parent
                                text: "EDIT USERS"
                                color: Theme.panel
                                font.pixelSize: Theme.fontMed
                                font.bold: true
                            }

                            MouseArea { anchors.fill: parent; onPressed: root.userManagementVisible = true }
                        }

                        Rectangle {
                            width: (adminPanel.width - (Theme.pad * 2) - Theme.gap) / 2
                            height: 190
                            radius: Theme.radius
                            color: Qt.darker(Theme.panel, 1.1)
                            border.width: 2
                            border.color: "#2a3442"

                            Text {
                                anchors.centerIn: parent
                                text: "LOG OUT"
                                color: Theme.text
                                font.pixelSize: Theme.fontMed
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                onPressed: {
                                    root.loggedIn = false
                                    root.loggedInUser = ""
                                    root.loggedInUserFirstName = ""
                                    root.loggedInIsAdmin = false
                                    root.loggedInRole = 0
                                    root.passcode = ""
                                }
                            }
                        }
                    }
            }
        }
    }
    
    // ===== PASSCODE MODAL (all users) =====
    Popup {
        id: pinPopup
        modal: true
        focus: true
        width: parent.width
        height: parent.height
        closePolicy: Popup.NoAutoClose

        onOpened: {
            root.passcode = ""
            root.pinErrorVisible = false
        }

        background: Rectangle {
            color: "#000000"
            opacity: 0.65
        }

        contentItem: Item {
            anchors.fill: parent
            Rectangle {
                id: panel
                width: Math.min(root.padW, parent.width*.7 - (Theme.pad * 2))
                radius: Theme.radius
                color: Theme.panel
                border.width: 2
                border.color: Theme.accent

                anchors.horizontalCenter: parent.horizontalCenter
                y: ((parent.height - height) / 2)-325

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.pad
                    spacing: Theme.gap

                Text {
                    text: "Enter 6-digit passcode"
                    color: Theme.text
                    font.pixelSize: Theme.fontMed
                }

                // ===========================
                // PASSCODE INCORRECT TIMER (2s)
                // ===========================
                Timer {
                    id: pinErrorTimer
                    interval: 2000
                    repeat: false
                    onTriggered: {
                        root.pinErrorVisible = false
                        root.passcode = ""
                    }
                }

                // ===========================
                // PASSCODE DISPLAY + OVERLAY ERROR (NO LAYOUT SHIFT)
                // ===========================
                Item {
                    width: parent.width
                    height: 55

                    // passcode display
                    Rectangle {
                        id: passcodeBox
                        anchors.fill: parent
                        radius: Theme.radius
                        color: Theme.sideBtnpanel
                        border.width: 2
                        border.color: Theme.accent

                        Text {
                            anchors.centerIn: parent
                            text: root.passcode.length > 0
                                  ? "••••••".slice(0, root.passcode.length)
                                  : "------"
                            color: Theme.text
                            font.pixelSize: Theme.fontLg
                        }
                    }

                    // error overlay (appears on top, does NOT move layout)
                    Rectangle {
                        anchors.fill: parent
                        visible: root.pinErrorVisible
                        radius: Theme.radius
                        color: Theme.danger
                        opacity: 0.92
                        z: 10

                        Text {
                            anchors.centerIn: parent
                            text: "PASSCODE INCORRECT!"
                            color: Theme.sideBtnstopText   // or "black" if undefined
                            font.pixelSize: Theme.fontMed
                            font.bold: true
                        }
                    }
                }


                    Grid {
                        id: keypad
                        columns: root.keyCols
                        columnSpacing: root.keySpacing
                        rowSpacing: root.keySpacing
                        anchors.horizontalCenter: parent.horizontalCenter

                        Repeater {
                            model: ["1","2","3","4","5","6","7","8","9","CLR","0","DEL"]

                            delegate: Rectangle {
                                width: Math.min(
                                           root.keyW,
                                           (panel.width - (Theme.pad * 2) - (root.keySpacing * (root.keyCols - 1))) / root.keyCols
                                       )
                                height: root.keyH - 30
                                radius: Theme.radius
                                color: Theme.sideBtnBase
                                border.width: 2
                                border.color: "#2a3442"

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: Theme.sideBtnText
                                    font.pixelSize: 40
                                    font.bold: true
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onPressed: {
                                        if (modelData === "CLR") { root.passcode = ""; return }
                                        if (modelData === "DEL") {
                                            if (root.passcode.length > 0)
                                                root.passcode = root.passcode.slice(0, root.passcode.length - 1)
                                            return
                                        }
                                        if (root.passcode.length < 6)
                                            root.passcode = root.passcode + modelData
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 60
                        radius: Theme.radius
                        color: Theme.accent

                        Text {
                            anchors.centerIn: parent
                            text: "LOG IN"
                            color: Theme.panel
                            font.pixelSize: Theme.fontLg
                            font.bold: true
                        }

                        // ===========================
                        // POPUP LOG IN BUTTON HANDLER
                        // validates passcode, sets loggedIn state, shows 2s error banner
                        // ===========================
                        MouseArea {
                            anchors.fill: parent
                            onPressed: {
                                if (!root.userChosen || usersModel.count === 0)
                                    return
                                if (root.passcode.length !== 6)
                                    return

                                if (root.passcode !== root.selectedPin) {
                                    root.pinErrorVisible = true
                                    pinErrorTimer.restart()
                                    return
                                }

                                root.pinErrorVisible = false
                                root.loggedIn = true
                                root.loggedInUser = root.selectedFullName
                                root.loggedInUserFirstName = root.selectedFirstName
                                root.loggedInIsAdmin = root.isAdminRole
                                // Map role string to Role enum: "Operator"=1, "Technician"=2, "Administrator"=3
                                if (root.selectedRole === "Administrator") {
                                    root.loggedInRole = 3
                                } else if (root.selectedRole === "Technician") {
                                    root.loggedInRole = 2
                                } else {
                                    root.loggedInRole = 1  // default to Operator
                                }
                                root.passcode = ""
                                pinPopup.close()
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 64
                        radius: Theme.radius
                        color: Qt.darker(Theme.panel, 1.15)
                        border.width: 2
                        border.color: "#2a3442"

                        Text {
                            anchors.centerIn: parent
                            text: "CANCEL"
                            color: Theme.text
                            font.pixelSize: Theme.fontMed
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            onPressed: {
                                root.passcode = ""
                                root.pinErrorVisible = false
                                pinPopup.close()
                            }
                        }
                    }
                }
            }
        }
    }
    
    // ===== USER MANAGEMENT PAGE =====
    Rectangle {
        id: userManagementPanel
        anchors.fill: parent
        visible: root.userManagementVisible
        color: "#000000"
        opacity: 0.95
        z: 100
        
        Column {
            anchors.fill: parent
            anchors.margins: Theme.pad
            spacing: Theme.gap
            
            // Header
            Row {
                width: parent.width
                spacing: Theme.gap
                
                Rectangle {
                    width: parent.width - 200 - Theme.gap
                    height: 80
                    radius: Theme.radius
                    color: Theme.panel
                    border.width: 2
                    border.color: Theme.accent

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.pad
                        anchors.verticalCenter: parent.verticalCenter
                        text: "User Management"
                        color: Theme.text
                        font.pixelSize: Theme.fontLg
                        font.bold: true
                    }
                }

                Rectangle {
                    width: 200
                    height: 80
                    radius: Theme.radius
                    color: Theme.accent

                    Text {
                        anchors.centerIn: parent
                        text: "Close"
                        color: Theme.panel
                        font.pixelSize: Theme.fontMed
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        onPressed: root.userManagementVisible = false
                    }
                }
            }
            
            // Content Area with tabs/sections
            Rectangle {
                width: parent.width
                height: parent.parent.height - 80 - Theme.gap - (Theme.pad * 2)
                radius: Theme.radius
                color: Theme.panel
                border.width: 2
                border.color: Theme.accent
                
                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.pad
                    spacing: Theme.gap
                    
                    // View Users Section
                    Text {
                        text: "Manage Users"
                        color: Theme.text
                        font.pixelSize: Theme.fontMed
                        font.bold: true
                    }
                    
                    // User Selection and Quick Actions
                    Row {
                        width: parent.width
                        spacing: Theme.gap
                        
                        Column {
                            width: 450
                            spacing: 4
                            
                            Text {
                                text: "Select User"
                                color: Theme.text
                                font.pixelSize: Theme.fontSm
                            }
                            
                            ComboBox {
                                id: userComboBox
                                width: parent.width
                                height: 48
                                model: usersModel
                                textRole: "fullName"

                                delegate: ItemDelegate {
                                    width: userComboBox.width
                                    text: model.firstName + " " + model.lastName
                                }

                                displayText: (usersModel.count > 0 && currentIndex >= 0)
                                             ? (usersModel.get(currentIndex).firstName + " " + usersModel.get(currentIndex).lastName)
                                             : ""

                                onCurrentIndexChanged: {
                                    if (currentIndex >= 0 && usersModel.count > 0) {
                                        var user = usersModel.get(currentIndex)
                                        root.selectedEditUser = user.username || ""
                                        root.selectedEditFirstName = user.firstName || ""
                                        root.selectedEditLastName = user.lastName || ""
                                        root.selectedEditRole = user.role || "Operator"
                                        root.editPasscode = user.pin || ""
                                    }
                                }
                            }
                        }
                        
                        Column {
                            width: 200
                            spacing: 4

                            Text {
                                text: " "
                                color: Theme.text
                                font.pixelSize: Theme.body
                            }

                            Rectangle {
                                width: parent.width
                                height: 48
                                radius: Theme.radius
                                color: Theme.accent

                                Text {
                                    anchors.centerIn: parent
                                    text: "Edit Selected"
                                    color: Theme.panel
                                    font.pixelSize: Theme.body
                                    font.bold: true
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        if (userComboBox.currentIndex >= 0) {
                                            editDialogVisible = true
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Users List
                    Rectangle {
                        width: parent.width
                        height: 300
                        radius: Theme.radius
                        color: Qt.darker(Theme.panel, 1.05)
                        border.width: 1
                        border.color: "#2a3442"
                        
                        ListView {
                            anchors.fill: parent
                            anchors.margins: Theme.pad
                            model: usersModel
                            spacing: Theme.gap
                            clip: true
                            
                            delegate: Rectangle {
                                width: ListView.view.width
                                height: 72
                                radius: Theme.radius
                                color: Theme.sideBtnBase
                                border.width: 2
                                border.color: "#2a3442"

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.pad
                                    anchors.topMargin: Theme.pad
                                    anchors.bottomMargin: Theme.pad
                                    anchors.rightMargin: Theme.pad * 2
                                    spacing: Theme.gap

                                    Column {
                                        width: 200
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            text: "First Name"
                                            color: Theme.muted
                                            font.pixelSize: Theme.bodySm
                                        }

                                        Text {
                                            text: firstName || "Unknown"
                                            color: Theme.text
                                            font.pixelSize: Theme.body
                                        }
                                    }

                                    Column {
                                        width: 200
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            text: "Last Name"
                                            color: Theme.muted
                                            font.pixelSize: Theme.bodySm
                                        }

                                        Text {
                                            text: lastName || "Unknown"
                                            color: Theme.text
                                            font.pixelSize: Theme.body
                                        }
                                    }

                                    Column {
                                        width: parent.width - 540
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            text: "Role"
                                            color: Theme.muted
                                            font.pixelSize: Theme.bodySm
                                        }

                                        Text {
                                            text: role || "No Role"
                                            color: Theme.text
                                            font.pixelSize: Theme.body
                                        }
                                    }

                                    Rectangle {
                                        width: 100
                                        height: 40
                                        radius: Theme.radius
                                        color: Theme.accent
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            anchors.centerIn: parent
                                            text: "Edit"
                                            color: Theme.panel
                                            font.pixelSize: Theme.body
                                            font.bold: true
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                root.selectedEditUser = username || ""
                                                root.selectedEditFirstName = firstName || ""
                                                root.selectedEditLastName = lastName || ""
                                                root.selectedEditRole = role || "Operator"
                                                root.editPasscode = pin || ""
                                                editDialogVisible = true
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Add New User Section
                    Row {
                        width: parent.width
                        spacing: Theme.gap

                        Rectangle {
                            width: parent.width
                            height: 56
                            radius: Theme.radius
                            color: Theme.accent

                            Text {
                                anchors.centerIn: parent
                                text: "Add New User"
                                color: Theme.panel
                                font.pixelSize: Theme.body
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.selectedEditUser = ""
                                    root.selectedEditFirstName = ""
                                    root.selectedEditLastName = ""
                                    root.editPasscode = ""
                                    root.selectedEditRole = "Operator"
                                    editDialogVisible = true
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Edit User Dialog
    property string selectedEditUser: ""
    property string selectedEditFirstName: ""
    property string selectedEditLastName: ""
    property string editPasscode: ""
    property string selectedEditRole: "Operator"
    property bool editDialogVisible: false
    
    Popup {
        id: editUserPopup
        modal: true
        focus: true
        width: parent.width
        height: parent.height
        visible: editDialogVisible
        closePolicy: Popup.NoAutoClose
        
        background: Rectangle {
            color: "#000000"
            opacity: 0.65
        }
        
        contentItem: Item {
            anchors.fill: parent
            
            Rectangle {
                width: 600
                height: 580
                radius: Theme.radius
                color: Theme.panel
                border.width: 2
                border.color: Theme.accent

                anchors.centerIn: parent

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.pad
                    spacing: Theme.gap

                    Text {
                        text: selectedEditUser ? "Edit User" : "Add New User"
                        color: Theme.text
                        font.pixelSize: Theme.fontMed
                        font.bold: true
                    }

                    // First Name
                    Column {
                        width: parent.width
                        spacing: 4

                        Text {
                            text: "First Name *"
                            color: Theme.text
                            font.pixelSize: Theme.body
                        }

                        Rectangle {
                            width: parent.width
                            height: 48
                            color: Theme.sideBtnpanel
                            border.width: 2
                            border.color: Theme.accent
                            radius: Theme.radius

                            TextField {
                                id: firstNameField
                                anchors.fill: parent
                                anchors.margins: Theme.pad
                                text: root.selectedEditFirstName
                                onTextChanged: root.selectedEditFirstName = text
                                font.pixelSize: Theme.body
                                color: Theme.text
                                placeholderText: "Required"
                                background: Rectangle { color: "transparent" }
                            }
                        }
                    }

                    // Last Name
                    Column {
                        width: parent.width
                        spacing: 4

                        Text {
                            text: "Last Name *"
                            color: Theme.text
                            font.pixelSize: Theme.body
                        }

                        Rectangle {
                            width: parent.width
                            height: 48
                            color: Theme.sideBtnpanel
                            border.width: 2
                            border.color: Theme.accent
                            radius: Theme.radius

                            TextField {
                                id: lastNameField
                                anchors.fill: parent
                                anchors.margins: Theme.pad
                                text: root.selectedEditLastName
                                onTextChanged: root.selectedEditLastName = text
                                font.pixelSize: Theme.body
                                color: Theme.text
                                placeholderText: "Required"
                                background: Rectangle { color: "transparent" }
                            }
                        }
                    }

                    // Passcode
                    Column {
                        width: parent.width
                        spacing: 4

                        Text {
                            text: "Passcode (6 digits) *"
                            color: Theme.text
                            font.pixelSize: Theme.body
                        }

                        Rectangle {
                            width: parent.width
                            height: 48
                            color: Theme.sideBtnpanel
                            border.width: 2
                            border.color: Theme.accent
                            radius: Theme.radius

                            TextField {
                                id: passcodeField
                                anchors.fill: parent
                                anchors.margins: Theme.pad
                                text: root.editPasscode
                                inputMethodHints: Qt.ImhDigitsOnly
                                validator: RegularExpressionValidator { regularExpression: /^[0-9]{0,6}$/ }
                                onTextChanged: root.editPasscode = text
                                font.pixelSize: Theme.body
                                color: Theme.text
                                placeholderText: "Required"
                                background: Rectangle { color: "transparent" }
                            }
                        }
                    }

                    // Role
                    Column {
                        width: parent.width
                        spacing: 4

                        Text {
                            text: "Role *"
                            color: Theme.text
                            font.pixelSize: Theme.body
                        }

                        ComboBox {
                            width: parent.width
                            height: 48
                            model: ["Operator", "Technician", "Administrator"]
                            currentIndex: find(root.selectedEditRole)
                            onCurrentTextChanged: root.selectedEditRole = currentText
                            font.pixelSize: Theme.body
                        }
                    }

                    Item { width: 1; height: Theme.gap }  // spacer

                    // Buttons
                    Row {
                        width: parent.width
                        spacing: Theme.gap

                        Rectangle {
                            width: (parent.width - Theme.gap) / 2
                            height: 56
                            radius: Theme.radius
                            color: Theme.accent

                            Text {
                                anchors.centerIn: parent
                                text: "Save"
                                color: Theme.panel
                                font.pixelSize: Theme.body
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    // Validate all required fields
                                    if (root.selectedEditFirstName.length === 0 ||
                                        root.selectedEditLastName.length === 0 ||
                                        root.editPasscode.length !== 6) {
                                        console.log("Invalid input: All fields are required")
                                        return
                                    }

                                    if (root.selectedEditUser) {
                                        // Update existing user
                                        UserService.updateUser(root.selectedEditUser, root.selectedEditFirstName,
                                                              root.selectedEditLastName, root.editPasscode,
                                                              root.selectedEditRole)
                                    } else {
                                        // Add new user - generate username from first and last name
                                        var username = root.selectedEditFirstName + " " + root.selectedEditLastName
                                        UserService.addUser(username, root.selectedEditFirstName,
                                                           root.selectedEditLastName, root.selectedEditRole,
                                                           root.editPasscode)
                                    }

                                    editDialogVisible = false
                                }
                            }
                        }

                        Rectangle {
                            width: (parent.width - Theme.gap) / 2
                            height: 56
                            radius: Theme.radius
                            color: Qt.darker(Theme.panel, 1.15)
                            border.width: 2
                            border.color: "#2a3442"

                            Text {
                                anchors.centerIn: parent
                                text: "Cancel"
                                color: Theme.text
                                font.pixelSize: Theme.body
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    editDialogVisible = false
                                }
                            }
                        }
                    }

                    // Delete button (only if editing)
                    Rectangle {
                        width: parent.width
                        height: 56
                        radius: Theme.radius
                        color: "transparent"
                        border.width: 2
                        border.color: Theme.danger
                        visible: selectedEditUser.length > 0

                        Text {
                            anchors.centerIn: parent
                            text: "Delete User"
                            color: Theme.danger
                            font.pixelSize: Theme.body
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                UserService.deleteUser(root.selectedEditUser)
                                editDialogVisible = false
                            }
                        }
                    }
                }
            }
        }
    }
}
