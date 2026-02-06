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

    // Get current date formatted as "Month Day, Year"
    function getCurrentDate() {
        var date = new Date()
        var months = ["January", "February", "March", "April", "May", "June",
                      "July", "August", "September", "October", "November", "December"]
        return months[date.getMonth()] + " " + date.getDate() + ", " + date.getFullYear()
    }

    Column {
        anchors.fill: parent
        anchors.margins: Theme.pad
        spacing: Theme.gap

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

        // Existing content area
        Item {
            width: parent.width
            height: parent.height - 60 - 50 - (Theme.gap * 2)

            Column {
                anchors.centerIn: parent
                spacing: 16

                Text {
                    text: "Welding Screen"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.h1
                }

                Button {
                    text: "Show Scan Data"
                    onClicked: ScanPlot.showScanData()
                }
            }
        }
    }

    Connections {
        target: ScanPlot
        function onError(msg) { console.log("ScanPlot error:", msg) }
        function onLaunched() { console.log("Scan plot launched") }
    }
}
