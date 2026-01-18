import QtQuick 2.15
import QtQuick.Controls 2.15

ApplicationWindow {
    id: win
    width: 900
    height: 700
    visible: true
    title: "4-Robot IK Ring Test"

    Rectangle {
        id: root
        anchors.fill: parent
        color: "#1e1e1e"

        // =========================
        // HARD-CODED DEFAULTS (relative to ring diameter)
        // =========================
        readonly property real ringDiam: ringArea.width
        readonly property real baseX: ringDiam * 0.6    // ~278 @ ringDiam ≈ 675
        readonly property real baseY: ringDiam * 0.070    // ~35  @ ringDiam ≈ 675
        readonly property real l1Def: ringDiam * 0.35    // ~184 @ ringDiam ≈ 675
        readonly property real l2Def: ringDiam * 0.4    // ~211 @ ringDiam ≈ 675

        // shared local position (1..90) per quadrant
        Slider {
            id: posSlider
            from: 1
            to: 90
            value: 1
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 20
        }

        Text {
            color: "white"
            text: "posDeg (local 1..90): " + Math.round(posSlider.value)
            anchors.left: posSlider.left
            anchors.bottom: posSlider.top
            anchors.bottomMargin: 6
        }

        // =========================
        // RING AREA (DRAW SPACE)
        // =========================
        Item {
            id: ringArea
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * 0.75
            height: width

            property real cx: width * 0.5
            property real cy: height * 0.5
            property real ringR: width * 0.35
            property real pathR: width * 0.46
        }

        Canvas {
            id: ring
            x: ringArea.x
            y: ringArea.y
            width: ringArea.width
            height: ringArea.height

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = "white"
                ctx.globalAlpha = 0.6
                ctx.lineWidth = 3
                ctx.beginPath()
                ctx.arc(width * 0.5, height * 0.5, ringArea.ringR, 0, Math.PI * 2, false)
                ctx.stroke()
                ctx.globalAlpha = 1.0
            }
        }

        // repaint ring if resized
        onWidthChanged: ring.requestPaint()
        onHeightChanged: ring.requestPaint()

        // =========================
        // ARM COMPONENT (instanced 4x)
        // =========================
        Component {
            id: robotArm

            Item {
                id: arm
                x: ringArea.x
                y: ringArea.y
                width: ringArea.width
                height: ringArea.height

                // per-robot inputs
                property int sx: 1
                property int sy: 1
                property int quadrant: 0               // 0..3
                property bool elbowUp: false

                // geometry inputs (bound from root)
                property real bx: ringArea.cx + sx * root.baseX
                property real by: ringArea.cy + sy * root.baseY
                property real l1: root.l1Def
                property real l2: root.l2Def

                // local pos (1..90) mapped into global degrees
                property real localDeg: posSlider.value
                property real posDeg: quadrant * 90 + localDeg
                property real rad: posDeg * Math.PI / 180.0

                // target point on path circle
                property real tx: ringArea.cx + Math.cos(rad) * ringArea.pathR
                property real ty: ringArea.cy + Math.sin(rad) * ringArea.pathR

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

                // forward-kin tip (for torch aim, works even when clamped)
                property real tipWX: bx + Math.cos(th1) * l1 + Math.cos(th1 + th2) * l2
                property real tipWY: by + Math.sin(th1) * l1 + Math.sin(th1 + th2) * l2
                property real aimRadW: Math.atan2(ringArea.cy - tipWY, ringArea.cx - tipWX)
                property real aimDegW: aimRadW * 180.0 / Math.PI
                property real link2DegW: (th1 + th2) * 180.0 / Math.PI
                property real lastPos: posSlider.value
                property bool isMoving: false

                Timer {
                    id: moveTimeout
                    interval: 500
                    repeat: false
                    onTriggered: arm.isMoving = false
                }

                Connections {
                    target: posSlider
                    function onValueChanged() {
                        // treat any change as "moving"
                        arm.isMoving = true
                        moveTimeout.restart()
                    }
                }


                // debug markers
                Rectangle {
                    width: 80
                    height: 60
                    radius: 16
                    color: "grey"
                    x: arm.bx - width / 2
                    y: arm.by - height / 2
                }

                Rectangle {
                    width: 30
                    height: 30
                    radius: 15
                    color: "#ebeb34"
                    x: arm.tx - 15
                    y: arm.ty - 15
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

                            Rectangle {
                                width:  arm.isMoving ? 12 : 0
                                height:  arm.isMoving ? 12 : 0
                                radius: 6
                                color: arm.isMoving ? "white" : "grey"
                                x: 56
                                y: -height / 2 - 1
                                z: 4
                            }

                            Rectangle {
                                width:  arm.isMoving ? 18 : 0
                                height:  arm.isMoving ? 18 : 0
                                radius: 9
                                color: arm.isMoving ? "cyan" : "grey"
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
        // 4 ROBOTS (quadrants + mirrored bases)
        // +/- pattern matches your working quadrant mapping
        // Elbows: Down UP Down UP
        // =========================
        Repeater {
            model: [
                { sx: +1, sy: +1, quadrant: 0, elbowUp: false }, // R1: Down
                { sx: -1, sy: +1, quadrant: 1, elbowUp: true  }, // R2: Up
                { sx: -1, sy: -1, quadrant: 2, elbowUp: false }, // R3: Down
                { sx: +1, sy: -1, quadrant: 3, elbowUp: true  }  // R4: Up
            ]

            Loader {
                sourceComponent: robotArm
                onLoaded: {
                    item.sx = modelData.sx
                    item.sy = modelData.sy
                    item.quadrant = modelData.quadrant
                    item.elbowUp = modelData.elbowUp
                }
            }
        }
    }
}
