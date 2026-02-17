import QtQuick 2.15
import RobotUI 1.0

Item {
    id: root

    property alias radius: bg.radius
    property alias borderWidth: bg.border.width
    property alias borderColor: bg.border.color

    property color normalColor: Theme.btnNormal
    property color pressedColor: Theme.btnPressed
    property color disabledColor: Theme.btnDisabled
    property color glowColor: Theme.accent

    property bool enabled: true
    property bool latched: false
    property bool active: false

    signal clicked()
    signal pressed()
    signal released()

    default property alias content: contentItem.data

    implicitWidth: 160
    implicitHeight: Theme.btnH

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: Theme.radius
        color: !root.enabled
               ? root.disabledColor
               : (mouse.pressed || root.active)
                 ? root.pressedColor
                 : root.normalColor
        border.width: 2
        border.color: Theme.border

        Behavior on color {
            ColorAnimation { duration: Theme.animationFast }
        }
    }

    Rectangle {
        id: glow
        anchors.fill: parent
        radius: bg.radius
        color: root.glowColor
        opacity: (mouse.pressed || root.active) ? 0.22 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.animationFast }
        }
    }

    Item {
        id: contentItem
        anchors.fill: parent
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.enabled
        onPressed: root.pressed()
        onReleased: root.released()
        onClicked: root.clicked()
    }
}
