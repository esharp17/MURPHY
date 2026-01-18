import QtQuick 2.15
import RobotUI 1.0

Rectangle {
    id: sb
    signal pressed(string name)

    radius: Theme.sideBtnradius
    color: Theme.sideBtnpanel

    // ----------------------------
    // External hookup
    // ----------------------------
    property var bridge: null
    property int robotIndex: 0          // only used for reference reads
    property bool driveAllRobots: true  // broadcast commands

    // Word indices
    property int cmdWord: 0             // outputs word index
    property int stWord: 0              // inputs word index

    // OUTPUT command bits (your spec)
    readonly property int bit_CMD_AUTO:   10
    readonly property int bit_CMD_MANUAL: 11
    readonly property int bit_CMD_ENABLE: 8
    readonly property int bit_CMD_START:  6
    readonly property int bit_CMD_RESET:  5
    readonly property int bit_CMD_IMSTP:  1

    // INPUT status bits (your spec)
    // Running=3, Fault=6, TPEN=8
    readonly property int bit_ST_RUNNING: 3
    readonly property int bit_ST_FAULT:   6
    readonly property int bit_ST_TPEN:    8

    // ----------------------------
    // UI states
    // ----------------------------
    property bool autoActive:   false
    property bool manualActive: false
    property bool startActive:  false
    property bool resetActive:  false

    // derived / cached indicators (bindings must depend on QML properties)
    property bool faultAny: false

    // STOP/IMSTP state:
    // stopSafe=true  => IMSTP bit ON  => solid red
    // stopSafe=false => IMSTP bit OFF => flashing red
    property bool stopSafe:  false
    property bool stopFlash: false

    // internal requests
    property bool _autoReq:   false
    property bool _manualReq: false

    readonly property real btnH: (height - (Theme.sideBtngap * 5) - (Theme.sideBtngap * 2)) / 6

    // cached inputs for robotIndex (only used if you want local indicators later)
    property var _ins: []

    // ----------------------------
    // bit helpers
    // ----------------------------
    // b is 1-based (bit1 = LSB)
    function _bit(w, b1) {
        var b = (b1 - 1)
        return (((w >>> 0) >>> b) & 1) === 1
    }

    // ----------------------------
    // Bridge IO helpers (using your existing API)
    // ----------------------------
    function _getInputs(robot) {
        if (!bridge) return []
        return bridge.getInputs(robot) || []
    }

    function _getOutputs(robot) {
        if (!bridge) return []
        return bridge.getOutputs(robot) || []
    }

    function _readInWord(robot, wordIndex) {
        var ins = _getInputs(robot)
        if (!ins || ins.length <= wordIndex) return 0
        return ins[wordIndex] >>> 0
    }

    function _readOutWord(robot, wordIndex) {
        var outs = _getOutputs(robot)
        if (!outs || outs.length <= wordIndex) return 0
        return outs[wordIndex] >>> 0
    }

    function _writeOutputsWord(robot, wordIndex, value) {
        if (!bridge) return
        bridge.setOutputWord(robot, wordIndex, value >>> 0)
    }

    function _writeCmdWordAll(value) {
        if (!bridge) return
        if (driveAllRobots) {
            if (bridge.setOutputWordAll) {
                bridge.setOutputWordAll(cmdWord, value >>> 0)
            } else {
                for (var r = 0; r < 4; r++) _writeOutputsWord(r, cmdWord, value >>> 0)
            }
        } else {
            _writeOutputsWord(robotIndex, cmdWord, value >>> 0)
        }
    }

    function _setBit(w, b1, on) {
        w = w >>> 0
        var b = (b1 - 1)
        return on ? (w | (1 << b)) : (w & ~(1 << b))
    }

    function _setCmdBitAll(bit, on) {
        // use first connected robot as the "base" word; simplest given your existing bridge API
        var base = _readOutWord(robotIndex, cmdWord)
        var next = _setBit(base, bit, on)
        _writeCmdWordAll(next)
    }

function _pulseCmdBit(robot, bit, ms) {
    // turn bit ON now
    var wOn = _readOutWord(robot, cmdWord)
    _writeOutputsWord(robot, cmdWord, _setBit(wOn, bit, true))

    // clear ONLY that bit after ms
    var t = Qt.createQmlObject(
        'import QtQuick 2.15; Timer { interval: '+ms+'; repeat: false }',
        sb,
        "pulseClearTimer"
    )
    t.triggered.connect(function() {
        var wNow = _readOutWord(robot, cmdWord)
        _writeOutputsWord(robot, cmdWord, _setBit(wNow, bit, false))
        t.destroy()
    })
    t.start()
}

    // ----------------------------
    // Cell-wide status checks (all robots)
    // ----------------------------
function _anyRobotBitOn(bit) {
    for (var r = 0; r < 4; r++) {
        var w = _readInWord(r, stWord)
        if (_bit(w, bit)) return true
    }
    return false
}

function _robotBitOn(robot, bit) {
    var w = _readInWord(robot, stWord)
    return _bit(w, bit)
}

function anyFault() { return _anyRobotBitOn(bit_ST_FAULT) }
function anyTPEN()  { return _anyRobotBitOn(bit_ST_TPEN) }
function autoEnabled() { return (!anyFault() && !anyTPEN()) }


    // ----------------------------
    // Timers
    // ----------------------------
    // Cycle Start hold (500ms)
    Timer {
        id: tHoldStart
        interval: 500
        repeat: false
        onTriggered: {
            if (!_autoReq) { startActive = false; return }

            // pulse START (bit 6) to any robot with RUNNING bit OFF
            for (var r = 0; r < 4; r++) {
                if (_robotBitOn(r, bit_ST_RUNNING)) continue
                _pulseCmdBit(r, bit_CMD_START, 200)
            }
            startActive = false
        }
    }

    // pulse restore timer (single outstanding pulse)
    Timer {
        id: tPulse
        property int robot: -1
        property int restoreWord: 0
        repeat: false
        onTriggered: {
            if (robot >= 0) _writeOutputsWord(robot, cmdWord, restoreWord)
        }
    }

    // IMSTP debounce ONLY for turning ON
    Timer {
        id: tImstpDebounceOn
        interval: 250
        repeat: false
    }

    // Flash STOP indicator when in STOP mode
    Timer {
        id: tStopFlash
        interval: 350
        repeat: true
        running: !stopSafe
        onTriggered: stopFlash = !stopFlash
        onRunningChanged: {
            if (!running) stopFlash = false
            if (running)  stopFlash = true
        }
    }

    // Auto drop if any TPEN or fault
    Timer {
        id: tAutoDropWatch
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (autoActive && !autoEnabled()) {
                _autoReq = false
                autoActive = false
                _setCmdBitAll(bit_CMD_AUTO, false)
            }
        }
    }

    // ----------------------------
    // Startup
    // ----------------------------
    Component.onCompleted: {
        if (bridge) _ins = bridge.getInputs(robotIndex)

        // start in STOP mode (IMSTP OFF)
        stopSafe = false
        _setCmdBitAll(bit_CMD_IMSTP, false)
    // Turn on Enable
    _setCmdBitAll(bit_CMD_ENABLE, true)

    }

    Connections {
        target: bridge
        function onIoUpdated(i) {
            // Any robot update can affect the aggregate indicators
            sb.faultAny = sb._anyRobotBitOn(sb.bit_ST_FAULT)

            // keep your local cache for robotIndex if you still want it
            if (i === sb.robotIndex) sb._ins = sb.bridge.getInputs(sb.robotIndex)
        }
    }

    // ----------------------------
    // Button handlers
    // ----------------------------


    function pressAuto() {
        if (!bridge) return
        if (!autoEnabled()) return

        _autoReq = true
        _manualReq = false

        autoActive = true
        manualActive = false

        _setCmdBitAll(bit_CMD_AUTO, true)
        _setCmdBitAll(bit_CMD_MANUAL, false)
    }

    function pressManual() {
        if (!bridge) return

        _manualReq = true
        _autoReq = false

        manualActive = true
        autoActive = false

        _setCmdBitAll(bit_CMD_MANUAL, true)
        _setCmdBitAll(bit_CMD_AUTO, false)
    }

    // Start is press-and-hold 500ms; only valid when Auto latched
    function pressStart(pressed) {
        if (!bridge) return
        if (!_autoReq) return

        if (pressed) {
            startActive = true
            tHoldStart.restart()
        } else {
            tHoldStart.stop()
            startActive = false
        }
    }

    // Cycle Stop does nothin
    function pressStop() {
        if (!bridge) return
        // nothing for now
    }

    // Fault reset: blue while held; while held, if any fault => hold bit 5 ON. Release => OFF.
    function pressReset(pressed) {
        if (!bridge) return

        resetActive = !!pressed

        if (!pressed) {
            _setCmdBitAll(bit_CMD_RESET, false)
            return
        }

        _setCmdBitAll(bit_CMD_RESET, anyFault())
    }

    // STOP / IMSTP: latch ON (safe) with debounce; OFF immediately.
    // Call with pressed=true on press, pressed=false on release.
    function pressImstp(pressed) {
        if (!bridge) return

        if (pressed) {
            // turning ON to safe mode: debounce
            if (!stopSafe) {
                if (tImstpDebounceOn.running) return
                tImstpDebounceOn.start()

                stopSafe = true
                _setCmdBitAll(bit_CMD_IMSTP, true)
            } else {
                // already safe: pressing turns OFF immediately (no debounce)
                stopSafe = false
                _setCmdBitAll(bit_CMD_IMSTP, false)
            }
            return
        }

        // release does nothing (latch behavior)
    }

    function stopButtonColor() {
        if (stopSafe) return Theme.sideBtnstopRed
        // flashing in STOP mode
        return stopFlash ? Theme.sideBtnstopRed : Qt.darker(Theme.sideBtnstopRed, 1.6)
    }

    // ----------------------------
    // UI
    // ----------------------------
    Column {
        anchors.fill: parent
        anchors.margins: Theme.sideBtngap
        spacing: Theme.sideBtngap

        Rectangle {
            id: bAuto
            height: sb.btnH
            width: parent.width
            radius: Theme.sideBtnradius
            color: sb.autoActive ? "green" : Theme.sideBtnBase
            border.width: 2
            border.color: "#2a3442"
            opacity: sb.autoEnabled() ? 1.0 : 0.35

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 6
                text: "Automatic Mode"
                color: Theme.sideBtnText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sideBtnFont
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                enabled: sb.autoEnabled()
                onClicked: { sb.pressAuto(); sb.pressed("auto") }
            }
        }

        Rectangle {
            id: bManual
            height: sb.btnH
            width: parent.width
            radius: Theme.sideBtnradius
            color: sb.manualActive ? "yellow" : Theme.sideBtnBase
            border.width: 2
            border.color: "#2a3442"

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 6
                text: "Manual Mode"
                color: sb.manualActive ? "black" : Theme.sideBtnText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sideBtnFont
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                onClicked: { sb.pressManual(); sb.pressed("manual") }
            }
        }

        Rectangle {
            id: bStart
            height: sb.btnH
            width: parent.width
            radius: Theme.sideBtnradius
            color: sb.startActive ? "blue" : Theme.sideBtnBase
            border.width: 2
            border.color: "#2a3442"
            opacity: sb._autoReq ? 1.0 : 0.35

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 6
                text: "Cycle Start"
                color: Theme.sideBtnText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sideBtnFont
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                enabled: sb._autoReq
                onPressed: { sb.pressStart(true); sb.pressed("start") }
                onReleased:{ sb.pressStart(false) }
                onCanceled:{ sb.pressStart(false) }
            }
        }

        Rectangle {
            id: bStop
            height: sb.btnH
            width: parent.width
            radius: Theme.sideBtnradius
            color: sb.stopActive ? "blue" : Theme.sideBtnBase
            border.width: 2
            border.color: "#2a3442"
            opacity: sb._autoReq ? 1.0 : 0.35

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 6
                text: "Cycle Stop"
                color: Theme.sideBtnText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sideBtnFont
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                enabled: sb._autoReq
                onPressed: { sb.pressStop(true); sb.pressed("stop") }
                onReleased:{ sb.pressStop(false) }
                onCanceled:{ sb.pressStop(false) }
            }
        }

                Rectangle {
            id: bReset
            height: sb.btnH
            width: parent.width
            radius: Theme.sideBtnradius
            color: sb.resetActive ? "blue" : Theme.sideBtnBase
            border.width: sb.faultAny ? 3 : 2
            border.color: sb.faultAny ? "red" : "#2a3442"

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 6
                text: "Fault Reset"
                color: Theme.sideBtnText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sideBtnFont
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                onPressed: { sb.pressReset(true); sb.pressed("reset") }
                onReleased:{ sb.pressReset(false) }
                onCanceled:{ sb.pressReset(false) }
            }
        }

        Rectangle {
            id: bEstop
            height: sb.btnH
            width: parent.width
            radius: Theme.sideBtnradius
            border.width: 3
            border.color: "#000000"
            color: sb.stopButtonColor()

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 6
                text: "STOP"
                color: Theme.sideBtnstopText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sideBtnFont + 4
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                onPressed: { sb.pressImstp(true); sb.pressed("estop") }
                // latch behavior; release does not force OFF
                onReleased: { sb.pressImstp(false) }
                onCanceled: { sb.pressImstp(false) }
            }
        }
    }
}

