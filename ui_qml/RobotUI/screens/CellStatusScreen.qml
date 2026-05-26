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
    property real splitLeftFrac: 0.65

    // Padding + gaps
    property int outerPad: Theme.pad
    property int gap: Theme.gap

    // Ring sizing
    property real ringFrac: 0.62
    property real ringMarginFrac: 0.02

    // Robot panel sizing & placement
    property real panelWFrac: 0.38
    property real panelHFrac: 0.40

    // Robot panel internal control sizes
    property real panelBtnHFrac: 0.16
    property real panelBtnWFrac: 0.46
    
    // Ring horizontal offset (positive = right, negative = left)
    property real ringOffsetX: 80  // <-- NEW: shift ring to the right
    // ============================================================

    // ---------- wire later ----------
    property bool door1Open: false
    property bool door2Open: false
    property bool floorOpen: false
    property bool fansOn: true
    property bool lightsOn: true

    // ============================================================
    // ALARMS (bits 40..60)
    // Alarm definitions come from a JSON file.
    // ============================================================

    //JSON file location RobotUI/assets/alarms.json
    property url alarmCatalogUrl: Qt.resolvedUrl("../assets/alarms.json")

    // Loaded catalog (bitNumber -> {name, desc, severity, stop, textColor})
    property var alarmCatalog: ({})

    function loadAlarmCatalog() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", alarmCatalogUrl)
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return

            if (xhr.status === 200) {
                try {
                    var txt = xhr.responseText || ""
                    // optional: strip UTF-8 BOM (common)
                    if (txt.length && txt.charCodeAt(0) === 0xFEFF) txt = txt.slice(1)

                    var obj = JSON.parse(txt)
                    alarmCatalog = (obj.alarms ? obj.alarms : obj)
                    console.log("[QML] alarmCatalog loaded:", Object.keys(alarmCatalog).length, "entries")
                } catch (e) {
                    console.log("[QML] alarmCatalog JSON parse failed:", e)
                    console.log("[QML] alarmCatalog url:", alarmCatalogUrl)
                    console.log("[QML] alarmCatalog resp len:", (xhr.responseText ? xhr.responseText.length : 0))
                    console.log("[QML] alarmCatalog resp head:", (xhr.responseText ? xhr.responseText.slice(0, 200) : "<empty>"))
                }

            } else {
                console.log("[QML] alarmCatalog load failed:", xhr.status, alarmCatalogUrl)
                console.log("[QML] alarmCatalog resp head:", (xhr.responseText ? xhr.responseText.slice(0, 200) : "<empty>"))
            }

            rebuildAlarms()
        }
        xhr.send()
    }

    Component.onCompleted: {
        loadAlarmCatalog()
    }

    ListModel {
        id: alarmModel2
    }

    function alarmLevel(sev) {
        if (sev === "Fault")
            return "ALARM"

        if (sev === "Warning")
            return "WARN"

        return "INFO"
    }

    function rebuildAlarms() {
        alarmModel2.clear()

        // bits 40..60 inclusive
        for (var b = 40; b <= 60; b++) {
            if (!getBit(ioInWords, b))
                continue

            var def = alarmCatalog[String(b)]
            if (!def)
                def = { name: "Alarm " + b, desc: "Active", severity: "Fault", stop: "NONE", textColor: Theme.text }

            var tc = def.textColor
            if (tc === undefined || tc === null || tc === "")
                tc = Theme.text

            tc = "" + tc

            alarmModel2.append({
                ts: "", // placeholder for later timestamping
                level: alarmLevel(def.severity),
                text: "(" + b + ") " + def.name + " — " + def.desc + "  [Stop: " + def.stop + "]",
                textColorStr: tc
            })
        }
    }

    // -------------------------------

    function norm360(v) {
        var x = v % 360
        if (x < 0)
            x += 360
        return x
    }

    function stateLabel(s) {
        if (s === "ready")
            return "READY"

        if (s === "welding")
            return "WELDING"

        if (s === "faulted")
            return "FAULT"

        if (s === "paused")
            return "PAUSED"

        return "DISABLED"
    }

    function stateColor(s) {
        // Hardcoded until Theme has equivalents.
        if (s === "ready")
            return "#1fbf4a"

        if (s === "welding")
            return "#1f6bff"

        if (s === "faulted")
            return "#e53935"

        if (s === "paused")
            return "#f2c94c"

        return "#8a8a8a"
    }

    // ============================================================
    // LIVE POSITION (from robot I/O)
    // Robot outputs a 16-bit value (1..360) starting at BIT 65.
    // Bit 65 is the LSB of WORD INDEX 4 (bits 65..80).
    // Wire `ioInWords` from your RobotCommBridge input word array.
    // ============================================================
    property var ioInWords: []

    readonly property int posWordIndex: 4

    // ============================================================
    // ROBOT SPEED (0–100%)
    // 16-bit value starting at bit 145 (1-based)
    // bit 145 => word index 9, bits 145..160
    // ============================================================
    readonly property int speedWordIndex: Math.floor((145 - 1) / 16)

    function readSpeedPctFromWords(words) {
        if (!words || words.length <= speedWordIndex)
            return 0

        var v = words[speedWordIndex] & 0xFFFF
        if (v < 0)
            v = 0

        if (v > 100)
            v = 100

        return v
    }

    readonly property int robotSpeedPct: readSpeedPctFromWords(ioInWords)

    function readPosDegFromWords(words) {
        if (!words || words.length <= posWordIndex)
            return 0

        var w = words[posWordIndex] & 0xFFFF

        // expected 1..360; clamp + wrap defensively
        if (w === 0)
            return 0

        if (w > 360)
            w = w % 360

        if (w === 0)
            w = 360

        return w
    }

    // Single-source position for now. Replace with per-robot word arrays when you add them.
    readonly property int livePosDeg: readPosDegFromWords(ioInWords)

    onLivePosDegChanged: {
        console.log("[QML] livePosDeg:", livePosDeg)
    }

    Connections {
        target: robotComm

        function onInWordsChanged() {
            // Copy to a QML-owned array so bindings re-evaluate reliably
            ioInWords = robotComm.in_words
            rebuildAlarms()
        }
    }

    // ============================================================
    // PANEL STATUS LOGIC (single robot for now)
    // Priority:
    //   Any Fault = Faulted
    //   DO 11 ON = Welding
    //   Cell in AUTO, no fault = Ready
    //   Cell NOT in AUTO, no fault = Paused
    // ============================================================

    // NOTE: These are BIT NUMBERS (1-based). Adjust if your mapping differs.
    property int bit_DO11_WELDING: 11
    property int bit_CELL_AUTO: 1
    property int bit_ANY_FAULT: 6

    // Weld enable feedback (read from robot input bit 14)
    property int bit_WELD_ENABLE_FB: 14

    function getBit(words, bit1) {
        if (!words || bit1 <= 0)
            return false

        var wi = Math.floor((bit1 - 1) / 16)
        var bi = (bit1 - 1) % 16
        if (wi < 0 || wi >= words.length)
            return false

        var w = words[wi] & 0xFFFF
        return ((w >> bi) & 1) === 1
    }

    readonly property bool stWelding: getBit(ioInWords, bit_DO11_WELDING)
    readonly property bool stAuto:    getBit(ioInWords, bit_CELL_AUTO)
    readonly property bool stFault:   getBit(ioInWords, bit_ANY_FAULT)

    readonly property string panelState:
        stFault ? "faulted" : (stWelding ? "welding" : (stAuto ? "ready" : "paused"))

    readonly property bool stWeldEnabled: getBit(ioInWords, bit_WELD_ENABLE_FB)

    // ============================================================
    // C-STOP POPUP STATE
    // ============================================================
    property bool cStopActive: false
    property int cStopRobotIndex: 0
    property int cStopDesiredPos: 0
    property bool goHomeLoading: false
    property bool resumeWeldLoading: false

    // Quadrant limits per robot (with +/-10 deg tolerance)
    // Robot 0 = top-right (Q1: 0-90), Robot 1 = top-left (Q2: 90-180)
    // Robot 2 = bottom-left (Q3: 180-270), Robot 3 = bottom-right (Q4: 270-360)
    function quadrantMin(robotIdx) {
        var bases = [350, 80, 170, 260]
        return bases[Math.min(3, Math.max(0, robotIdx))]
    }
    function quadrantMax(robotIdx) {
        var caps = [100, 190, 280, 370]
        return caps[Math.min(3, Math.max(0, robotIdx))]
    }

    // Clamp position to quadrant limits (handles wrap-around)
    function clampToQuadrant(pos, robotIdx) {
        var mn = quadrantMin(robotIdx)
        var mx = quadrantMax(robotIdx)
        // Normalize to 0-360
        var p = pos % 360
        if (p < 0) p += 360

        // Handle wrap-around for robot 0 (350-100 crosses 0)
        if (mn > mx) {
            // e.g. 350..360..0..100
            if (p >= mn || p <= (mx % 360)) return p
            // clamp to nearest bound
            var distToMin = Math.min(Math.abs(p - mn), Math.abs(p - mn + 360), Math.abs(p - mn - 360))
            var distToMax = Math.min(Math.abs(p - (mx % 360)), Math.abs(p - (mx % 360) + 360))
            return distToMin < distToMax ? mn : (mx % 360)
        }
        if (p < mn) return mn
        if (p > mx) return mx
        return p
    }

    // Read current position from input bits 65-74 (10-bit integer in word 4)
    function readCurrentPos() {
        if (!ioInWords || ioInWords.length <= 4) return 0
        return ioInWords[4] & 0x03FF
    }

    // Write desired position to output bits 65-74 (word 4, lower 10 bits)
    function writeDesiredPos(robotIdx, pos) {
        var outs = robotComm ? robotComm.getOutputs(robotIdx) : []
        var w4 = (outs && outs.length > 4) ? (Number(outs[4]) & 0xFFFF) : 0
        // Clear lower 10 bits, set new value
        w4 = (w4 & 0xFC00) | (pos & 0x03FF)
        if (robotComm) robotComm.setOutputWord(robotIdx, 4, w4)
    }

    // Set/clear a single output bit (1-indexed)
    function setOutputBit(robotIdx, bit1, value) {
        var wi = Math.floor((bit1 - 1) / 16)
        var bi = (bit1 - 1) % 16
        var outs = robotComm ? robotComm.getOutputs(robotIdx) : []
        var w = (outs && outs.length > wi) ? (Number(outs[wi]) & 0xFFFF) : 0
        if (value)
            w = w | (1 << bi)
        else
            w = w & (~(1 << bi))
        if (robotComm) robotComm.setOutputWord(robotIdx, wi, w)
    }

    // Open C-Stop popup for a robot
    function openCStop(robotIdx) {
        cStopRobotIndex = robotIdx
        cStopDesiredPos = readCurrentPos()
        goHomeLoading = false
        resumeWeldLoading = false
        // Set output bit 20 high to tell robot c-stop triggered
        setOutputBit(robotIdx, 20, true)
        cStopActive = true
    }

    // ======================================================
    // MAIN SPLIT: LEFT and RIGHT
    // ======================================================
    Row {
        anchors.fill: parent
        anchors.margins: outerPad
        spacing: gap

        // ======================================================
        // LEFT PANE: ring + robots
        // ======================================================
        Item {
            id: leftPane
            width: Math.floor((root.width - (outerPad * 2) - gap) * splitLeftFrac)
            height: parent.height

            Item {
                id: ringArea
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: root.ringOffsetX  // <-- APPLY OFFSET HERE
                width: Math.min(leftPane.width, leftPane.height)
                height: width

                // Ring diameter derived from ringFrac
                readonly property real ringDiam: Math.min(width, height) * ringFrac
                readonly property real ringX: (width - ringDiam) * 0.5
                readonly property real ringY: (height - ringDiam) * 0.5

                // Panel size derived from fractions of ringArea
                readonly property real panelW: width * panelWFrac
                readonly property real panelH: height * panelHFrac

                // Center helpers
                readonly property real ringCenterX: width * 0.5
                readonly property real ringCenterY: height * 0.5
                readonly property real ringRadius: ringDiam * 0.48
                readonly property real panelRadiusFactor: 1.20
                readonly property real panelRadius: ringRadius * panelRadiusFactor

                // ==================================================
                // 4-ROBOT GRAPHIC
                // ==================================================
                Item {
                    id: robotGraphic
                    x: ringArea.ringX
                    y: ringArea.ringY
                    width: ringArea.ringDiam
                    height: ringArea.ringDiam

                    readonly property real ringDiam: width
                    readonly property real baseX: ringDiam * -0.1
                    readonly property real baseY: ringDiam * -0.55
                    readonly property real l1Def: ringDiam * 0.5
                    readonly property real l2Def: ringDiam * 0.55

                    readonly property real cx: width * 0.5
                    readonly property real cy: height * 0.5
                    readonly property real ringR: width * 0.35
                    readonly property real pathR: width * 0.46

                    Canvas {
                        id: faintRing
                        anchors.fill: parent
                        z: 5

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.strokeStyle = Theme.text
                            ctx.globalAlpha = 1
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
                            property bool elbowUp: true

                            // bound from robot list (0..360, 0=12 o'clock)
                            property real posDeg: 0

                            // geometry inputs
                            property real bx: robotGraphic.cx + sx * robotGraphic.baseX
                            property real by: robotGraphic.cy + sy * robotGraphic.baseY
                            property real l1: robotGraphic.l1Def
                            property real l2: robotGraphic.l2Def

                            // map 0°=12 o'clock, clockwise positive -> standard math angle
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

                            // "moving" detector based on posDeg changing
                            property bool isMoving: false

                            Timer {
                                id: moveTimeout
                                interval: 2000
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
                                    z: 1
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
                    // 4 ROBOTS
                    // =========================
                    Repeater {
                        model: [
                            { sx: +1, sy: -1, elbowUp: false }
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
                                value: root.norm360(root.livePosDeg)
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

                        property string name: ""
                        property int pos: 0
                        property string timeLeft: "0:00"
                        property string state: "ready"

                        // ---- top row: C-STOP + STATUS INDICATOR ----
                        InteractiveSurface {
                            id: cstop
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: Theme.pad
                            width: parent.width * panelBtnWFrac
                            height: parent.height * panelBtnHFrac
                            radius: Theme.radius * 0.6
                            normalColor: Theme.sideBtnBase
                            pressedColor: Theme.btnPressed
                            disabledColor: Theme.btnDisabled
                            borderWidth: 2
                            borderColor: Theme.border

                            Text {
                                anchors.centerIn: parent
                                text: "C-STOP"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSmall
                                font.bold: true
                            }

                            onClicked: {
                                root.openCStop(0)
                            }
                        }

                        Rectangle {
                            id: status
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Theme.pad
                            width: parent.width * panelBtnWFrac
                            height: parent.height * panelBtnHFrac
                            radius: Theme.radius * 0.6
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
                                font.pixelSize: Theme.fontSmall
                                font.bold: true
                            }
                        }

                        // ---- weld enable toggle (full width) ----
                        InteractiveSurface {
                            id: weldEnableBtn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: cstop.bottom
                            anchors.margins: Theme.pad
                            height: parent.height * panelBtnHFrac
                            radius: Theme.radius * 0.6
                            normalColor: root.stWeldEnabled ? "#3a3a3a" : "#bdbdbd"
                            pressedColor: Theme.btnPressed
                            disabledColor: Theme.btnDisabled
                            borderWidth: 2
                            borderColor: Theme.border

                            // Drive appearance from robot feedback, not local state
                            readonly property bool fb: root.stWeldEnabled

                            Text {
                                anchors.centerIn: parent
                                text: fb ? "Weld Enabled" : "Weld Disabled"
                                color: fb ? "#1fbf4a" : "#000000"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSmall
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }

                            onClicked: {
                                // Toggle output bit 14 on robot (single robot for now)
                                var desired = !fb

                                // Bit numbers are 1-based; bit 14 => word 0, bit 13
                                var mask = 1 << (root.bit_WELD_ENABLE_FB - 1)

                                var outs = robotComm ? robotComm.getOutputs(0) : []
                                var w0 = (outs && outs.length > 0) ? (outs[0] & 0xFFFF) : 0

                                var next = desired ? (w0 | mask) : (w0 & (~mask))
                                if (robotComm)
                                    robotComm.setOutputWord(0, 0, next)
                            }
                        }

                        // ---- bottom boxes: speed + position ----

                        Button {
                            id: speedBtn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: weldEnableBtn.bottom
                            anchors.margins: Theme.pad
                            height: parent.height * panelBtnHFrac

                            background: Rectangle {
                                radius: Theme.radius * 0.6
                                color: "#3a3a3a"
                            }

                            contentItem: Text {
                                text: "Speed: " + root.robotSpeedPct + "%"
                                color: "#1fbf4a"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSmall
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }

                            onClicked: {
                                // Toggle output bit 14 on robot (single robot for now)
                            }
                        }

                        Button {
                            id: positionBtn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: speedBtn.bottom
                            anchors.margins: Theme.pad
                            height: parent.height * panelBtnHFrac

                            background: Rectangle {
                                radius: Theme.radius * 0.6
                                color: "#3a3a3a"
                            }

                            contentItem: Text {
                                text: "Position: " + root.livePosDeg
                                color: "#1fbf4a"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSmall
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }

                            onClicked: {
                                // Toggle output bit 14 on robot (single robot for now)
                            }
                        }
                    }
                }

                // Example: one panel (top-left) wired to robots[0]
                Loader {
                    id: panelTL
                    sourceComponent: robotPanel
                    visible: robots.count > 0

                    onLoaded: {
                        item.name = "Robot 1"
                        item.pos = 0

                        item.x = -ringArea.panelW - 80 // <-- ADJUSTED: position panel to left of ring
                        item.y = -20
                    }

                    Binding {
                        target: panelTL.item
                        property: "state"
                        when: panelTL.item
                        value: root.panelState
                    }
                }
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
                    Layout.preferredHeight: rightPane.height * 0.42
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
                            font.pixelSize: Theme.h2
                            font.bold: true
                            Layout.fillWidth: true
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
                                    anchors.margins: 4
                                    spacing: 2

                                    Text {
                                        text: t.label
                                        color: Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontMed
                                        font.bold: true
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 4
                                        Layout.alignment: Qt.AlignHCenter

                                        Rectangle {
                                            width: 12
                                            height: 12
                                            radius: 6
                                            color: t.on ? "#1fbf4a" : "#8a8a8a"
                                        }

                                        Text {
                                            text: t.on ? t.onText : t.offText
                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSmall
                                        }
                                    }
                                }
                            }
                        }

                        Component {
                            id: indicatorValueTile

                            Rectangle {
                                id: v
                                radius: Theme.radius * 0.6
                                color: Theme.panel
                                border.color: Theme.text
                                border.width: 1

                                property string label: ""
                                property string valueText: "—"

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.pad
                                    spacing: 6

                                    Text {
                                        text: v.label
                                        color: Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontMed
                                        font.bold: true
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                    }

                                    Text {
                                        text: v.valueText
                                        color: Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontMed
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            columns: 2
                            rowSpacing: 4
                            columnSpacing: 4

                            Loader {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 40
                                sourceComponent: indicatorTile
                                onLoaded: {
                                    item.label = "Door 1"
                                    item.onText = "OPEN"
                                    item.offText = "CLOSED"
                                    item.on = root.door1Open
                                }
                            }

                            Loader {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 40
                                sourceComponent: indicatorTile
                                onLoaded: {
                                    item.label = "Door 2"
                                    item.onText = "OPEN"
                                    item.offText = "CLOSED"
                                    item.on = root.door2Open
                                }
                            }

                            Loader {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 40
                                sourceComponent: indicatorTile
                                onLoaded: {
                                    item.label = "Floor"
                                    item.onText = "OPEN"
                                    item.offText = "CLOSED"
                                    item.on = root.floorOpen
                                }
                            }

                            Loader {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 40
                                sourceComponent: indicatorTile
                                onLoaded: {
                                    item.label = "Fans"
                                    item.onText = "ON"
                                    item.offText = "OFF"
                                    item.on = root.fansOn
                                }
                            }

                            Loader {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 40
                                sourceComponent: indicatorTile
                                onLoaded: {
                                    item.label = "Lights"
                                    item.onText = "ON"
                                    item.offText = "OFF"
                                    item.on = root.lightsOn
                                }
                            }
                        }
                    }
                }

                // -------- ALARMS window (lower half) --------
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
                            font.pixelSize: Theme.h2
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
                                model: alarmModel2
                                clip: true
                                spacing: 8

                                delegate: Rectangle {
                                    width: ListView.view.width
                                    height: 54
                                    radius: Theme.radius * 0.5
                                    color: Theme.sideBtnpanel

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: Theme.pad
                                        spacing: Theme.gap

                                        Text {
                                            text: level
                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSmall
                                            font.bold: true
                                            Layout.preferredWidth: 70
                                        }

                                        Text {
                                            text: model.text
                                            color: (model.textColorStr && model.textColorStr.length ? model.textColorStr : Theme.text)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSmall
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

    // ============================================================
    // C-STOP POPUP OVERLAY
    // ============================================================
    Rectangle {
        id: cStopPopup
        anchors.fill: parent
        visible: root.cStopActive
        color: "#CC000000"
        z: 100

        // Auto-close when robot sends input bit 20 low
        Connections {
            target: robotComm
            function onInWordsChanged() {
                if (root.cStopActive && !root.getBit(root.ioInWords, 20)) {
                    root.cStopActive = false
                    root.setOutputBit(root.cStopRobotIndex, 20, false)
                }
                // Check Go Home complete (input bit 17 goes low)
                if (root.goHomeLoading && !root.getBit(root.ioInWords, 17)) {
                    root.goHomeLoading = false
                }
                // Check Resume Weld complete (input bit 19 goes low)
                if (root.resumeWeldLoading && !root.getBit(root.ioInWords, 19)) {
                    root.resumeWeldLoading = false
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {} // block clicks through
        }

        Rectangle {
            id: popupCard
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.5, 500)
            height: Math.min(parent.height * 0.7, 520)
            radius: Theme.radius
            color: Theme.panel
            border.color: Theme.danger
            border.width: 3

            Column {
                anchors.fill: parent
                anchors.margins: Theme.pad * 2
                spacing: Theme.gap

                // Title
                Text {
                    text: "CONTROLLED STOP — Robot " + (root.cStopRobotIndex + 1)
                    color: Theme.danger
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.h2
                    font.bold: true
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                // Current Position (read-only from robot)
                Rectangle {
                    width: parent.width
                    height: 50
                    radius: Theme.radius * 0.6
                    color: "#2a2d35"
                    border.color: Theme.border
                    border.width: 1

                    Row {
                        anchors.fill: parent
                        anchors.margins: Theme.pad
                        spacing: Theme.gap

                        Text {
                            text: "Current Position:"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.body
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: root.readCurrentPos() + "°"
                            color: "#1fbf4a"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.h2
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                // Desired Position (editable)
                Rectangle {
                    width: parent.width
                    height: 50
                    radius: Theme.radius * 0.6
                    color: "#2a2d35"
                    border.color: Theme.accent
                    border.width: 1

                    Row {
                        anchors.fill: parent
                        anchors.margins: Theme.pad
                        spacing: Theme.gap

                        Text {
                            text: "Desired Position:"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.body
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        TextInput {
                            id: desiredPosInput
                            width: 80
                            text: String(root.cStopDesiredPos)
                            color: "#1f6bff"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.h2
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                            inputMethodHints: Qt.ImhDigitsOnly
                            validator: IntValidator { bottom: 0; top: 360 }
                            onEditingFinished: {
                                var v = parseInt(text)
                                if (!isNaN(v)) {
                                    v = root.clampToQuadrant(v, root.cStopRobotIndex)
                                    root.cStopDesiredPos = v
                                    text = String(v)
                                    root.writeDesiredPos(root.cStopRobotIndex, v)
                                }
                            }
                        }

                        Text {
                            text: "°"
                            color: "#1f6bff"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.h2
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                // Jog Buttons
                Row {
                    width: parent.width
                    spacing: Theme.gap
                    anchors.horizontalCenter: parent.horizontalCenter

                    Rectangle {
                        width: (parent.width - Theme.gap) / 2
                        height: 48
                        radius: Theme.radius
                        color: "#3a3f4a"
                        border.color: Theme.border
                        border.width: 2

                        Text {
                            anchors.centerIn: parent
                            text: "- 5°"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.body
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var v = root.cStopDesiredPos - 5
                                v = root.clampToQuadrant(v, root.cStopRobotIndex)
                                root.cStopDesiredPos = v
                                desiredPosInput.text = String(v)
                                root.writeDesiredPos(root.cStopRobotIndex, v)
                            }
                        }
                    }

                    Rectangle {
                        width: (parent.width - Theme.gap) / 2
                        height: 48
                        radius: Theme.radius
                        color: "#3a3f4a"
                        border.color: Theme.border
                        border.width: 2

                        Text {
                            anchors.centerIn: parent
                            text: "+ 5°"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.body
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var v = root.cStopDesiredPos + 5
                                v = root.clampToQuadrant(v, root.cStopRobotIndex)
                                root.cStopDesiredPos = v
                                desiredPosInput.text = String(v)
                                root.writeDesiredPos(root.cStopRobotIndex, v)
                            }
                        }
                    }
                }

                // Quadrant limits info
                Text {
                    text: "Limits: " + root.quadrantMin(root.cStopRobotIndex) + "° — " + (root.quadrantMax(root.cStopRobotIndex) % 360) + "°"
                    color: "#8a8a8a"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.caption
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                // Go Home Button
                Rectangle {
                    width: parent.width
                    height: 48
                    radius: Theme.radius
                    color: root.goHomeLoading ? "#555e6e" : Theme.accent
                    border.color: root.goHomeLoading ? "#555e6e" : Theme.accent
                    border.width: 2

                    Text {
                        anchors.centerIn: parent
                        text: root.goHomeLoading ? "Going Home..." : "Go Home"
                        color: Theme.panel
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.body
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !root.goHomeLoading
                        cursorShape: root.goHomeLoading ? Qt.WaitCursor : Qt.PointingHandCursor
                        onClicked: {
                            root.goHomeLoading = true
                            root.setOutputBit(root.cStopRobotIndex, 17, true)
                        }
                    }
                }

                // Resume Weld Button
                Rectangle {
                    width: parent.width
                    height: 48
                    radius: Theme.radius
                    color: root.resumeWeldLoading ? "#555e6e" : Theme.success
                    border.color: root.resumeWeldLoading ? "#555e6e" : "#3ab86a"
                    border.width: 2

                    Text {
                        anchors.centerIn: parent
                        text: root.resumeWeldLoading ? "Resuming..." : "Resume Weld"
                        color: Theme.panel
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.body
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !root.resumeWeldLoading
                        cursorShape: root.resumeWeldLoading ? Qt.WaitCursor : Qt.PointingHandCursor
                        onClicked: {
                            root.resumeWeldLoading = true
                            root.setOutputBit(root.cStopRobotIndex, 19, true)
                        }
                    }
                }
            }
        }
    }

}
