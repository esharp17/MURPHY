import QtQuick 2.15
import QtQuick.Controls 2.15
import RobotUI 1.0

Rectangle {
    id: tabs

    property int currentIndex: 0
    signal tabSelected(int index)

    // Colors match tab order.
    // If labels length changes, activeColor clamps safely.
    property var tabColors: [
        "#3b82f6", // Splash/Admin
        "#22c55e", // Robot
        "#f59e0b", // Status
        "#a855f7"  // Weld
    ]

    // Default labels; Main.qml can override (and should).
    // Keep 4 tabs now (Splash/Admin combined).
    property var labels: ["Splash", "Robot", "Status", "Weld"]

    readonly property int tabCount: (labels && labels.length > 0) ? labels.length : 0
    readonly property int safeIndex: tabCount > 0 ? Math.min(Math.max(currentIndex, 0), tabCount - 1) : 0
    property color activeColor: tabCount > 0 ? tabColors[Math.min(safeIndex, tabColors.length - 1)] : "#3b82f6"

    height: 92
    radius: Theme.radius
    color: "transparent"

    Row {
        id: row
        anchors.fill: parent
        anchors.margins: Theme.gap
        spacing: Theme.gap

        Repeater {
            model: tabs.tabCount

            delegate: Button {
                property int idx: model.index

                text: tabs.labels[idx]
                width: (row.width - (row.spacing * (tabs.tabCount - 1))) / tabs.tabCount
                height: row.height

                font.family: Theme.fontFamily
                font.pixelSize: Theme.tabFont

                background: Rectangle {
                    radius: Theme.radius

                    // Clamp color index in case tabColors length differs.
                    readonly property color base: tabs.tabColors[Math.min(idx, tabs.tabColors.length - 1)]

                    color: (tabs.safeIndex === idx)
                           ? base
                           : Qt.darker(base, 1.45)

                    border.width: (tabs.safeIndex === idx) ? 0 : 2
                    border.color: "#2a3442"
                }

                contentItem: Text {
                    text: parent.text
                    color: (tabs.safeIndex === idx) ? "white" : Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.body
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 6
                }

                onClicked: tabs.tabSelected(idx)
            }
        }
    }
}
