
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import RobotUI 1.0

Rectangle {
    id: root
    color: Theme.panel
    radius: Theme.radius

    // ============================================================
    // TUNING KNOBS (edit these to move/size things)
    // ============================================================
    // Split: left 2/3, right 1/3
    property real splitLeftFrac: 0.65         // <<< adjust left/right split

    // Padding + gaps
    property int  outerPad: Theme.pad            // <<< overall padding inside this screen
    property int  gap: Theme.gap                 // <<< spacing between major panes

    // Ring sizing
    property real ringFrac: 0.62                 // <<< ring diameter as fraction of LEFT pane min dimension
    property real ringMarginFrac: 0.02           // <<< room around ring inside ringArea

    // Robot panel sizing & placement (critical)
    property real panelWFrac: 0.28               // <<< panel width as fraction of ringArea width
    property real panelHFrac: 0.20               // <<< panel height as fraction of ringArea height
 
    // Robot panel internal control sizes
    property real panelBtnHFrac: 0.28            // <<< button height fraction within panel
    property real panelBtnWFrac: 0.46            // <<< left/right control tile width fraction within panel
    // ============================================================

    // ---------- wire later ----------
    property bool door1Open: false
    property bool door2Open: false
    property bool floorOpen: false
    property bool fansOn: true
    property bool lightsOn: true

    ListModel {
        id: robots
        ListElement { name: "Robot 1"; pos:  45; timeLeft: "4:28"; state: "welding" }
        ListElement { name: "Robot 2"; pos: 135; timeLeft: "2:11"; state: "ready" }
        ListElement { name: "Robot 3"; pos: 225; timeLeft: "0:54"; state: "paused" }
        ListElement { name: "Robot 4"; pos: 315; timeLeft: "6:02"; state: "faulted" }
    }

    ListModel {
        id: messageModel
    }
    // -------------------------------

    function norm360(v) {
        var x = v % 360
        if (x < 0) x += 360
        return x
    }

    function stateLabel(s) {
        if (s === "ready")   return "READY"
        if (s === "welding") return "WELDING"
        if (s === "faulted") return "FAULT"
        if (s === "paused")  return "PAUSED"
        return "DISABLED"
    }

    function stateColor(s) {
        // Hardcoded until Theme has equivalents.
        if (s === "ready")   return "#1fbf4a"
        if (s === "welding") return "#1f6bff"
        if (s === "faulted") return "#e53935"
        if (s === "paused")  return "#f2c94c"
        return "#8a8a8a"
    }

    // ======================================================
    // MAIN SPLIT: LEFT 2/3 and RIGHT 1/3
    // ======================================================


    Row {
        anchors.fill: parent
        anchors.margins: outerPad                   // <<< overall inset from screen edges
        spacing: gap                                // <<< gap between left and right panes

        // ======================================================
        // LEFT PANE: ring + four robot panels (no top bar here)
        // ======================================================
        Item {
            id: leftPane
            width: Math.floor((root.width - (outerPad * 2) - gap) * splitLeftFrac)  // <<< split control
            height: parent.height

            // This central "ringArea" is the coordinate space for ring + panels.
            Item {
                id: ringArea
                anchors.centerIn: parent
                width: Math.min(leftPane.width, leftPane.height)                    // base square
                height: width

                // Ring diameter derived from ringFrac
                readonly property real ringDiam: Math.min(width, height) * ringFrac  // <<< ring size control
                readonly property real ringX: (width - ringDiam) * 0.5
                readonly property real ringY: (height - ringDiam) * 0.5

                // Panel size derived from fractions of ringArea
                readonly property real panelW: width * panelWFrac                    // <<< panel width control
                readonly property real panelH: height * panelHFrac                   // <<< panel height control


// Put these 4 readonly properties INSIDE ringArea (same scope as ringDiam/panelW/panelH):
readonly property real ringCenterX: width * 0.5
readonly property real ringCenterY: height * 0.5
readonly property real ringRadius:  ringDiam * 0.48        // must match Canvas r = width*0.48
readonly property real panelOffset: Math.min(width, height) * 0.33
// Panel placement: distance from ring center as a multiple of ringRadius
readonly property real panelRadiusFactor: 1.20
readonly property real panelRadius: ringRadius * panelRadiusFactor


// ==================================================
// 4-ROBOT GRAPHIC (replaces center ring canvas)
// ==================================================
Item {
    id: robotGraphic
    x: ringArea.ringX
    y: ringArea.ringY
    width: ringArea.ringDiam
    height: ringArea.ringDiam

    // Match your test harness scaling to the cell-status ring size
    readonly property real ringDiam: width
    readonly property real baseX: ringDiam * 0.6
    readonly property real baseY: ringDiam * 0.070
    readonly property real l1Def: ringDiam * 0.35
    readonly property real l2Def: ringDiam * 0.4

    // Local "ringArea" values (for IK math)
    readonly property real cx: width * 0.5
    readonly property real cy: height * 0.5
    readonly property real ringR: width * 0.35     // matches your old ringR
    readonly property real pathR: width * 0.46

    // Optional: draw the ring behind the robots (if you still want a faint circle)
    Canvas {
        id: faintRing
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.strokeStyle = Theme.text
            ctx.globalAlpha = 0.35
            ctx.lineWidth = Math.max(2, width * 0.010)
            ctx.beginPath()
            ctx.arc(width * 0.5, height * 0.5, robotGraphic.ringR, 0, Math.PI * 2, false)
            ctx.stroke()
            ctx.globalAlpha = 1.0
        }
    }


    // =========================
    // ARM COMPONENT (instanced 4x)
    // =========================
    Component {
        id: robotArm

        Item {
            id: arm
            anchors.fill: parent

            // per-robot inputs
            property int sx: 1
            property int sy: 1
            property int quadrant: 0
            property bool elbowUp: false

            // bound from robot list (0..360, 0=12 o'clock expected by your status screen)
            property real posDeg: 0

            // geometry inputs
            property real bx: robotGraphic.cx + sx * robotGraphic.baseX
            property real by: robotGraphic.cy + sy * robotGraphic.baseY
            property real l1: robotGraphic.l1Def
            property real l2: robotGraphic.l2Def

            // map 0°=12 o'clock, clockwise positive -> standard math angle
            // standard: 0° is +X. We want 0° at -Y. So subtract 90.
            property real rad: (posDeg - 90) * Math.PI / 180.0

            // target point on path circle
            property real tx: robotGraphic.cx + Math.cos(rad) * robotGraphic.pathR
            property real ty: robotGraphic.cy + Math.sin(rad) * robotGraphic.pathR

            // IK solve
            property real dx: tx - bx
            property real dy: ty - by
            property real dRaw: Math.sqrt(dx * dx + dy * dy)

            property real dMin: Math.abs(l1 - l2) + 0.0001
            property real dMax: (l1 + l2) - 0.0001
            property real d: Math.max(dMin, Math.min(dMax, dRaw))

            property real c2: (d * d - l1 * l1 - l2 * l2) / (2 * l1 * l2)
            property real c2c: Math.max(-1, Math.min(1, c2))
            property real s2mag: Math.sqrt(Math.max(0, 1 - c2c * c2c))
            property real s2: elbowUp ? -s2mag : s2mag

            property real th2: Math.atan2(s2, c2c)
            property real th1: Math.atan2(dy, dx) - Math.atan2(l2 * s2, l1 + l2 * c2c)

            property real deg1: th1 * 180.0 / Math.PI
            property real deg2: th2 * 180.0 / Math.PI

            // forward-kin tip (for torch aim)
            property real tipWX: bx + Math.cos(th1) * l1 + Math.cos(th1 + th2) * l2
            property real tipWY: by + Math.sin(th1) * l1 + Math.sin(th1 + th2) * l2
            property real aimRadW: Math.atan2(robotGraphic.cy - tipWY, robotGraphic.cx - tipWX)
            property real aimDegW: aimRadW * 180.0 / Math.PI
            property real link2DegW: (th1 + th2) * 180.0 / Math.PI

            // “moving” detector based on posDeg changing
            property real _lastPos: posDeg
            property bool isMoving: false

            Timer {
                id: moveTimeout
                interval: 1000          // 1s idle -> not moving
                repeat: false
                onTriggered: arm.isMoving = false
            }

            onPosDegChanged: {
                arm.isMoving = true
                moveTimeout.restart()
            }

            // ---- base marker ----
            Rectangle {
                width: 80
                height: 60
                radius: 16
                color: "grey"
                x: arm.bx - width / 2
                y: arm.by - height / 2
                opacity: 0.6
            }

            // ---- target marker ----
            Rectangle {
                width: 30
                height: 30
                radius: 15
                color: "#ebeb34"
                x: arm.tx - 15
                y: arm.ty - 15
                opacity: 0.9
            }

            // link1 at base
            Item {
                id: link1
                x: arm.bx
                y: arm.by
                width: 1
                height: 1

                transform: Rotation { origin.x: 0; origin.y: 0; angle: arm.deg1 }

                Rectangle {
                    width: 44
                    height: 44
                    radius: 22
                    color: "#ebeb34"
                    x: -22
                    y: -22
                }

                Rectangle {
                    height: 45
                    width: arm.l1
                    radius: 15
                    color: "#ebeb34"
                    x: 0
                    y: -height / 2
                }

                // link2 at elbow
                Item {
                    id: link2
                    x: arm.l1
                    y: 0
                    width: 1
                    height: 1

                    transform: Rotation { origin.x: 0; origin.y: 0; angle: arm.deg2 }

                    Rectangle {
                        width: 44
                        height: 44
                        radius: 10
                        color: "#ebeb34"
                        x: -22
                        y: -22
                    }

                    Rectangle {
                        height: 30
                        width: arm.l2
                        radius: 15
                        color: "#ebeb34"
                        x: 0
                        y: -height / 2
                    }

                    // tip marker
                    Rectangle {
                        width: 26
                        height: 26
                        radius: 13
                        color: "black"
                        x: arm.l2 - width / 2
                        y: -height / 2
                        z: 5
                    }

                    // torch at tip, points to ring center
                    Item {
                        id: torch
                        x: arm.l2
                        y: 0
                        width: 1
                        height: 1

                        transform: Rotation {
                            origin.x: 0
                            origin.y: 0
                            angle: arm.aimDegW - arm.link2DegW
                        }

                        Rectangle {
                            width: 60
                            height: 10
                            radius: 5
                            color: "#A15C2F"
                            x: 0
                            y: -height / 2
                            z: 2
                        }

                        // glow only while moving
                        Rectangle {
                            width: arm.isMoving ? 12 : 0
                            height: arm.isMoving ? 12 : 0
                            radius: 6
                            color: "white"
                            x: 56
                            y: -height / 2 - 1
                            z: 4
                        }

                        Rectangle {
                            width: arm.isMoving ? 18 : 0
                            height: arm.isMoving ? 18 : 0
                            radius: 9
                            color: "cyan"
                            x: 56
                            y: -height / 2 - 1
                            z: 3
                        }
                    }
                }
            }
        }
    }

    // =========================
    // 4 ROBOTS, bound to robots[i].pos
    // =========================
    Repeater {
        model: [
            { sx: +1, sy: -1, elbowUp: true }, // R1: Down
            { sx: +1, sy: +1, elbowUp: false  }, // R2: Up
            { sx: -1, sy: +1, elbowUp: true }, // R3: Down
            { sx: -1, sy: -1, elbowUp: false  }  // R4: Up
        ]

Loader {
    sourceComponent: robotArm

    onLoaded: {
        item.sx = modelData.sx
        item.sy = modelData.sy
        item.elbowUp = modelData.elbowUp
    }

Binding {
    target: item
    property: "posDeg"
    when: item
    value: {
        var r = robots.get(index)
        return r ? root.norm360(r.pos) : 0
    }
}


}


    }
}

                }

                // ==================================================
                // ROBOT PANEL COMPONENT
                // ==================================================
                Component {
                    id: robotPanel

                    Rectangle {
                        id: p
                        width: ringArea.panelW
                        height: ringArea.panelH
                        radius: Theme.radius
                        color: Theme.sideBtnpanel
                        border.color: Theme.text
                        border.width: 1
                        clip: true

                        property string name: ""
                        property int pos: 0
                        property string timeLeft: "0:00"
                        property string state: "ready"

                        // ---- top row: C-STOP + STATUS INDICATOR ----
                        Row {
                            id: topRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Theme.padSm
                            height: parent.height * panelBtnHFrac
                            spacing: Theme.padSm

                            Rectangle {
                                id: cstop
                                width: (parent.width - parent.spacing) * 0.5
                                height: parent.height
                                radius: Theme.radiusSm
                                color: Theme.panel
                                border.width: 2
                                border.color: Theme.danger

                                Text {
                                    anchors.centerIn: parent
                                    text: "C-STOP"
                                    color: Theme.danger
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.caption
                                    font.bold: true
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: console.log("C-STOP pressed for " + p.name)
                                }
                            }

                            Rectangle {
                                id: status
                                width: (parent.width - parent.spacing) * 0.5
                                height: parent.height
                                radius: Theme.radiusSm
                                color: root.stateColor(p.state)

                                SequentialAnimation on opacity {
                                    running: (p.state === "faulted")
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.55; duration: 700 }
                                    NumberAnimation { to: 1.0;  duration: 700 }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: root.stateLabel(p.state)
                                    color: Theme.panel
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.caption
                                    font.bold: true
                                }
                            }
                        }

                        // ---- bottom: readouts ----
                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: topRow.bottom
                            anchors.bottom: parent.bottom
                            anchors.margins: Theme.padSm
                            text: p.name + "\nPos: " + Math.round(root.norm360(p.pos)) + "\nTime Left: " + p.timeLeft
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.caption
                            wrapMode: Text.WordWrap
                        }
                    }
                }

// Panel offsets relative to ring center (YOU tune these)

Loader {
    id: panelTL
    sourceComponent: robotPanel
    visible: robots.count > 0
    onLoaded: {
        var r = robots.get(0)
        item.name = r.name
        item.pos = r.pos
        item.timeLeft = r.timeLeft
        item.state = r.state
    }
    Binding { target: panelTL.item; property: "x"; value: ringArea.width * 0.01; when: panelTL.item }
    Binding { target: panelTL.item; property: "y"; value: ringArea.height * 0.01; when: panelTL.item }
}

Loader {
    id: panelBL
    sourceComponent: robotPanel
    visible: robots.count > 1
    onLoaded: {
        var r = robots.get(1)
        item.name = r.name
        item.pos = r.pos
        item.timeLeft = r.timeLeft
        item.state = r.state
    }
    Binding { target: panelBL.item; property: "x"; value: ringArea.width - ringArea.panelW - ringArea.width * 0.01; when: panelBL.item }
    Binding { target: panelBL.item; property: "y"; value: ringArea.height * 0.01; when: panelBL.item }
}

Loader {
    id: panelTR
    sourceComponent: robotPanel
    visible: robots.count > 2
    onLoaded: {
        var r = robots.get(2)
        item.name = r.name
        item.pos = r.pos
        item.timeLeft = r.timeLeft
        item.state = r.state
    }
    Binding { target: panelTR.item; property: "x"; value: ringArea.width * 0.01; when: panelTR.item }
    Binding { target: panelTR.item; property: "y"; value: ringArea.height - ringArea.panelH - ringArea.height * 0.01; when: panelTR.item }
}

Loader {
    id: panelBR
    sourceComponent: robotPanel
    visible: robots.count > 3
    onLoaded: {
        var r = robots.get(3)
        item.name = r.name
        item.pos = r.pos
        item.timeLeft = r.timeLeft
        item.state = r.state
    }
    Binding { target: panelBR.item; property: "x"; value: ringArea.width - ringArea.panelW - ringArea.width * 0.01; when: panelBR.item }
    Binding { target: panelBR.item; property: "y"; value: ringArea.height - ringArea.panelH - ringArea.height * 0.01; when: panelBR.item }
}


}
      // ======================================================
        // RIGHT PANE: indicator grid (top) + message window (bottom)
        // ======================================================
        Rectangle {
            id: rightPane
            width: (root.width - (outerPad * 2) - gap) - leftPane.width
            height: parent.height
            radius: Theme.radius
            color: "transparent"

            ColumnLayout {
                anchors.fill: parent
                spacing: Theme.gap

                // -------- indicators (upper half) --------
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: rightPane.height * 0.45
                    radius: Theme.radius
                    color: Theme.sideBtnpanel

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.pad
                        spacing: Theme.gap

                        Text {
                            text: "Cell I/O"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.body
                            font.bold: true
                        }

                        Component {
                            id: indicatorTile
                            Rectangle {
                                id: t
                                radius: Theme.radius * 0.6
                                color: Theme.panel
                                border.color: Theme.text
                                border.width: 1

                                property string label: ""
                                property bool on: false
                                property string onText: "ON"
                                property string offText: "OFF"

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.padSm
                                    spacing: 2
                                                
                                    // TOP LINE — label (bold)
                                    Text {
                                        text: t.label
                                        color: Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.body
                                        font.bold: true
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                    }

                                    // BOTTOM LINE — state (OPEN / CLOSED)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.gap
                                        Layout.alignment: Qt.AlignHCenter

                                        Rectangle {
                                            width: 10
                                            height: 10
                                            radius: 5
                                            color: t.on ? "#1fbf4a" : "#8a8a8a"
                                        }

                                        Text {
                                            text: t.on ? t.onText : t.offText
                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.bodySm
                                        }
                                    }
                                }
                            }
                        }


                        GridLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            columns: 2
                            rowSpacing: Theme.gap
                            columnSpacing: Theme.gap

                            Loader {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                sourceComponent: indicatorTile
                                onLoaded: { item.label = "Door 1"; item.onText = "OPEN"; item.offText = "CLOSED"; item.on = root.door1Open }
                            }
                            Loader {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                sourceComponent: indicatorTile
                                onLoaded: { item.label = "Door 2"; item.onText = "OPEN"; item.offText = "CLOSED"; item.on = root.door2Open }
                            }
                            Loader {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                sourceComponent: indicatorTile
                                onLoaded: { item.label = "Floor"; item.onText = "OPEN"; item.offText = "CLOSED"; item.on = root.floorOpen }
                            }
                            Loader {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                sourceComponent: indicatorTile
                                onLoaded: { item.label = "Fans"; item.onText = "ON"; item.offText = "OFF"; item.on = root.fansOn }
                            }
                            Loader {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                sourceComponent: indicatorTile
                                onLoaded: { item.label = "Lights"; item.onText = "ON"; item.offText = "OFF"; item.on = root.lightsOn }
                            }
                        }
                    }
                }

                // -------- message window (lower half) --------
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radius
                    color: Theme.sideBtnpanel

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.pad
                        spacing: Theme.gap

                        Text {
                            text: "Messages / Alarms"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.body
                            font.bold: true
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Theme.radius * 0.6
                            color: Theme.panel
                            border.color: Theme.text
                            border.width: 1

                            ListView {
                                anchors.fill: parent
                                anchors.margins: Theme.pad
                                model: messageModel
                                clip: true
                                spacing: 8

                                delegate: Rectangle {
                                    width: ListView.view.width
                                    height: 42
                                    radius: Theme.radius * 0.5
                                    color: Theme.sideBtnpanel

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: Theme.pad
                                        spacing: Theme.gap

                                        Text {
                                            text: ts
                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.caption
                                            Layout.preferredWidth: 70
                                        }

                                        Text {
                                            text: level
                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.caption
                                            font.bold: true
                                            Layout.preferredWidth: 60
                                        }

                                        Text {
                                            text: text
                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.caption
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
