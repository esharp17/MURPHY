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

    // local UI state
    property string passcode: ""

    // keypad tuning knobs
    property int keyCols: 3
    property int keyW: 220
    property int keyH: 120
    property int keySpacing: Theme.gap
    property int padW: (keyW * keyCols) + (keySpacing * (keyCols - 1)) + (Theme.pad * 2)

    // admin editor UI (in-memory only for now)
    property string editUserName: ""
    property string editPasscode: ""
    property bool showPasscode: false

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

            // ---- Logo ----
            Item {
                width: 832
                height: 526
                visible: !root.adminModeActive

                Image {
                    anchors.fill: parent
                    source: "../assets/images/pipecell.png"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }
            }

            // ---- User row ----
            Column {
                spacing: Theme.gap
                width: 900

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
            

            // ---- Login / Logout button ----
            Rectangle {
                width: 900
                height: 84
                radius: Theme.radius
                color: Theme.accent
                anchors.horizontalCenter: parent.horizontalCenter

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
}
            // ---- Admin Panel (only when admin logged in) ----
            Rectangle {
                id: adminPanel
                anchors.fill: parent
                visible: root.adminModeActive

                height: visible ? 640 : 0
                radius: Theme.radius
                color: Theme.sideBtnpanel
                border.width: 2
                border.color: Theme.accent

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.pad
                    spacing: Theme.gap

                    Text {
                        text: "Admin"
                        color: Theme.text
                        font.pixelSize: Theme.fontLg
                        font.bold: true
                    }

                    Rectangle {
                        width: parent.width
                        height: 220
                        radius: Theme.radius
                        color: Qt.darker(Theme.panel, 1.05)
                        border.width: 2
                        border.color: "#2a3442"

                        Column {
                            anchors.fill: parent
                            anchors.margins: Theme.pad
                            spacing: Theme.gap

                            Text {
                                text: "User + Passcode Editor"
                                color: Theme.text
                                font.pixelSize: Theme.fontMed
                                font.bold: true
                            }

                            Row {
                                spacing: Theme.gap
                                width: parent.width

                                Column {
                                    spacing: 6
                                    width: (parent.width - Theme.gap) * 0.60

                                    Text { text: "Username"; color: Theme.text; font.pixelSize: Theme.fontMed }

                                    TextField {
                                        width: parent.width
                                        height: 64
                                        text: root.editUserName
                                        onTextChanged: root.editUserName = text
                                        font.pixelSize: Theme.fontMed
                                        placeholderText: "e.g. operator1"
                                    }
                                }

                                Column {
                                    spacing: 6
                                    width: (parent.width - Theme.gap) * 0.40

                                    Text { text: "Passcode (6)"; color: Theme.text; font.pixelSize: Theme.fontMed }

                                    TextField {
                                        width: parent.width
                                        height: 64
                                        text: root.editPasscode
                                        echoMode: root.showPasscode ? TextInput.Normal : TextInput.Password
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        validator: RegularExpressionValidator { regularExpression: /^[0-9]{0,6}$/ }
                                        onTextChanged: root.editPasscode = text
                                        font.pixelSize: Theme.fontMed
                                        placeholderText: "000000"
                                    }
                                }
                            }

                            Row {
                                spacing: Theme.gap
                                width: parent.width

                                CheckBox {
                                    checked: root.showPasscode
                                    text: "Show passcode"
                                    onCheckedChanged: root.showPasscode = checked
                                }
                            }
                        }
                    }

                    Text {
                        text: "Actions"
                        color: Theme.text
                        font.pixelSize: Theme.fontMed
                        font.bold: true
                    }

                    Grid {
                        columns: 2
                        columnSpacing: Theme.gap
                        rowSpacing: Theme.gap
                        width: parent.width

                        Rectangle {
                            width: (parent.width - Theme.gap) / 2
                            height: 96
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
                            width: (parent.width - Theme.gap) / 2
                            height: 96
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
                            width: (parent.width - Theme.gap) / 2
                            height: 96
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
                            width: (parent.width - Theme.gap) / 2
                            height: 96
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
                    }

                    Row {
                        spacing: Theme.gap
                        width: parent.width

                        Rectangle {
                            width: (parent.width - Theme.gap) / 2
                            height: 84
                            radius: Theme.radius
                            color: Qt.darker(Theme.accent, 1.1)

                            Text {
                                anchors.centerIn: parent
                                text: "SAVE USER/PASSCODE"
                                color: Theme.panel
                                font.pixelSize: Theme.fontMed
                                font.bold: true
                            }

                            MouseArea { anchors.fill: parent; onPressed: console.log("ADMIN: save user/pass", root.editUserName, root.editPasscode) }
                        }

                        Rectangle {
                            width: (parent.width - Theme.gap) / 2
                            height: 84
                            radius: Theme.radius
                            color: Qt.darker(Theme.panel, 1.1)
                            border.width: 2
                            border.color: "#2a3442"

                            Text {
                                anchors.centerIn: parent
                                text: "Log Out"
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
                width: Math.min(root.padW, parent.width - (Theme.pad * 2))
                radius: Theme.radius
                color: Theme.panel
                border.width: 2
                border.color: Theme.accent

                anchors.horizontalCenter: parent.horizontalCenter
                y: ((parent.height - height) / 2) - 420

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
                    height: 72

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
                                height: root.keyH
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
                        height: 84
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
