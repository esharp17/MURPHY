
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
    property real splitLeftFrac: 0.65
    property int  outerPad: Theme.pad
    property int  gap: Theme.gap
    property real ringFrac: 0.62
    property real ringMarginFrac: 0.02
    property real panelWFrac: 0.28
    property real panelHFrac: 0.20
    property real panelBtnHFrac: 0.28
    property real panelBtnWFrac: 0.46
    // ============================================================

    // ---------- wire later ----------
    property bool door1Open: false
    property bool door2Open: false
    property bool floorOpen: false
    property bool fansOn: true
    property bool lightsOn: true

    property var r0Words: []
    property var r1Words: []
    property var r2Words: []
    property var r3Words: []
    property int r0ConnState: 0
    property int r1ConnState: 0
    property int r2ConnState: 0
    property int r3ConnState: 0

    function refreshRobotData() {
        if (!RobotComm) return
        r0ConnState = RobotComm.getState(0)
        r1ConnState = RobotComm.getState(1)
        r2ConnState = RobotComm.getState(2)
        r3ConnState = RobotComm.getState(3)
        r0Words = RobotComm.getInputs(0)
        r1Words = RobotComm.getInputs(1)
        r2Words = RobotComm.getInputs(2)
        r3Words = RobotComm.getInputs(3)
    }

    // Get input words for a robot index
    function wordsFor(idx) {
        if (idx === 0) return root.r0Words
        if (idx === 1) return root.r1Words
        if (idx === 2) return root.r2Words
        if (idx === 3) return root.r3Words
        return []
    }

    function connStateFor(idx) {
        if (idx === 0) return root.r0ConnState
        if (idx === 1) return root.r1ConnState
        if (idx === 2) return root.r2ConnState
        if (idx === 3) return root.r3ConnState
        return 0
    }

    // Read position from word 4 (bits 65-80, lower 10 bits) for a robot
    function robotPos(idx) {
        var w = wordsFor(idx)
        if (!w || w.length <= 4) return 0
        return Number(w[4]) & 0x03FF
    }

    // Derive robot status string from connection state + I/O bits
    // Bit 6 = fault, bit 11 = welding, bit 1 = auto/ready
    // We add: bit 22 = scan data ready (use as "scanning" indicator)
    function robotStatus(idx) {
        var cs = connStateFor(idx)
        if (cs === 0) return "disconnected"
        if (cs === 1) return "connecting"
        if (cs === 3) return "faulted"
        // cs === 2 (cyclic) — read I/O bits
        var w = wordsFor(idx)
        if (getBit(w, 6)) return "faulted"
        if (getBit(w, 11)) return "welding"
        if (getBit(w, 4)) return "paused"
        if (getBit(w, 22)) return "scanning"
        if (getBit(w, 1)) return "ready"
        return "idle"
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
        if (s === "ready")        return "READY"
        if (s === "welding")      return "WELD"
        if (s === "faulted")      return "FAULT"
        if (s === "paused")       return "PAUSE"
        if (s === "scanning")     return "SCAN"
        if (s === "disconnected") return "DISC"
        if (s === "connecting")   return "CONN"
        if (s === "idle")         return "IDLE"
        return "OFF"
    }

    function stateColor(s) {
        if (s === "ready")        return Theme.stateReady
        if (s === "welding")      return Theme.stateWelding
        if (s === "faulted")      return Theme.stateFaulted
        if (s === "paused")       return Theme.statePaused
        if (s === "disconnected") return Theme.stateDisabled
        if (s === "connecting")   return Theme.warning
        if (s === "scanning")     return Theme.accent
        if (s === "idle")         return Theme.muted
        return Theme.stateDisabled
    }

    // ============================================================
    // C-STOP PER-ROBOT STATE (arrays of 4)
    // ============================================================
    property var cStopOpen: [false, false, false, false]
    property var cStopAcknowledged: [false, false, false, false]  // true once robot bit 20 went high
    property var cStopDesiredPos: [0, 0, 0, 0]
    property var goHomeLoading: [false, false, false, false]
    property var goHomeAcknowledged: [false, false, false, false]
    property var resumeWeldLoading: [false, false, false, false]
    property var resumeWeldAcknowledged: [false, false, false, false]

    // Live I/O words from robot comm
    property var ioInWords: []

    // ============================================================
    // ALARMS (bits 40-60, all 4 robots)
    // ============================================================
    property var dismissedAlertKeys: ({})
    property var alarmCatalog: ({})
    property url alarmCatalogUrl: Qt.resolvedUrl("../assets/alarms.json")

    onDismissedAlertKeysChanged: rebuildAlarms()

    function loadAlarmCatalog() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", alarmCatalogUrl)
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (!(xhr.status === 200 || xhr.status === 0)) return
            if (!xhr.responseText || xhr.responseText.length < 2) return
            try {
                var txt = xhr.responseText
                if (txt.charCodeAt(0) === 0xFEFF) txt = txt.slice(1)
                var obj = JSON.parse(txt)
                alarmCatalog = (obj.alarms ? obj.alarms : obj)
            } catch (e) {
                console.log("[CellStatus4] alarms.json parse fail:", e)
            }
            rebuildAlarms()
        }
        xhr.send()
    }

    function alarmLevel(sev) {
        if (sev === "Fault")   return "ALARM"
        if (sev === "Warning") return "WARN"
        return "INFO"
    }

    function rebuildAlarms() {
        messageModel.clear()
        var robotWords = [r0Words, r1Words, r2Words, r3Words]
        var robotNames = ["Robot 1", "Robot 2", "Robot 3", "Robot 4"]
        for (var ri = 0; ri < 4; ri++) {
            for (var b = 40; b <= 60; b++) {
                if (!getBit(robotWords[ri], b)) continue
                var key = "DI" + b
                if (root.dismissedAlertKeys && root.dismissedAlertKeys[key]) continue
                var def = alarmCatalog[String(b)]
                if (!def) def = { name: "Alarm " + b, desc: "Active", severity: "Fault", textColor: "" }
                var tc = (def.textColor && String(def.textColor).length > 0) ? String(def.textColor) : Theme.text
                messageModel.append({
                    ts: "",
                    level: alarmLevel(def.severity),
                    msg: robotNames[ri] + ": " + def.name,
                    textColorStr: tc
                })
            }
        }
    }

    Component.onCompleted: loadAlarmCatalog()

    Connections {
        target: RobotComm || null
        enabled: RobotComm !== null
        function onStateChanged(robotIdx) {
            if (!RobotComm) return
            var s = RobotComm.getState(robotIdx)
            if (robotIdx === 0) r0ConnState = s
            else if (robotIdx === 1) r1ConnState = s
            else if (robotIdx === 2) r2ConnState = s
            else if (robotIdx === 3) r3ConnState = s
        }
        function onIoUpdated(robotIdx) {
            if (!RobotComm) return
            // Refresh the specific robot's word cache and connection state
            var fresh = RobotComm.getInputs(robotIdx)
            var s = RobotComm.getState(robotIdx)
            if (robotIdx === 0) { r0Words = fresh; r0ConnState = s; ioInWords = fresh }
            else if (robotIdx === 1) { r1Words = fresh; r1ConnState = s }
            else if (robotIdx === 2) { r2Words = fresh; r2ConnState = s }
            else if (robotIdx === 3) { r3Words = fresh; r3ConnState = s }

            var words = fresh
            var i = robotIdx

            rebuildAlarms()

            // Wait for robot to set bit 20 HIGH (acknowledgment), then close when it goes LOW
            if (root.cStopOpen[i]) {
                if (root.getBit(words, 20)) {
                    if (!root.cStopAcknowledged[i]) {
                        var ackArr = root.cStopAcknowledged.slice()
                        ackArr[i] = true
                        root.cStopAcknowledged = ackArr
                    }
                } else if (root.cStopAcknowledged[i]) {
                    root.closeCStop(i)
                }
            }
            // Go Home: wait for bit 17 HIGH (ack), then clear when it goes LOW
            if (root.goHomeLoading[i]) {
                if (root.getBit(words, 17)) {
                    if (!root.goHomeAcknowledged[i]) {
                        var ghAck = root.goHomeAcknowledged.slice()
                        ghAck[i] = true
                        root.goHomeAcknowledged = ghAck
                    }
                } else if (root.goHomeAcknowledged[i]) {
                    var gh = root.goHomeLoading.slice()
                    gh[i] = false
                    root.goHomeLoading = gh
                    var ghAck2 = root.goHomeAcknowledged.slice()
                    ghAck2[i] = false
                    root.goHomeAcknowledged = ghAck2
                    root.setOutputBit(i, 17, false)
                    if (root.cStopOpen[i]) root.closeCStop(i)
                }
            }
            // Resume Weld: wait for bit 19 HIGH (ack), then clear when it goes LOW
            if (root.resumeWeldLoading[i]) {
                if (root.getBit(words, 19)) {
                    if (!root.resumeWeldAcknowledged[i]) {
                        var rwAck = root.resumeWeldAcknowledged.slice()
                        rwAck[i] = true
                        root.resumeWeldAcknowledged = rwAck
                    }
                } else if (root.resumeWeldAcknowledged[i]) {
                    var rw = root.resumeWeldLoading.slice()
                    rw[i] = false
                    root.resumeWeldLoading = rw
                    var rwAck2 = root.resumeWeldAcknowledged.slice()
                    rwAck2[i] = false
                    root.resumeWeldAcknowledged = rwAck2
                    root.setOutputBit(i, 19, false)
                    if (root.cStopOpen[i]) root.closeCStop(i)
                }
            }
        }
    }

    // Read a 1-indexed bit from a word array
    function getBit(words, bit1) {
        if (!words || bit1 <= 0) return false
        var wi = Math.floor((bit1 - 1) / 16)
        var bi = (bit1 - 1) % 16
        if (wi < 0 || wi >= words.length) return false
        var w = Number(words[wi]) & 0xFFFF
        return ((w >> bi) & 1) === 1
    }

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

    function clampToQuadrant(pos, robotIdx) {
        var mn = quadrantMin(robotIdx)
        var mx = quadrantMax(robotIdx)
        var p = pos % 360
        if (p < 0) p += 360
        // Handle wrap for robot 0 (350-100 crosses 0)
        if (mn > mx % 360) {
            if (p >= mn || p <= (mx % 360)) return p
            var distToMin = Math.abs(p - mn) > 180 ? 360 - Math.abs(p - mn) : Math.abs(p - mn)
            var distToMax = Math.abs(p - (mx % 360)) > 180 ? 360 - Math.abs(p - (mx % 360)) : Math.abs(p - (mx % 360))
            return distToMin < distToMax ? mn : (mx % 360)
        }
        if (p < mn) return mn
        if (p > mx) return mx
        return p
    }

    // Read current position from input bits 65-74 (word 4, lower 10 bits)
    function readCurrentPos() {
        if (!ioInWords || ioInWords.length <= 4) return 0
        return Number(ioInWords[4]) & 0x03FF
    }

    // Write desired position to output bits 65-74 (word 4, lower 10 bits)
    function writeDesiredPos(robotIdx, pos) {
        if (!RobotComm) return
        var outs = RobotComm.getOutputs(robotIdx) || []
        var w4 = (outs.length > 4) ? (Number(outs[4]) & 0xFFFF) : 0
        w4 = (w4 & 0xFC00) | (pos & 0x03FF)
        RobotComm.setOutputWord(robotIdx, 4, w4)
    }

    // Set/clear a single output bit (1-indexed)
    function setOutputBit(robotIdx, bit1, value) {
        if (!RobotComm) return
        var wi = Math.floor((bit1 - 1) / 16)
        var bi = (bit1 - 1) % 16
        var outs = RobotComm.getOutputs(robotIdx) || []
        var w = (outs.length > wi) ? (Number(outs[wi]) & 0xFFFF) : 0
        if (value)
            w = w | (1 << bi)
        else
            w = w & (~(1 << bi))
        RobotComm.setOutputWord(robotIdx, wi, w)
    }

    // Toggle C-Stop for a specific robot index
    function openCStop(robotIdx) {
        if (cStopOpen[robotIdx]) return  // already open, do nothing
        var arr = cStopOpen.slice()
        arr[robotIdx] = true
        cStopOpen = arr
        var ackArr = cStopAcknowledged.slice()
        ackArr[robotIdx] = false
        cStopAcknowledged = ackArr
        // Initialize desired pos for this robot
        var posArr = cStopDesiredPos.slice()
        posArr[robotIdx] = robotPos(robotIdx)
        cStopDesiredPos = posArr
        // Clear loading states and their acknowledgment flags
        var ghArr = goHomeLoading.slice()
        var rwArr = resumeWeldLoading.slice()
        var ghAckArr = goHomeAcknowledged.slice()
        var rwAckArr = resumeWeldAcknowledged.slice()
        ghArr[robotIdx] = false
        rwArr[robotIdx] = false
        ghAckArr[robotIdx] = false
        rwAckArr[robotIdx] = false
        goHomeLoading = ghArr
        resumeWeldLoading = rwArr
        goHomeAcknowledged = ghAckArr
        resumeWeldAcknowledged = rwAckArr
        // Set output bit 20 for this robot
        setOutputBit(robotIdx, 20, true)
    }

    // Close C-Stop for a specific robot
    function closeCStop(robotIdx) {
        var arr = cStopOpen.slice()
        arr[robotIdx] = false
        cStopOpen = arr
        var ackArr = cStopAcknowledged.slice()
        ackArr[robotIdx] = false
        cStopAcknowledged = ackArr
        setOutputBit(robotIdx, 20, false)
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
    visible: root.connStateFor(index) === 2

    onLoaded: {
        item.sx = modelData.sx
        item.sy = modelData.sy
        item.elbowUp = modelData.elbowUp
    }

Binding {
    target: item
    property: "posDeg"
    when: item
    value: root.norm360(root.robotPos(index))
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
                        height: contentCol.implicitHeight + Theme.padSm * 2
                        radius: Theme.radius
                        color: Theme.sideBtnpanel
                        border.color: !p.isConnected ? "#e55a2b" : cStopActive ? Theme.danger : Theme.text
                        border.width: (!p.isConnected || cStopActive) ? 2 : 1
                        clip: true

                        // Smooth height animation
                        Behavior on height {
                            NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
                        }

                        property string name: ""
                        property int robotIndex: 0
                        property bool cStopActive: root.cStopOpen[robotIndex] || false
                        property bool isConnected: root.connStateFor(robotIndex) === 2

                        Column {
                            id: contentCol
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: Theme.padSm
                            spacing: 4

                            // ---- disconnected banner ----
                            Column {
                                width: parent.width
                                height: visible ? implicitHeight + Theme.padSm : 0
                                visible: !p.isConnected
                                spacing: 4

                                Text {
                                    width: parent.width
                                    text: p.name
                                    color: "#e55a2b"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.bodySm
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                Text {
                                    width: parent.width
                                    text: "DISCONNECTED"
                                    color: "#e55a2b"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.caption
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }

                            // ---- top row: C-STOP + STATUS INDICATOR ----
                            Row {
                                id: topRow
                                width: parent.width
                                height: p.isConnected ? 28 : 0
                                visible: p.isConnected
                                spacing: Theme.padSm

                                Rectangle {
                                    id: cstop
                                    width: (parent.width - parent.spacing) * 0.5
                                    height: parent.height
                                    radius: Theme.radiusSm
                                    color: cStopActive ? Theme.danger : Theme.panel
                                    border.width: 2
                                    border.color: cStopActive ? "#ff5555" : Theme.danger

                                    Text {
                                        anchors.centerIn: parent
                                        text: cStopActive ? "ACTIVE" : "C-STOP"
                                        color: cStopActive ? Theme.panel : Theme.danger
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.caption
                                        font.bold: true
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (!cStopActive) root.openCStop(p.robotIndex)
                                        }
                                    }
                                }

                                Rectangle {
                                    id: status
                                    width: (parent.width - parent.spacing) * 0.5
                                    height: parent.height
                                    radius: Theme.radiusSm
                                    color: root.stateColor(root.robotStatus(p.robotIndex))

                                    SequentialAnimation on opacity {
                                        running: (root.robotStatus(p.robotIndex) === "faulted")
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 0.55; duration: 700 }
                                        NumberAnimation { to: 1.0;  duration: 700 }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        width: parent.width - 4
                                        text: root.stateLabel(root.robotStatus(p.robotIndex))
                                        color: "#ffffff"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.bold: true
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            // ---- position readout ----
                            Text {
                                width: parent.width
                                height: visible ? implicitHeight : 0
                                text: p.name + "\nPos: " + root.robotPos(p.robotIndex) + "\u00B0"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.caption
                                wrapMode: Text.WordWrap
                                visible: p.isConnected && !p.cStopActive
                            }

                            // ---- C-STOP CONTROLS (visible when active and connected) ----
                            Column {
                                width: parent.width
                                height: visible ? implicitHeight : 0
                                spacing: 4
                                visible: p.cStopActive && p.isConnected

                                // Divider
                                Rectangle {
                                    width: parent.width
                                    height: 2
                                    color: Theme.danger
                                    opacity: 0.5
                                }

                                // Current + Desired Position row
                                Row {
                                    width: parent.width
                                    spacing: 4

                                    Rectangle {
                                        width: parent.width * 0.48
                                        height: 28
                                        radius: 4
                                        color: "#2a2d35"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "Cur: " + root.robotPos(p.robotIndex) + "\u00B0"
                                            color: "#1fbf4a"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.caption
                                        }
                                    }

                                    Rectangle {
                                        width: parent.width * 0.48
                                        height: 28
                                        radius: 4
                                        color: "#2a2d35"
                                        border.color: Theme.accent
                                        border.width: 1

                                        TextInput {
                                            id: desiredInput
                                            anchors.fill: parent
                                            anchors.margins: 4
                                            text: String(root.cStopDesiredPos[p.robotIndex] || 0)
                                            color: "#1f6bff"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.caption
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            inputMethodHints: Qt.ImhDigitsOnly
                                            validator: IntValidator { bottom: 0; top: 360 }
                                            onEditingFinished: {
                                                var v = parseInt(text)
                                                if (!isNaN(v)) {
                                                    v = root.clampToQuadrant(v, p.robotIndex)
                                                    var arr = root.cStopDesiredPos
                                                    arr[p.robotIndex] = v
                                                    root.cStopDesiredPos = arr
                                                    text = String(v)
                                                    root.writeDesiredPos(p.robotIndex, v)
                                                }
                                            }
                                        }
                                    }
                                }

                                // Jog buttons
                                Row {
                                    width: parent.width
                                    spacing: 4

                                    Rectangle {
                                        width: (parent.width - 4) / 2
                                        height: 26
                                        radius: 4
                                        color: "#3a3f4a"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "-5\u00B0"
                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.caption
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                var arr = root.cStopDesiredPos.slice()
                                                var v = (arr[p.robotIndex] || 0) - 5
                                                v = root.clampToQuadrant(v, p.robotIndex)
                                                arr[p.robotIndex] = v
                                                root.cStopDesiredPos = arr
                                                desiredInput.text = String(v)
                                                root.writeDesiredPos(p.robotIndex, v)
                                            }
                                        }
                                    }

                                    Rectangle {
                                        width: (parent.width - 4) / 2
                                        height: 26
                                        radius: 4
                                        color: "#3a3f4a"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "+5\u00B0"
                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.caption
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                var arr = root.cStopDesiredPos.slice()
                                                var v = (arr[p.robotIndex] || 0) + 5
                                                v = root.clampToQuadrant(v, p.robotIndex)
                                                arr[p.robotIndex] = v
                                                root.cStopDesiredPos = arr
                                                desiredInput.text = String(v)
                                                root.writeDesiredPos(p.robotIndex, v)
                                            }
                                        }
                                    }
                                }

                                // Limits display
                                Text {
                                    width: parent.width
                                    text: "Limits: " + root.quadrantMin(p.robotIndex) + "\u00B0-" + (root.quadrantMax(p.robotIndex) % 360) + "\u00B0"
                                    color: "#8a8a8a"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                // Go Home button
                                Rectangle {
                                    width: parent.width
                                    height: 26
                                    radius: 4
                                    color: root.goHomeLoading[p.robotIndex] ? "#555e6e" : Theme.accent

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.goHomeLoading[p.robotIndex] ? "Going..." : "Go Home"
                                        color: Theme.panel
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.caption
                                        font.bold: true
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: !root.goHomeLoading[p.robotIndex]
                                        onClicked: {
                                            var arr = root.goHomeLoading.slice()
                                            arr[p.robotIndex] = true
                                            root.goHomeLoading = arr
                                            root.setOutputBit(p.robotIndex, 17, true)
                                        }
                                    }
                                }

                                // Resume Weld button
                                Rectangle {
                                    width: parent.width
                                    height: 26
                                    radius: 4
                                    color: root.resumeWeldLoading[p.robotIndex] ? "#555e6e" : "#1fbf4a"

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.resumeWeldLoading[p.robotIndex] ? "Resuming..." : "Resume Weld"
                                        color: Theme.panel
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.caption
                                        font.bold: true
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: !root.resumeWeldLoading[p.robotIndex]
                                        onClicked: {
                                            var arr = root.resumeWeldLoading.slice()
                                            arr[p.robotIndex] = true
                                            root.resumeWeldLoading = arr
                                            root.setOutputBit(p.robotIndex, 19, true)
                                        }
                                    }
                                }

                            }
                        }
                    }
                }

// Panel offsets relative to ring center (YOU tune these)

Loader {
    id: panelTL
    sourceComponent: robotPanel
    visible: true
    onLoaded: {
        item.name = "Robot 1"
        item.robotIndex = 0
    }
    Binding { target: panelTL.item; property: "x"; value: ringArea.width * 0.01; when: panelTL.item }
    Binding { target: panelTL.item; property: "y"; value: ringArea.height * 0.01; when: panelTL.item }
}

Loader {
    id: panelBL
    sourceComponent: robotPanel
    visible: true
    onLoaded: {
        item.name = "Robot 2"
        item.robotIndex = 1
    }
    Binding { target: panelBL.item; property: "x"; value: ringArea.width - ringArea.panelW - ringArea.width * 0.01; when: panelBL.item }
    Binding { target: panelBL.item; property: "y"; value: ringArea.height * 0.01; when: panelBL.item }
}

Loader {
    id: panelTR
    sourceComponent: robotPanel
    visible: true
    onLoaded: {
        item.name = "Robot 3"
        item.robotIndex = 2
    }
    Binding { target: panelTR.item; property: "x"; value: ringArea.width * 0.01; when: panelTR.item }
    Binding { target: panelTR.item; property: "y"; value: ringArea.height - (panelTR.item ? panelTR.item.height : ringArea.panelH) - ringArea.height * 0.01; when: panelTR.item }
}

Loader {
    id: panelBR
    sourceComponent: robotPanel
    visible: true
    onLoaded: {
        item.name = "Robot 4"
        item.robotIndex = 3
    }
    Binding { target: panelBR.item; property: "x"; value: ringArea.width - ringArea.panelW - ringArea.width * 0.01; when: panelBR.item }
    Binding { target: panelBR.item; property: "y"; value: ringArea.height - (panelBR.item ? panelBR.item.height : ringArea.panelH) - ringArea.height * 0.01; when: panelBR.item }
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
                    Layout.maximumHeight: rightPane.height * 0.54
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
                                id: msgListView
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
                                            text: level
                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.caption
                                            font.bold: true
                                            Layout.preferredWidth: 60
                                        }

                                        Text {
                                            text: msg
                                            color: textColorStr
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
