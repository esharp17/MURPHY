import QtQuick 2.15
import QtQuick.Controls 2.15
import RobotUI 1.0

Rectangle {
    id: root
    anchors.fill: parent
    color: Theme.panel
    radius: Theme.radius

    // Properties to receive from parent
    property string loggedInUserFirstName: ""
    property string loggedInUserLastName: ""
    property bool preCheckConfirmed: false
    property bool showWeldRecord: false

    // Weld Record Data fields
    property string weldId: ""
    property string weldProject: ""
    property string weldClient: ""
    property string weldComments: ""
    property string weldUpstreamHeat: ""
    property string weldDownstreamHeat: ""
    property string saveErrorMessage: ""
    property string saveSuccessMessage: ""
    property bool showScanView: false
    property bool scanLoading: false
    property string scanPlotImage: ""
    property real scanAzim: 140
    property real scanElev: 20
    property real scanZoom: 1.0
    property real scanDragStartX: 0
    property real scanDragStartAzim: 0
    property bool scanRendering: false

    // Get current date formatted as "Month Day, Year"
    function getCurrentDate() {
        var date = new Date()
        var months = ["January", "February", "March", "April", "May", "June",
                      "July", "August", "September", "October", "November", "December"]
        return months[date.getMonth()] + " " + date.getDate() + ", " + date.getFullYear()
    }

    // =========================================================
    // PRE-CHECK VIEW
    // =========================================================
    Column {
        id: preCheckView
        anchors.fill: parent
        anchors.margins: Theme.pad
        spacing: Theme.gap
        visible: !root.showWeldRecord

        // Top Info Bar
        Row {
            width: parent.width
            height: 60
            spacing: Theme.gap

            // Running WSM Cell
            Rectangle {
                width: (parent.width - (Theme.gap * 3)) / 4
                height: parent.height
                radius: Theme.radius
                color: Theme.sideBtnBase
                border.width: 2
                border.color: Theme.accent

                Column {
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Running WSM"
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.bodySm
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: ""
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.body
                        font.bold: true
                    }
                }
            }

            // Cell # Cell
            Rectangle {
                width: (parent.width - (Theme.gap * 3)) / 4
                height: parent.height
                radius: Theme.radius
                color: Theme.sideBtnBase
                border.width: 2
                border.color: Theme.accent

                Column {
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Cell #:"
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.bodySm
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: ""
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.body
                        font.bold: true
                    }
                }
            }

            // Temperature Cell
            Rectangle {
                width: (parent.width - (Theme.gap * 3)) / 4
                height: parent.height
                radius: Theme.radius
                color: Theme.sideBtnBase
                border.width: 2
                border.color: Theme.accent

                Column {
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Temperature: "
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.bodySm
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "X°F" +"X°C"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.body
                        font.bold: true
                    }
                }
            }

            // Date Cell
            Rectangle {
                width: (parent.width - (Theme.gap * 3)) / 4
                height: parent.height
                radius: Theme.radius
                color: Theme.sideBtnBase
                border.width: 2
                border.color: Theme.accent

                Column {
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Date: "
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.bodySm
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.getCurrentDate()
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.body
                        font.bold: true
                    }
                }
            }
        }

        // Welcome Message
        Rectangle {
            width: parent.width
            height: 50
            radius: Theme.radius
            color: Theme.sideBtnpanel
            border.width: 2
            border.color: Theme.accent

            Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.pad
                anchors.verticalCenter: parent.verticalCenter
                text: root.loggedInUserFirstName ? ("Welcome, " + root.loggedInUserFirstName) : "Welcome"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontMed
                font.bold: true
            }
        }

        // Pre-Check List
        Item {
            width: parent.width
            height: parent.height - 60 - 50 - (Theme.gap * 2)

            Column {
                id: checkListContent
                anchors.centerIn: parent
                width: Math.min(parent.width, 700)
                spacing: Theme.gap

                Text {
                    text: "Pre-Check List"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontMed
                    font.bold: true
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Row {
                    width: parent.width
                    spacing: Theme.padLg
                    anchors.horizontalCenter: parent.horizontalCenter

                    // Left column
                    Column {
                        width: (parent.width - Theme.padLg) / 2
                        spacing: Theme.gapSm

                        Repeater {
                            model: [
                                "Correct wire",
                                "Correct Gas",
                                "Gas is on & full",
                                "Correct Pre-Heat",
                                "Nozzles are clean",
                                "Tips are clean",
                                "Ground cable is on",
                                "E-Stops & C-Stops are off",
                                "Grinding disks are not worn-out"
                            ]
                            delegate: Row {
                                spacing: 8
                                Text {
                                    text: "\u2022"
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.bodyLg
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: modelData
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.bodyLg
                                }
                            }
                        }
                    }

                    // Right column
                    Column {
                        width: (parent.width - Theme.padLg) / 2
                        spacing: Theme.gapSm

                        Repeater {
                            model: [
                                "Doors are closed",
                                "Robot path is unobstructed",
                                "Anchor magnets are engaged",
                                "Trap doors are shut",
                                "Correct WSM is loaded",
                                "Nobody is inside the cell",
                                "Power Supply is on",
                                "Generator has adequate fuel",
                                "Air supply is on",
                                "Beacon light is working"
                            ]
                            delegate: Row {
                                spacing: 8
                                Text {
                                    text: "\u2022"
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.bodyLg
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: modelData
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.bodyLg
                                }
                            }
                        }
                    }
                }

                // Confirm Button
                Rectangle {
                    width: 200
                    height: 56
                    radius: Theme.radius
                    color: root.preCheckConfirmed ? Theme.stateDisabled : Theme.accent
                    anchors.horizontalCenter: parent.horizontalCenter

                    Text {
                        anchors.centerIn: parent
                        text: root.preCheckConfirmed ? "Unconfirm" : "Confirm"
                        color: root.preCheckConfirmed ? Theme.muted : Theme.panel
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.bodyLg
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.preCheckConfirmed = !root.preCheckConfirmed
                        }
                    }
                }
            }
        }
    }

    // New Weld Button - bottom right (pre-check view only)
    Rectangle {
        width: 180
        height: 56
        radius: Theme.radius
        color: root.preCheckConfirmed ? Theme.accent : Theme.stateDisabled
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: Theme.pad
        anchors.bottomMargin: Theme.pad
        visible: !root.showWeldRecord

        Text {
            anchors.centerIn: parent
            text: "New Weld"
            color: root.preCheckConfirmed ? Theme.panel : Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.body
            font.bold: true
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.preCheckConfirmed
            cursorShape: root.preCheckConfirmed ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                root.showWeldRecord = true
            }
        }
    }

    // =========================================================
    // WELD RECORD VIEW
    // =========================================================
    Item {
        id: weldRecordView
        anchors.fill: parent
        anchors.margins: Theme.pad
        visible: root.showWeldRecord && !root.showScanView

        // Two tables side by side
        Row {
            id: tablesRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: bottomBar.top
            anchors.bottomMargin: Theme.gap
            spacing: Theme.padLg

            // ---- Essential Variables Table ----
            Rectangle {
                width: (parent.width - Theme.padLg) / 2
                height: essVarsCol.implicitHeight
                radius: Theme.radius
                color: Theme.sideBtnBase
                border.width: 2
                border.color: Theme.border
                clip: true

                Column {
                    id: essVarsCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top

                    // Header
                    Rectangle {
                        width: parent.width
                        height: 44
                        color: Theme.accent
                        radius: Theme.radius

                        // Square off bottom corners
                        Rectangle {
                            width: parent.width
                            height: Theme.radius
                            color: Theme.accent
                            anchors.bottom: parent.bottom
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "Essential Variables"
                            color: Theme.panel
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.body
                            font.bold: true
                        }
                    }

                    // Rows
                    Repeater {
                        model: [
                            { label: "Pipe Diameter", val1: "1,219mm", val2: "48\"" },
                            { label: "Wall Thickness", val1: "15.88mm", val2: "0.625\"" },
                            { label: "Bevel Prep", val1: "30\u00b0", val2: "" },
                            { label: "Pre-Heat Temp", val1: "100\u00b0 C", val2: "212\u00b0F" },
                            { label: "Wire Type", val1: "GMAW", val2: "" },
                            { label: "Wire Diameter", val1: "1.2mm", val2: "0.045\"" },
                            { label: "Wire Brand", val1: "Lincoln", val2: "" },
                            { label: "Shield Gas", val1: "Ar/Co2 85/15", val2: "" }
                        ]
                        delegate: Rectangle {
                            width: parent ? parent.width : 0
                            height: 40
                            color: index % 2 === 0 ? Theme.sideBtnpanel : Theme.sideBtnBase

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.pad
                                anchors.rightMargin: Theme.pad

                                Text {
                                    width: parent.width * 0.4
                                    height: parent.height
                                    text: modelData.label
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.body
                                    font.bold: true
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Text {
                                    width: parent.width * 0.3
                                    height: parent.height
                                    text: modelData.val1
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.body
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                Text {
                                    width: parent.width * 0.3
                                    height: parent.height
                                    text: modelData.val2
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.body
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }
                    }
                }
            }

            // ---- Weld Record Data Table ----
            Rectangle {
                width: (parent.width - Theme.padLg) / 2
                height: weldRecordCol.implicitHeight
                radius: Theme.radius
                color: Theme.sideBtnBase
                border.width: 2
                border.color: Theme.border
                clip: true

                Column {
                    id: weldRecordCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top

                    // Header
                    Rectangle {
                        width: parent.width
                        height: 44
                        color: Theme.accent
                        radius: Theme.radius

                        Rectangle {
                            width: parent.width
                            height: Theme.radius
                            color: Theme.accent
                            anchors.bottom: parent.bottom
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "Weld Record Data"
                            color: Theme.panel
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.body
                            font.bold: true
                        }
                    }

                    // Weld ID
                    Rectangle {
                        width: parent.width
                        height: 40
                        color: Theme.sideBtnpanel

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.pad
                            anchors.rightMargin: Theme.pad

                            Text {
                                width: parent.width * 0.45
                                height: parent.height
                                text: "Weld ID"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.body
                                font.bold: true
                                verticalAlignment: Text.AlignVCenter
                            }

                            TextField {
                                width: parent.width * 0.55
                                height: parent.height
                                text: root.weldId
                                onTextChanged: root.weldId = text
                                placeholderText: "Input from operator"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.bodySm
                                color: Theme.text
                                verticalAlignment: Text.AlignVCenter
                                background: Rectangle { color: "transparent" }
                            }
                        }
                    }

                    // Project
                    Rectangle {
                        width: parent.width
                        height: 40
                        color: Theme.sideBtnBase

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.pad
                            anchors.rightMargin: Theme.pad

                            Text {
                                width: parent.width * 0.45
                                height: parent.height
                                text: "Project"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.body
                                font.bold: true
                                verticalAlignment: Text.AlignVCenter
                            }

                            TextField {
                                width: parent.width * 0.55
                                height: parent.height
                                text: root.weldProject
                                onTextChanged: root.weldProject = text
                                placeholderText: "Input from operator"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.bodySm
                                color: Theme.text
                                verticalAlignment: Text.AlignVCenter
                                background: Rectangle { color: "transparent" }
                            }
                        }
                    }

                    // Client
                    Rectangle {
                        width: parent.width
                        height: 40
                        color: Theme.sideBtnpanel

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.pad
                            anchors.rightMargin: Theme.pad

                            Text {
                                width: parent.width * 0.45
                                height: parent.height
                                text: "Client"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.body
                                font.bold: true
                                verticalAlignment: Text.AlignVCenter
                            }

                            TextField {
                                width: parent.width * 0.55
                                height: parent.height
                                text: root.weldClient
                                onTextChanged: root.weldClient = text
                                placeholderText: "Input from operator"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.bodySm
                                color: Theme.text
                                verticalAlignment: Text.AlignVCenter
                                background: Rectangle { color: "transparent" }
                            }
                        }
                    }

                    // Operator (read-only)
                    Rectangle {
                        width: parent.width
                        height: 40
                        color: Theme.sideBtnBase

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.pad
                            anchors.rightMargin: Theme.pad

                            Text {
                                width: parent.width * 0.45
                                height: parent.height
                                text: "Operator"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.body
                                font.bold: true
                                verticalAlignment: Text.AlignVCenter
                            }

                            Text {
                                width: parent.width * 0.55
                                height: parent.height
                                text: root.loggedInUserFirstName + " " + root.loggedInUserLastName
                                color: Theme.muted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.bodySm
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    // Location Coords (read-only)
                    Rectangle {
                        width: parent.width
                        height: 40
                        color: Theme.sideBtnpanel

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.pad
                            anchors.rightMargin: Theme.pad

                            Text {
                                width: parent.width * 0.45
                                height: parent.height
                                text: "Location Coords"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.body
                                font.bold: true
                                verticalAlignment: Text.AlignVCenter
                            }

                            Text {
                                width: parent.width * 0.55
                                height: parent.height
                                text: "Pulled from tablet GPS"
                                color: Theme.muted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.bodySm
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    // Upstream Heat #
                    Rectangle {
                        width: parent.width
                        height: 40
                        color: Theme.sideBtnBase

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.pad
                            anchors.rightMargin: Theme.pad

                            Text {
                                width: parent.width * 0.45
                                height: parent.height
                                text: "Upstream Heat #"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.body
                                font.bold: true
                                verticalAlignment: Text.AlignVCenter
                            }

                            TextField {
                                width: parent.width * 0.55
                                height: parent.height
                                text: root.weldUpstreamHeat
                                onTextChanged: root.weldUpstreamHeat = text
                                placeholderText: "Input from operator"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.bodySm
                                color: Theme.text
                                verticalAlignment: Text.AlignVCenter
                                background: Rectangle { color: "transparent" }
                            }
                        }
                    }

                    // Downstream Heat #
                    Rectangle {
                        width: parent.width
                        height: 40
                        color: Theme.sideBtnpanel

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.pad
                            anchors.rightMargin: Theme.pad

                            Text {
                                width: parent.width * 0.45
                                height: parent.height
                                text: "Downstream Heat #"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.body
                                font.bold: true
                                verticalAlignment: Text.AlignVCenter
                            }

                            TextField {
                                width: parent.width * 0.55
                                height: parent.height
                                text: root.weldDownstreamHeat
                                onTextChanged: root.weldDownstreamHeat = text
                                placeholderText: "Input from operator"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.bodySm
                                color: Theme.text
                                verticalAlignment: Text.AlignVCenter
                                background: Rectangle { color: "transparent" }
                            }
                        }
                    }

                    // Comments
                    Rectangle {
                        width: parent.width
                        height: 40
                        color: Theme.sideBtnBase

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.pad
                            anchors.rightMargin: Theme.pad

                            Text {
                                width: parent.width * 0.45
                                height: parent.height
                                text: "Comments"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.body
                                font.bold: true
                                verticalAlignment: Text.AlignVCenter
                            }

                            TextField {
                                width: parent.width * 0.55
                                height: parent.height
                                text: root.weldComments
                                onTextChanged: root.weldComments = text
                                placeholderText: "Input from operator"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.bodySm
                                color: Theme.text
                                verticalAlignment: Text.AlignVCenter
                                background: Rectangle { color: "transparent" }
                            }
                        }
                    }
                }
            }
        }

        // Error / Success Message
        Text {
            id: saveMessageText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: bottomBar.top
            anchors.bottomMargin: Theme.gapSm
            horizontalAlignment: Text.AlignHCenter
            text: root.saveErrorMessage !== "" ? root.saveErrorMessage : root.saveSuccessMessage
            color: root.saveErrorMessage !== "" ? "#ff4444" : "#44cc66"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.body
            font.bold: true
            visible: root.saveErrorMessage !== "" || root.saveSuccessMessage !== ""
        }

        Timer {
            id: successTimer
            interval: 3000
            onTriggered: root.saveSuccessMessage = ""
        }

        // Bottom Navigation Bar
        Row {
            id: bottomBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 48
            spacing: Theme.gap

            // I/O Button
            Rectangle {
                width: (parent.width - Theme.gap * 4) / 5
                height: parent.height
                radius: Theme.radius
                color: Theme.sideBtnBase
                border.width: 2
                border.color: Theme.border

                Text {
                    anchors.centerIn: parent
                    text: "I/O"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.body
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: console.log("I/O clicked")
                }
            }

            // New Weld Button
            Rectangle {
                width: (parent.width - Theme.gap * 4) / 5
                height: parent.height
                radius: Theme.radius
                color: Theme.sideBtnBase
                border.width: 2
                border.color: Theme.border

                Text {
                    anchors.centerIn: parent
                    text: "New Weld"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.body
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: console.log("New Weld clicked")
                }
            }

            // View WSM Button
            Rectangle {
                width: (parent.width - Theme.gap * 4) / 5
                height: parent.height
                radius: Theme.radius
                color: Theme.sideBtnBase
                border.width: 2
                border.color: Theme.border

                Text {
                    anchors.centerIn: parent
                    text: "View WSM"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.body
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: console.log("View WSM clicked")
                }
            }

            // Save Weld Button
            Rectangle {
                width: (parent.width - Theme.gap * 4) / 5
                height: parent.height
                radius: Theme.radius
                color: Theme.success
                border.width: 2
                border.color: "#3ab86a"

                Text {
                    anchors.centerIn: parent
                    text: "Save Weld"
                    color: Theme.panel
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.body
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.saveErrorMessage = ""
                        root.saveSuccessMessage = ""
                        var result = WeldRecordService.saveWeldRecord(
                            root.weldId,
                            root.weldProject,
                            root.weldClient,
                            root.loggedInUserFirstName + " " + root.loggedInUserLastName,
                            root.weldUpstreamHeat,
                            root.weldDownstreamHeat,
                            root.weldComments,
                            "GPS pending"
                        )
                        if (result === "") {
                            root.saveSuccessMessage = "Weld record saved successfully!"
                            successTimer.restart()
                        } else {
                            root.saveErrorMessage = result
                        }
                    }
                }
            }

            // Start Scan Button
            Rectangle {
                width: (parent.width - Theme.gap * 4) / 5
                height: parent.height
                radius: Theme.radius
                color: Theme.success
                border.width: 2
                border.color: "#3ab86a"

                Text {
                    anchors.centerIn: parent
                    text: "Start Scan"
                    color: Theme.panel
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.body
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.scanLoading = true
                        scanLoadTimer.start()
                    }
                }
            }
        }
    }

    // Scan loading timer - renders plot to image then shows scan view
    Timer {
        id: scanLoadTimer
        interval: 500
        onTriggered: {
            var imgPath = ScanPlot.renderScanPlotLocal()
            root.scanLoading = false
            if (imgPath !== "") {
                root.scanPlotImage = "file:///" + imgPath + "?t=" + Date.now()
                root.showScanView = true
            } else {
                root.saveErrorMessage = "Failed to render scan plot."
            }
        }
    }

    // Debounce timer for interactive re-rendering
    Timer {
        id: scanRenderDebounce
        interval: 150
        onTriggered: {
            root.scanRendering = true
            var imgPath = ScanPlot.renderScanPlotView(root.scanElev, root.scanAzim, root.scanZoom)
            root.scanRendering = false
            if (imgPath !== "") {
                root.scanPlotImage = "file:///" + imgPath + "?t=" + Date.now()
            }
        }
    }

    function requestScanRender() {
        scanRenderDebounce.restart()
    }

    // =========================================================
    // LOADING OVERLAY
    // =========================================================
    Rectangle {
        id: loadingOverlay
        anchors.fill: parent
        color: "#cc0d1117"
        visible: root.scanLoading
        z: 100

        Column {
            anchors.centerIn: parent
            spacing: Theme.gap

            // Spinning indicator
            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: root.scanLoading
                width: 64
                height: 64
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Loading Scan..."
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontMed
                font.bold: true
            }
        }
    }

    // =========================================================
    // SCAN VIEW
    // =========================================================
    Item {
        id: scanView
        anchors.fill: parent
        anchors.margins: Theme.pad
        visible: root.showScanView && !root.scanLoading

        // Embedded scan plot image with interaction
        Rectangle {
            id: scanPlotContainer
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: scanButtonsCol.left
            anchors.rightMargin: Theme.gap
            radius: Theme.radius
            color: "#0d1117"
            border.width: 2
            border.color: Theme.border
            clip: true

            Image {
                id: scanPlotImg
                anchors.fill: parent
                anchors.margins: 4
                source: root.scanPlotImage
                fillMode: Image.PreserveAspectFit
                cache: false
                opacity: root.scanRendering ? 0.5 : 1.0
            }

            // Rendering indicator
            BusyIndicator {
                anchors.centerIn: parent
                running: root.scanRendering
                visible: root.scanRendering
                width: 32
                height: 32
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                onPressed: function(mouse) {
                    root.scanDragStartX = mouse.x
                    root.scanDragStartAzim = root.scanElev
                }

                onPositionChanged: function(mouse) {
                    if (pressed) {
                        var dx = mouse.x - root.scanDragStartX
                        // Horizontal drag changes elevation (rotates ring around its center axis)
                        root.scanElev = root.scanDragStartAzim + dx * 0.3
                        root.requestScanRender()
                    }
                }

                onWheel: function(wheel) {
                    if (wheel.angleDelta.y > 0) {
                        root.scanZoom = Math.max(0.3, root.scanZoom * 0.9)
                    } else {
                        root.scanZoom = Math.min(3.0, root.scanZoom / 0.9)
                    }
                    root.requestScanRender()
                }
            }
        }

        // Right-side buttons
        Column {
            id: scanButtonsCol
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 160
            spacing: Theme.gapSm

            // --- View Preset Buttons ---
            Text {
                width: parent.width
                text: "View"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySm
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            // Helper function for view buttons
            // Iso Home
            Rectangle {
                width: parent.width; height: 38; radius: Theme.radius
                color: Theme.sideBtnBase; border.width: 1; border.color: Theme.border
                Text { anchors.centerIn: parent; text: "Iso Home"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySm; font.bold: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.scanElev = 20; root.scanAzim = 140; root.scanZoom = 1.0; root.requestScanRender() } }
            }
            // Front
            Rectangle {
                width: parent.width; height: 38; radius: Theme.radius
                color: Theme.sideBtnBase; border.width: 1; border.color: Theme.border
                Text { anchors.centerIn: parent; text: "Front"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySm; font.bold: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.scanElev = 0; root.scanAzim = 90; root.scanZoom = 1.0; root.requestScanRender() } }
            }
            // Back
            Rectangle {
                width: parent.width; height: 38; radius: Theme.radius
                color: Theme.sideBtnBase; border.width: 1; border.color: Theme.border
                Text { anchors.centerIn: parent; text: "Back View"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySm; font.bold: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.scanElev = 0; root.scanAzim = -90; root.scanZoom = 1.0; root.requestScanRender() } }
            }
            // Left
            Rectangle {
                width: parent.width; height: 38; radius: Theme.radius
                color: Theme.sideBtnBase; border.width: 1; border.color: Theme.border
                Text { anchors.centerIn: parent; text: "Left"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySm; font.bold: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.scanElev = 0; root.scanAzim = 0; root.scanZoom = 1.0; root.requestScanRender() } }
            }
            // Right
            Rectangle {
                width: parent.width; height: 38; radius: Theme.radius
                color: Theme.sideBtnBase; border.width: 1; border.color: Theme.border
                Text { anchors.centerIn: parent; text: "Right"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySm; font.bold: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.scanElev = 0; root.scanAzim = 180; root.scanZoom = 1.0; root.requestScanRender() } }
            }
            // Top
            Rectangle {
                width: parent.width; height: 38; radius: Theme.radius
                color: Theme.sideBtnBase; border.width: 1; border.color: Theme.border
                Text { anchors.centerIn: parent; text: "Top"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySm; font.bold: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.scanElev = 90; root.scanAzim = 140; root.scanZoom = 1.0; root.requestScanRender() } }
            }
            // Side
            Rectangle {
                width: parent.width; height: 38; radius: Theme.radius
                color: Theme.sideBtnBase; border.width: 1; border.color: Theme.border
                Text { anchors.centerIn: parent; text: "Side"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySm; font.bold: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.scanElev = 0; root.scanAzim = 0; root.scanZoom = 1.0; root.requestScanRender() } }
            }

            // --- Spacer ---
            Item { width: 1; height: Theme.gap }

            // --- Action Buttons ---
            // Go Back
            Rectangle {
                width: parent.width; height: 48; radius: Theme.radius
                color: Theme.sideBtnBase; border.width: 2; border.color: Theme.border
                Text { anchors.centerIn: parent; text: "Go Back"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.body; font.bold: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.showScanView = false } }
            }
            // Scan Data
            Rectangle {
                width: parent.width; height: 48; radius: Theme.radius
                color: Theme.accent; border.width: 2; border.color: Theme.accent
                Text { anchors.centerIn: parent; text: "Scan Data"; color: Theme.panel; font.family: Theme.fontFamily; font.pixelSize: Theme.body; font.bold: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { ScanPlot.showScanDataLocal() } }
            }
            // Start Weld
            Rectangle {
                width: parent.width; height: 48; radius: Theme.radius
                color: Theme.success; border.width: 2; border.color: "#3ab86a"
                Text { anchors.centerIn: parent; text: "Start Weld"; color: Theme.panel; font.family: Theme.fontFamily; font.pixelSize: Theme.body; font.bold: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { console.log("Start Weld clicked") } }
            }
        }
    }

    Connections {
        target: ScanPlot
        function onError(msg) {
            console.log("ScanPlot error:", msg)
            root.scanLoading = false
            root.showScanView = true
            root.saveErrorMessage = "Scan failed: Could not connect to robot. Check network connection."
        }
        function onLaunched() { console.log("Scan plot launched") }
    }
}
