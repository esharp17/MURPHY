import QtQuick 2.15
import QtQuick.Controls 2.15
import RobotUI 1.0

Item {
    id: root
    anchors.fill: parent

    // app-level state
    property bool loggedIn: false
    property string loggedInUser: ""
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

    // derived
    readonly property string selectedUser: (usersModel.count > 0) ? (usersModel.get(userIndex).username || "") : ""
    readonly property string selectedDisplay: (usersModel.count > 0) ? (usersModel.get(userIndex).display || "") : ""
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
                    textRole: "display"

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
                width: 1200
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

                            MouseArea { anchors.fill: parent; onPressed: console.log("ADMIN: edit users") }
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
                                root.loggedInUser = root.selectedDisplay
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
}
