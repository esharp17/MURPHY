import QtQuick 2.15
import QtQuick.Controls 2.15
import RobotUI 1.0

Rectangle {
    anchors.fill: parent
    color: Theme.panel
    radius: Theme.radius

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

    Connections {
        target: ScanPlot
        function onError(msg) { console.log("ScanPlot error:", msg) }
        function onLaunched() { console.log("Scan plot launched") }
    }
}
