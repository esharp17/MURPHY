import QtQuick 2.15
import QtQuick.Controls 2.15
import RobotUI 1.0

Rectangle {
    id: tabs

    property int currentIndex: 0
    signal tabSelected(int index)

    // Blue color scheme for all tabs
    property color tabSelectedColor: "#3b82f6"    // Lighter blue (selected, matches border)
    property color tabUnselectedColor: "#1e3a5f"  // Darker blue (unselected)
    property color tabDisabledColor: "#2a3040"    // Greyed out (inaccessible)
    property color tabDisabledText: "#555e6e"     // Greyed out text

    // Current user role for permission checking
    property int sessionRole: 0

    // Default labels; Main.qml can override (and should).
    // Keep 4 tabs now (Splash/Admin combined).
    property var labels: ["Splash", "Robot", "Status", "Weld"]

    readonly property int tabCount: (labels && labels.length > 0) ? labels.length : 0
    readonly property int safeIndex: tabCount > 0 ? Math.min(Math.max(currentIndex, 0), tabCount - 1) : 0
    property color activeColor: tabSelectedColor

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

            delegate: InteractiveSurface {
                property int idx: model.index
                readonly property bool accessible: (typeof PermissionChecker !== "undefined" && PermissionChecker !== null) ? PermissionChecker.canAccessPage(idx, tabs.sessionRole) : true

                width: (row.width - (row.spacing * (tabs.tabCount - 1))) / tabs.tabCount
                height: row.height
                enabled: accessible
                active: tabs.safeIndex === idx

                normalColor: tabs.tabUnselectedColor
                pressedColor: tabs.tabSelectedColor
                disabledColor: tabs.tabDisabledColor
                borderWidth: (tabs.safeIndex === idx) ? 3 : 1
                borderColor: (tabs.safeIndex === idx)
                             ? tabs.tabSelectedColor
                             : !accessible
                               ? "#3a3f4a"
                               : "#2a4a6a"

                onClicked: tabs.tabSelected(idx)

                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 6
                    text: tabs.labels[idx]
                    color: !accessible
                           ? tabs.tabDisabledText
                           : (tabs.safeIndex === idx) ? "#ffffff" : "#8891a8"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.body
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }
        }
    }
}
