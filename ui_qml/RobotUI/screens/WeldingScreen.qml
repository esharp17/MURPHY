import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Dialogs
import RobotUI 1.0
import ScanPlot 1.0

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
    property real scanAzim: 140
    property real scanElev: 20
    property real scanZoom: 1.0
    property real scanPanX: 0.0
    property real scanPanY: 0.0
    property bool scanDataLoaded: false
    property string scanSelectedInfo: ""
    property bool showScanDataPage: false
    property var scanRowData: []
    property real scanYScale: 1.0
    property real scanCylDiam: 45.0
    property real scanTransparency: 0.25

    // Essential Variables from WSM PDF
    property var essentialVarsModel: []
    property string wsmPdfName: ""
    property string wsmFolder: WsmService ? WsmService.folder : ""

    Connections {
        target: WsmService
        function onDataChanged() {
            root.essentialVarsModel = WsmService.essentialVariables()
            root.wsmPdfName = WsmService.pdfName
        }
    }

    Component.onCompleted: {
        if (WsmService && WsmService.folder) {
            root.essentialVarsModel = WsmService.essentialVariables()
            root.wsmPdfName = WsmService.pdfName
        }
    }

    FolderDialog {
        id: wsmFolderDialog
        title: "Select WSM Folder"
        onAccepted: {
            WsmService.setFolder(selectedFolder.toString())
        }
    }

    // Get current date formatted as "Month Day, Year"
    function getCurrentDate() {
        var date = new Date()
        var months = ["January", "February", "March", "April", "May", "June",
                      "July", "August", "September", "October", "November", "December"]
        return months[date.getMonth()] + " " + date.getDate() + ", " + date.getFullYear()
    }

    // =========================================================
    // ALWAYS-VISIBLE HEADER (Top Info Bar + Welcome)
    // =========================================================
    Column {
        id: alwaysVisibleHeader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.pad
        spacing: Theme.gap
        visible: !root.showScanView

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
                        text: root.wsmPdfName ? ("Running WSM: " + root.wsmPdfName.replace(".pdf", "").replace(".PDF", "")) : "Running WSM"
                        color: root.wsmPdfName ? Theme.text : Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.bodySm
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
    }

    // =========================================================
    // PRE-CHECK VIEW
    // =========================================================
    Item {
        id: preCheckView
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: alwaysVisibleHeader.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: Theme.pad
        anchors.rightMargin: Theme.pad
        anchors.topMargin: Theme.gap
        anchors.bottomMargin: Theme.pad
        visible: !root.showWeldRecord

        // Pre-Check List
        Item {
            width: parent.width
            height: parent.height

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
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: alwaysVisibleHeader.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: Theme.pad
        anchors.rightMargin: Theme.pad
        anchors.topMargin: Theme.gap
        anchors.bottomMargin: Theme.pad
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

                    // WSM folder selector + PDF name
                    Rectangle {
                        width: parent.width
                        height: 36
                        color: Theme.sideBtnpanel

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.pad
                            anchors.rightMargin: 4
                            spacing: 6

                            Text {
                                width: parent.width - selectFolderBtn.width - refreshBtn.width - 18
                                height: parent.height
                                text: root.wsmPdfName ? ("Running WSM: " + root.wsmPdfName.replace(".pdf", "").replace(".PDF", "")) : (root.wsmFolder ? "No PDF found" : "No WSM folder selected")
                                color: root.wsmPdfName ? Theme.text : Theme.muted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.bodySm
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideMiddle
                            }

                            Rectangle {
                                id: refreshBtn
                                width: 28; height: 28
                                radius: 4
                                color: Theme.accent
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.wsmFolder !== ""

                                Text {
                                    anchors.centerIn: parent
                                    text: "\u21BB"
                                    color: "white"
                                    font.pixelSize: 16
                                    font.bold: true
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: WsmService.reload()
                                }
                            }

                            Rectangle {
                                id: selectFolderBtn
                                width: 80; height: 28
                                radius: 4
                                color: Theme.accent
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: "Browse..."
                                    color: "white"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.bodySm
                                    font.bold: true
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: wsmFolderDialog.open()
                                }
                            }
                        }
                    }

                    // Rows
                    Repeater {
                        model: root.essentialVarsModel.length > 0 ? root.essentialVarsModel : [
                            { label: "Pipe Diameter", val1: "--", val2: "" },
                            { label: "Wall Thickness", val1: "--", val2: "" },
                            { label: "Bevel Prep", val1: "--", val2: "" },
                            { label: "Pre-Heat Temp", val1: "--", val2: "" },
                            { label: "Wire Type", val1: "--", val2: "" },
                            { label: "Wire Diameter", val1: "--", val2: "" },
                            { label: "Wire Brand", val1: "--", val2: "" },
                            { label: "Shield Gas", val1: "--", val2: "" }
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
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: parent.width
            height: 48
            spacing: Theme.gap

            // New Weld Button
            InteractiveSurface {
                width: (parent.width - Theme.gap * 3) / 4
                height: parent.height
                radius: Theme.radius
                normalColor: Theme.sideBtnBase
                pressedColor: Theme.btnPressed
                disabledColor: Theme.btnDisabled
                borderWidth: 2
                borderColor: Theme.border

                onClicked: {
                    root.weldId = ""
                    root.weldComments = ""
                    root.weldUpstreamHeat = ""
                    root.weldDownstreamHeat = ""
                    root.saveErrorMessage = ""
                    root.saveSuccessMessage = ""
                }

                Text {
                    anchors.centerIn: parent
                    text: "New Weld"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.body
                    font.bold: true
                }
            }

            // View WSM Button
            InteractiveSurface {
                width: (parent.width - Theme.gap * 3) / 4
                height: parent.height
                radius: Theme.radius
                normalColor: Theme.sideBtnBase
                pressedColor: Theme.btnPressed
                disabledColor: Theme.btnDisabled
                borderWidth: 2
                borderColor: Theme.border

                onClicked: console.log("View WSM clicked")

                Text {
                    anchors.centerIn: parent
                    text: "View WSM"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.body
                    font.bold: true
                }
            }

            // Save Weld Button
            InteractiveSurface {
                width: (parent.width - Theme.gap * 3) / 4
                height: parent.height
                radius: Theme.radius
                normalColor: Theme.success
                pressedColor: Theme.btnPressed
                disabledColor: Theme.btnDisabled
                borderWidth: 2
                borderColor: "#3ab86a"

                onClicked: {
                    root.saveErrorMessage = ""
                    root.saveSuccessMessage = ""
                    var ev = root.essentialVarsModel
                    var result = WeldRecordService.saveWeldRecord(
                        root.weldId,
                        root.weldProject,
                        root.weldClient,
                        root.loggedInUserFirstName + " " + root.loggedInUserLastName,
                        root.weldUpstreamHeat,
                        root.weldDownstreamHeat,
                        root.weldComments,
                        "GPS pending",
                        ev.length > 0 ? (ev[0].val1 + (ev[0].val2 ? " / " + ev[0].val2 : "")) : "",
                        ev.length > 1 ? (ev[1].val1 + (ev[1].val2 ? " / " + ev[1].val2 : "")) : "",
                        ev.length > 2 ? ev[2].val1 : "",
                        ev.length > 3 ? (ev[3].val1 + (ev[3].val2 ? " / " + ev[3].val2 : "")) : "",
                        ev.length > 4 ? ev[4].val1 : "",
                        ev.length > 5 ? (ev[5].val1 + (ev[5].val2 ? " / " + ev[5].val2 : "")) : "",
                        ev.length > 6 ? ev[6].val1 : "",
                        ev.length > 7 ? ev[7].val1 : ""
                    )
                    if (result === "") {
                        root.saveSuccessMessage = "Weld record saved successfully!"
                        successTimer.restart()
                    } else {
                        root.saveErrorMessage = result
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "Save Weld"
                    color: Theme.panel
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.body
                    font.bold: true
                }
            }

            // Start Scan Button
            InteractiveSurface {
                width: (parent.width - Theme.gap * 3) / 4
                height: parent.height
                radius: Theme.radius
                normalColor: Theme.success
                pressedColor: Theme.btnPressed
                disabledColor: Theme.btnDisabled
                borderWidth: 2
                borderColor: "#3ab86a"

                onClicked: {
                    root.scanLoading = true
                    scanLoadTimer.start()
                }

                Text {
                    anchors.centerIn: parent
                    text: "Start Scan"
                    color: Theme.panel
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.body
                    font.bold: true
                }
            }
        }
    }

    // Scan loading timer - loads data via ScanDataProvider then shows scan view
    Timer {
        id: scanLoadTimer
        interval: 100
        onTriggered: {
            ScanDataProvider.loadData()
            root.scanLoading = false
            if (ScanDataProvider.isLoaded()) {
                root.scanDataLoaded = true
                root.showScanView = true
            } else {
                root.saveErrorMessage = "Failed to load scan data: " + ScanDataProvider.errorString()
            }
        }
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
        anchors.margins: Theme.gapSm
        visible: root.showScanView && !root.scanLoading && !root.showScanDataPage

        property var ioConfigObj: null
        property int alertRobotIndex: 1
        property var watchAlertKeys: ["DI41"]
        property var dismissedAlertKeys: ({})
        property bool debugForceAlerts: false

        ListModel { id: activeAlertsModel }

        function _ioConfigUrlRobot1() {
            return Qt.resolvedUrl("../assets/IO_config_robot_1.json")
        }

        function loadIoConfigRobot1() {
            var url = _ioConfigUrlRobot1()
            var xhr = new XMLHttpRequest()
            xhr.open("GET", url)
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return
                if (!(xhr.status === 200 || xhr.status === 0)) return
                if (!xhr.responseText || xhr.responseText.length < 2) return

                var obj
                try { obj = JSON.parse(xhr.responseText) }
                catch (e) { console.log("IO_CONFIG JSON parse fail:", e); return }
                ioConfigObj = obj
                refreshAlerts()
            }
            xhr.send()
        }

        Component.onCompleted: {
            loadIoConfigRobot1()
            debugForceAlerts = true
        }

        function _bitFromWords(words, bit1) {
            if (!words || bit1 <= 0) return 0
            var wi = Math.floor((bit1 - 1) / 16)
            var bi = (bit1 - 1) % 16
            if (wi < 0 || wi >= words.length) return 0
            var w = Number(words[wi]) & 0xFFFF
            return (w >> bi) & 1
        }

        function _ioKeyToBit1(key) {
            if (!key || String(key).length < 3) return -1
            var m = String(key).match(/^(DI|DO)(\d+)$/)
            if (!m) return -1
            var n = parseInt(m[2], 10)
            if (isNaN(n) || n <= 0) return -1
            return n
        }

        function _isAlertActiveForKey(key) {
            if (debugForceAlerts) return true
            var bit1 = _ioKeyToBit1(key)
            if (bit1 <= 0) return false

            if (String(key).indexOf("DI") === 0) {
                return _bitFromWords(RobotComm.getInputs(alertRobotIndex), bit1) === 1
            }
            if (String(key).indexOf("DO") === 0) {
                return _bitFromWords(RobotComm.getOutputs(alertRobotIndex), bit1) === 1
            }
            return false
        }

        function _alertLabelForKey(key) {
            if (ioConfigObj && ioConfigObj[key] && ioConfigObj[key].label)
                return String(ioConfigObj[key].label)
            return String(key)
        }

        function _indexOfAlertKey(key) {
            for (var i = 0; i < activeAlertsModel.count; i++) {
                if (activeAlertsModel.get(i).key === key) return i
            }
            return -1
        }

        function refreshAlerts() {
            for (var k = 0; k < watchAlertKeys.length; k++) {
                var key = String(watchAlertKeys[k])
                var active = _isAlertActiveForKey(key)
                var idx = _indexOfAlertKey(key)

                if (!active) {
                    if (idx >= 0) activeAlertsModel.remove(idx)
                    if (dismissedAlertKeys && dismissedAlertKeys[key]) dismissedAlertKeys[key] = false
                    continue
                }

                if (dismissedAlertKeys && dismissedAlertKeys[key]) {
                    if (idx >= 0) activeAlertsModel.remove(idx)
                    continue
                }

                if (idx < 0) {
                    activeAlertsModel.append({
                        key: key,
                        label: _alertLabelForKey(key)
                    })
                }
            }
        }

        function acknowledgeAlert(key) {
            dismissedAlertKeys[key] = true
            var idx = _indexOfAlertKey(key)
            if (idx >= 0) activeAlertsModel.remove(idx)
        }

        Connections {
            target: RobotComm
            function onIoUpdated(i) {
                if (i === scanView.alertRobotIndex) scanView.refreshAlerts()
            }
        }

        // Right side: alert stack
        Column {
            id: alertCol
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: Theme.gapSm
            width: 300

            Rectangle {
                width: parent.width
                height: 300
                color: Theme.sideBtnBase
                border.width: 2
                border.color: Theme.border

                Flickable {
                    anchors.fill: parent
                    anchors.margins: Theme.gapSm
                    clip: true
                    contentWidth: width
                    contentHeight: alertStack.implicitHeight

                    Column {
                        id: alertStack
                        width: parent.width
                        spacing: Theme.gapSm

                        Repeater {
                            model: activeAlertsModel
                            delegate: Rectangle {
                                width: alertStack.width
                                radius: Theme.radius
                                color: Theme.panel
                                border.width: 2
                                border.color: "#cc0000"

                                Column {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: Theme.gapSm
                                    spacing: Theme.gapSm

                                    Text {
                                        text: "Notification:"
                                        color: Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.body
                                        font.bold: true
                                        wrapMode: Text.WordWrap
                                        width: parent.width
                                    }

                                    Text {
                                        text: label
                                        color: Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.body
                                        wrapMode: Text.WordWrap
                                        width: parent.width
                                    }

                                    Row {
                                        spacing: Theme.gapSm
                                        anchors.horizontalCenter: parent.horizontalCenter

                                        Rectangle {
                                            width: 90
                                            height: 34
                                            radius: Theme.radius
                                            color: Theme.sideBtnBase
                                            border.width: 1
                                            border.color: Theme.border
                                            Text {
                                                anchors.centerIn: parent
                                                text: "No"
                                                color: Theme.text
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.body
                                                font.bold: true
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                            }
                                        }

                                        Rectangle {
                                            width: 90
                                            height: 34
                                            radius: Theme.radius
                                            color: Theme.sideBtnBase
                                            border.width: 1
                                            border.color: Theme.border
                                            Text {
                                                anchors.centerIn: parent
                                                text: "Yes"
                                                color: Theme.text
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.body
                                                font.bold: true
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: scanView.acknowledgeAlert(key)
                                            }
                                        }
                                    }

                                    Item {
                                        width: 1
                                        height: Theme.gapSm
                                    }
                                }

                                implicitHeight: childrenRect.height + Theme.gapSm
                            }
                        }

                        Rectangle {
                            visible: activeAlertsModel.count === 0
                            width: alertStack.width
                            height: 48
                            radius: Theme.radius
                            color: "#e6e6e6"
                            border.width: 2
                            border.color: "#cc0000"
                            Text {
                                anchors.centerIn: parent
                                text: "No Alerts"
                                color: "#000000"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.body
                                font.bold: true
                            }
                        }
                    }

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }
                }
            }
        }

        // Right-side action buttons (Go Back, Scan Data, Start Weld)
        Column {
            id: scanActionCol
            anchors.right: parent.right
            anchors.top: alertCol.bottom
            anchors.topMargin: Theme.gapSm
            anchors.bottom: parent.bottom
            width: 300
            spacing: Theme.gapSm

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
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.scanRowData = ScanDataProvider.getAllRowData(); root.showScanDataPage = true } }
            }

            // Start Weld
            Rectangle {
                width: parent.width; height: 48; radius: Theme.radius
                color: Theme.success; border.width: 2; border.color: "#3ab86a"
                Text { anchors.centerIn: parent; text: "Start Weld"; color: Theme.panel; font.family: Theme.fontFamily; font.pixelSize: Theme.body; font.bold: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { console.log("Start Weld clicked") } }
            }
        }

        // Main plot area with offwhite background and blue border
        Rectangle {
            id: scanPlotContainer
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.right: scanActionCol.left
            anchors.rightMargin: Theme.gapSm
            anchors.bottom: scanControlBar.top
            anchors.bottomMargin: Theme.gapSm
            radius: Theme.radius
            color: "#f0f2f5"
            border.width: 2
            border.color: Theme.accent
            clip: true

            ScanPlotItem {
                id: scanPlotItem
                anchors.fill: parent
                elev: root.scanElev
                azim: root.scanAzim
                zoom: root.scanZoom
                panX: root.scanPanX
                panY: root.scanPanY
                yScale: root.scanYScale
                cylDiam: root.scanCylDiam
                transparency: root.scanTransparency

                Component.onCompleted: {
                    if (root.scanDataLoaded) {
                        scanView.feedDataToPlot()
                    }
                }
            }

            // Touch: two-finger pinch-to-zoom + two-finger pan
            MultiPointTouchArea {
                id: touchArea
                anchors.fill: parent
                minimumTouchPoints: 2
                maximumTouchPoints: 2
                mouseEnabled: false

                property real startDist: 1.0
                property real startZoom: 1.0
                property real startCenterX: 0.0
                property real startCenterY: 0.0
                property real startPanX: 0.0
                property real startPanY: 0.0

                touchPoints: [
                    TouchPoint { id: tp1 },
                    TouchPoint { id: tp2 }
                ]

                onPressed: {
                    var dx = tp2.x - tp1.x
                    var dy = tp2.y - tp1.y
                    startDist = Math.max(1, Math.sqrt(dx * dx + dy * dy))
                    startZoom = root.scanZoom
                    startCenterX = (tp1.x + tp2.x) / 2.0
                    startCenterY = (tp1.y + tp2.y) / 2.0
                    startPanX = root.scanPanX
                    startPanY = root.scanPanY
                }

                onUpdated: {
                    var dx = tp2.x - tp1.x
                    var dy = tp2.y - tp1.y
                    var dist = Math.max(1, Math.sqrt(dx * dx + dy * dy))

                    // Pinch zoom
                    var scale = startDist / dist
                    var oldZoom = root.scanZoom
                    var newZoom = Math.max(0.05, Math.min(3.0, startZoom * scale))
                    root.scanZoom = newZoom

                    // Two-finger pan
                    var cx = (tp1.x + tp2.x) / 2.0
                    var cy = (tp1.y + tp2.y) / 2.0
                    var panDx = cx - startCenterX
                    var panDy = cy - startCenterY
                    var panScale = newZoom * 2.0
                    root.scanPanX = startPanX + panDx * panScale
                    root.scanPanY = startPanY - panDy * panScale

                    // Zoom toward pinch center
                    var dz = oldZoom - newZoom
                    var relX = (cx / scanPlotContainer.width - 0.5) * 2.0
                    var relY = (cy / scanPlotContainer.height - 0.5) * 2.0
                    root.scanPanX += scanPlotItem.xzHalf * dz * relX
                    root.scanPanY -= scanPlotItem.yHalf * dz * relY
                }
            }

            // Mouse: left-drag rotate, right-drag pan, scroll zoom, click pick
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                hoverEnabled: true

                property int activeButton: Qt.NoButton
                property real dragStartX: 0
                property real dragStartY: 0
                property real dragStartAzim: 0
                property real dragStartElev: 0
                property real dragStartPanX: 0
                property real dragStartPanY: 0

                onPressed: function(mouse) {
                    activeButton = mouse.button
                    dragStartX = mouse.x
                    dragStartY = mouse.y
                    if (mouse.button === Qt.LeftButton) {
                        dragStartAzim = root.scanAzim
                        dragStartElev = root.scanElev
                    } else if (mouse.button === Qt.RightButton) {
                        dragStartPanX = root.scanPanX
                        dragStartPanY = root.scanPanY
                    }
                }

                onPositionChanged: function(mouse) {
                    if (!pressed) return
                    var dx = mouse.x - dragStartX
                    var dy = mouse.y - dragStartY
                    if (activeButton === Qt.LeftButton) {
                        // Rotate
                        root.scanAzim = dragStartAzim - dx * 0.5
                        root.scanElev = Math.max(-90, Math.min(90, dragStartElev + dy * 0.3))
                    } else if (activeButton === Qt.RightButton) {
                        // Pan
                        var panScale = root.scanZoom * 2.0
                        root.scanPanX = dragStartPanX + dx * panScale
                        root.scanPanY = dragStartPanY - dy * panScale
                    }
                }

                onReleased: function(mouse) {
                    activeButton = Qt.NoButton
                }

                onWheel: function(wheel) {
                    var oldZoom = root.scanZoom
                    var newZoom
                    if (wheel.angleDelta.y > 0) {
                        newZoom = Math.max(0.05, oldZoom * 0.9)
                    } else {
                        newZoom = Math.min(3.0, oldZoom / 0.9)
                    }

                    // Zoom toward cursor
                    var dz = oldZoom - newZoom
                    var relX = (wheel.x / scanPlotContainer.width - 0.5) * 2.0
                    var relY = (wheel.y / scanPlotContainer.height - 0.5) * 2.0
                    root.scanPanX += scanPlotItem.xzHalf * dz * relX
                    root.scanPanY -= scanPlotItem.yHalf * dz * relY
                    root.scanZoom = newZoom
                }

                onClicked: function(mouse) {
                    if (mouse.button === Qt.LeftButton) {
                        scanPlotItem.pickPoint(mouse.x, mouse.y)
                    }
                }
            }
        }

        // Bottom control bar: view buttons on left, sliders on right
        Rectangle {
            id: scanControlBar
            anchors.left: parent.left
            anchors.right: scanActionCol.left
            anchors.rightMargin: Theme.gapSm
            anchors.bottom: infoStrip.top
            anchors.bottomMargin: Theme.gapSm
            height: 110
            radius: Theme.radius
            color: Theme.panelRecessed
            border.width: 1
            border.color: Theme.border

            Row {
                anchors.fill: parent
                anchors.margins: Theme.pad
                spacing: Theme.gapSm

                // View buttons
                Row {
                    spacing: Theme.gapSm
                    anchors.verticalCenter: parent.verticalCenter

                    Repeater {
                        model: [
                            { label: "Top",  elev: 90,  azim: -90 },
                            { label: "Front", elev: 0,   azim: -90 },
                            { label: "Iso",  elev: 25,  azim: -60 }
                        ]
                        delegate: Rectangle {
                            width: 80; height: 48; radius: Theme.radius
                            color: Theme.sideBtnBase
                            border.width: 2
                            border.color: Theme.border
                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.body
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.scanElev = modelData.elev
                                    root.scanAzim = modelData.azim
                                }
                            }
                        }
                    }
                }

                Rectangle { width: 1; height: parent.height; color: Theme.border; opacity: 0.5 }

                // Sliders
                Column {
                    spacing: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: scanControlBar.width - 270

                    Row {
                        spacing: 10
                        Text { width: 90; text: "Y Scale"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySm }
                        Slider {
                            id: yScaleSlider
                            from: 0.1
                            to: 5.0
                            stepSize: 0.05
                            value: root.scanYScale
                            onValueChanged: root.scanYScale = value
                            width: parent.width - 140
                        }
                        Text { width: 40; text: root.scanYScale.toFixed(2); color: Theme.muted; font.family: Theme.fontFamilyMono; font.pixelSize: Theme.caption }
                    }

                    Row {
                        spacing: 10
                        Text { width: 90; text: "Cyl Diam"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySm }
                        Slider {
                            id: cylDiamSlider
                            from: 1
                            to: 200
                            stepSize: 0.5
                            value: root.scanCylDiam
                            onValueChanged: root.scanCylDiam = value
                            width: parent.width - 140
                        }
                        Text { width: 40; text: root.scanCylDiam.toFixed(1); color: Theme.muted; font.family: Theme.fontFamilyMono; font.pixelSize: Theme.caption }
                    }

                    Row {
                        spacing: 10
                        Text { width: 90; text: "Transparency"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySm }
                        Slider {
                            id: transparencySlider
                            from: 0.0
                            to: 1.0
                            stepSize: 0.01
                            value: root.scanTransparency
                            onValueChanged: root.scanTransparency = value
                            width: parent.width - 140
                        }
                        Text { width: 40; text: root.scanTransparency.toFixed(2); color: Theme.muted; font.family: Theme.fontFamilyMono; font.pixelSize: Theme.caption }
                    }
                }
            }
        }

        // Info strip at bottom
        Rectangle {
            id: infoStrip
            anchors.left: parent.left
            anchors.right: scanActionCol.left
            anchors.rightMargin: Theme.gapSm
            anchors.bottom: parent.bottom
            height: 36
            radius: Theme.radius
            color: Theme.panelRecessed
            border.width: 1
            border.color: Theme.border

            Row {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 16

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: scanPlotItem.selectedInfo !== "" ? scanPlotItem.selectedInfo : "Tap a point to see details"
                    color: scanPlotItem.selectedInfo !== "" ? Theme.text : Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.caption
                    elide: Text.ElideRight
                    width: parent.width - statsText.width - 24
                }

                Text {
                    id: statsText
                    anchors.verticalCenter: parent.verticalCenter
                    text: scanPlotItem.pointCount + " pts  |  " + scanPlotItem.gapRange
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.caption
                }
            }
        }

        // Feed data to plot item from ScanDataProvider
        function feedDataToPlot() {
            scanPlotItem.loadFromProvider(ScanDataProvider)
        }

        // When scan data is loaded, feed it to the plot
        onVisibleChanged: {
            if (visible && root.scanDataLoaded) {
                feedDataToPlot()
            }
        }
    }

    // =========================================================
    // SCAN DATA TABLE PAGE
    // =========================================================
    Item {
        id: scanDataPage
        anchors.fill: parent
        anchors.margins: Theme.pad
        visible: root.showScanView && root.showScanDataPage && !root.scanLoading

        // Header bar
        Rectangle {
            id: dataPageHeader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 48
            radius: Theme.radius
            color: Theme.panelRecessed
            border.width: 1
            border.color: Theme.border

            Text {
                anchors.centerIn: parent
                text: "Scan Offset Data  (​" + root.scanRowData.length + " points)"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.body
                font.bold: true
            }

            // Back button
            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 80; height: 34; radius: Theme.radius
                color: Theme.sideBtnBase
                border.width: 1; border.color: Theme.border
                Text { anchors.centerIn: parent; text: "\u2190  Back"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySm; font.bold: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.showScanDataPage = false } }
            }
        }

        // Column headers
        Rectangle {
            id: tableHeader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: dataPageHeader.bottom
            anchors.topMargin: Theme.gapSm
            height: 32
            radius: Theme.radiusSm
            color: Theme.panelRecessed

            Row {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 0

                Text { width: parent.width * 0.06; text: "Pos"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.caption; font.bold: true; verticalAlignment: Text.AlignVCenter; height: parent.height }
                Text { width: parent.width * 0.10; text: "Gap (mm)"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.caption; font.bold: true; verticalAlignment: Text.AlignVCenter; height: parent.height }
                Text { width: parent.width * 0.08; text: "Sched"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.caption; font.bold: true; verticalAlignment: Text.AlignVCenter; height: parent.height }
                Text { width: parent.width * 0.11; text: "Off X"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.caption; font.bold: true; verticalAlignment: Text.AlignVCenter; height: parent.height }
                Text { width: parent.width * 0.11; text: "Off Y"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.caption; font.bold: true; verticalAlignment: Text.AlignVCenter; height: parent.height }
                Text { width: parent.width * 0.11; text: "Off Z"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.caption; font.bold: true; verticalAlignment: Text.AlignVCenter; height: parent.height }
                Text { width: parent.width * 0.11; text: "Act X"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.caption; font.bold: true; verticalAlignment: Text.AlignVCenter; height: parent.height }
                Text { width: parent.width * 0.11; text: "Act Y"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.caption; font.bold: true; verticalAlignment: Text.AlignVCenter; height: parent.height }
                Text { width: parent.width * 0.11; text: "Act Z"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.caption; font.bold: true; verticalAlignment: Text.AlignVCenter; height: parent.height }
            }
        }

        // Scrollable data rows
        ListView {
            id: dataListView
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: tableHeader.bottom
            anchors.topMargin: 2
            anchors.bottom: parent.bottom
            clip: true
            model: root.scanRowData
            flickDeceleration: 3000
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                width: dataListView.width
                height: 34
                radius: 0
                color: index % 2 === 0 ? "transparent" : Qt.rgba(1, 1, 1, 0.02)

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 0

                    Text { width: parent.width * 0.06; text: modelData.pos; color: Theme.text; font.family: Theme.fontFamilyMono; font.pixelSize: Theme.caption; verticalAlignment: Text.AlignVCenter; height: parent.height }
                    Text { width: parent.width * 0.10; text: modelData.gap.toFixed(3); color: Theme.text; font.family: Theme.fontFamilyMono; font.pixelSize: Theme.caption; verticalAlignment: Text.AlignVCenter; height: parent.height }
                    Text { width: parent.width * 0.08; text: Number(modelData.sched).toFixed(0); color: Theme.text; font.family: Theme.fontFamilyMono; font.pixelSize: Theme.caption; verticalAlignment: Text.AlignVCenter; height: parent.height }
                    Text { width: parent.width * 0.11; text: modelData.offX.toFixed(3); color: Theme.text; font.family: Theme.fontFamilyMono; font.pixelSize: Theme.caption; verticalAlignment: Text.AlignVCenter; height: parent.height }
                    Text { width: parent.width * 0.11; text: modelData.offY.toFixed(3); color: Theme.text; font.family: Theme.fontFamilyMono; font.pixelSize: Theme.caption; verticalAlignment: Text.AlignVCenter; height: parent.height }
                    Text { width: parent.width * 0.11; text: modelData.offZ.toFixed(3); color: Theme.text; font.family: Theme.fontFamilyMono; font.pixelSize: Theme.caption; verticalAlignment: Text.AlignVCenter; height: parent.height }
                    Text { width: parent.width * 0.11; text: modelData.actX.toFixed(2); color: Theme.muted; font.family: Theme.fontFamilyMono; font.pixelSize: Theme.caption; verticalAlignment: Text.AlignVCenter; height: parent.height }
                    Text { width: parent.width * 0.11; text: modelData.actY.toFixed(2); color: Theme.muted; font.family: Theme.fontFamilyMono; font.pixelSize: Theme.caption; verticalAlignment: Text.AlignVCenter; height: parent.height }
                    Text { width: parent.width * 0.11; text: modelData.actZ.toFixed(2); color: Theme.muted; font.family: Theme.fontFamilyMono; font.pixelSize: Theme.caption; verticalAlignment: Text.AlignVCenter; height: parent.height }
                }

                // Bottom border
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: Theme.border
                    opacity: 0.3
                }
            }

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
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