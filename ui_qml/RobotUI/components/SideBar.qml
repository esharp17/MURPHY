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
    property int loggedInRole: 0         // Role enum: 0=NONE, 1=OPERATOR, 2=TECHNICIAN, 3=ADMIN

    // Word indices
    property int cmdWord: 0             // outputs word index
    property int stWord: 0              // inputs word index

    // OUTPUT command bits (your spec)
    readonly property int bit_CMD_AUTO:        10
    readonly property int bit_CMD_MANUAL:      11
    readonly property int bit_CMD_ENABLE:       8
    readonly property int bit_CMD_OPERATE:       2  // Operate: must be ON for robot to run; drop to Hold
    readonly property int bit_CMD_START:        6  // Start: resumes paused program
    readonly property int bit_CMD_CYCLE_STOP:   4  // Cycle Stop: aborts all programs
    readonly property int bit_CMD_RESET:        5  // Fault Reset
    readonly property int bit_CMD_IMSTP:        1  // IMSTP (safe stop)
    readonly property int bit_CMD_PROD_START:   9  // Production Start: starts Main task (requires bits 3,4,6 all low)

    // INPUT status bits (your spec)
    // Running=3, Fault=6, TPEN=8, Paused=4
    readonly property int bit_ST_RUNNING: 3
    readonly property int bit_ST_FAULT:   6
    readonly property int bit_ST_TPEN:    8
    readonly property int bit_ST_PAUSED:  4

    // ----------------------------
    // UI states
    // ----------------------------
    property bool autoActive:   false
    property bool manualActive: false
    property bool holdActive:   false
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

    readonly property real btnH: (height - (Theme.sideBtngap * 6) - (Theme.sideBtngap * 2) - stripH) / 7
    readonly property real stripH: 28

    // cached inputs per robot for state strip
    property var _ins:  []
    property var _ins0: []
    property var _ins1: []
    property var _ins2: []
    property var _ins3: []

    function _robotState(r) {
        var w = (r === 0 ? _ins0 : r === 1 ? _ins1 : r === 2 ? _ins2 : _ins3)
        if (!w || w.length === 0) return "off"
        var w0 = w[0] >>> 0
        if ((w0 >> 2) & 1) return "running"   // bit 3
        if ((w0 >> 3) & 1) return "paused"    // bit 4
        return "aborted"
    }

    function _stateColor(st) {
        if (st === "running") return "#3dba6e"   // green
        if (st === "paused")  return "#e0a030"   // amber
        if (st === "aborted") return "#555e6e"   // gray
        return "#333a44"
    }

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
    // Compute which word and the local (1-based) bit within that word
    var wi       = Math.floor((bit - 1) / 16)
    var localBit = ((bit - 1) % 16) + 1

    // turn bit ON now
    var wOn = _readOutWord(robot, wi)
    _writeOutputsWord(robot, wi, _setBit(wOn, localBit, true))

    // clear ONLY that bit after ms
    var t = Qt.createQmlObject(
        'import QtQuick 2.15; Timer { interval: '+ms+'; repeat: false }',
        sb,
        "pulseClearTimer"
    )
    t.triggered.connect(function() {
        var wNow = _readOutWord(robot, wi)
        _writeOutputsWord(robot, wi, _setBit(wNow, localBit, false))
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

            _setCmdBitAll(bit_CMD_OPERATE, true)  // bit 2 ON: re-enable operation before starting

            // pulse START (bit 6) or RESUME (bit 18) per-robot depending on paused state
            for (var r = 0; r < 4; r++) {
                var isRunning = _robotBitOn(r, bit_ST_RUNNING)
                var isPaused  = _robotBitOn(r, bit_ST_PAUSED)
                console.log("[CYCLESTART] r=" + r + " running=" + isRunning + " paused=" + isPaused)
                var isFaulted = _robotBitOn(r, bit_ST_FAULT)
                if (isRunning) continue                      // already running → skip
                if (isFaulted) continue                      // faulted → skip
                if (isPaused) {
                    console.log("[CYCLESTART] r=" + r + " => START bit 6 (resume paused)")
                    _pulseCmdBit(r, bit_CMD_START, 2000)       // paused → bit 6 resumes
                } else {
                    console.log("[CYCLESTART] r=" + r + " => PROD_START bit 9 (bits 3,4,6 all low)")
                    _pulseCmdBit(r, bit_CMD_PROD_START, 2000)  // bits 3,4,6 all low → bit 9 starts Main task
                }
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
            sb._ins0 = sb.bridge.getInputs(0)
            sb._ins1 = sb.bridge.getInputs(1)
            sb._ins2 = sb.bridge.getInputs(2)
            sb._ins3 = sb.bridge.getInputs(3)
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
        holdActive = false  // reset hold latch when switching modes

        _setCmdBitAll(bit_CMD_ENABLE, true)    // bit 8 ON: enable robot
        _setCmdBitAll(bit_CMD_AUTO, true)
        _setCmdBitAll(bit_CMD_MANUAL, false)
    }

    function pressManual() {
        if (!bridge) return

        _manualReq = true
        _autoReq = false

        manualActive = true
        autoActive = false
        holdActive = false  // reset hold latch when switching modes

        _setCmdBitAll(bit_CMD_ENABLE, true)    // bit 8 ON: enable robot
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

    // Hold: latching toggle of bit 2 (OPERATE); available in manual or auto
    function pressHold() {
        if (!bridge) return
        if (!_autoReq && !_manualReq) return
        holdActive = !holdActive
        // bit 2 ON = running, OFF = hold
        _setCmdBitAll(bit_CMD_OPERATE, !holdActive)
    }

    // Cycle Stop: pulses bit 4 to abort all programs on all robots
    function pressStop() {
        if (!bridge) return
        for (var r = 0; r < 4; r++) {
            _pulseCmdBit(r, bit_CMD_CYCLE_STOP, 200)
        }
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

        // ---- Per-robot state strip ----
        Row {
            width: parent.width
            height: sb.stripH
            spacing: 3
            visible: sb.loggedInRole !== 0

            Repeater {
                model: 4
                delegate: Rectangle {
                    width: (parent.width - 9) / 4
                    height: parent.height
                    radius: 4
                    color: sb._stateColor(sb._robotState(index))

                    Text {
                        anchors.centerIn: parent
                        text: "R" + (index + 1) + "\n" +
                              (sb._robotState(index) === "running" ? "RUNNING" :
                               sb._robotState(index) === "paused"  ? "PAUSED" :
                               sb._robotState(index) === "aborted" ? "ABORTED" : "OFF")
                        color: "#ffffff"
                        font.pixelSize: 9
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        lineHeight: 1.1
                    }
                }
            }
        }

        InteractiveSurface {
            id: bAuto
            height: sb.btnH
            width: parent.width
            radius: Theme.sideBtnradius
            normalColor:  sb.autoActive ? "#1a4d2e" : Theme.sideBtnBase
            pressedColor: "#1a6b3a"
            disabledColor: Theme.btnDisabled
            glowColor: "#2ecc71"
            borderWidth: sb.autoActive ? 2 : 2
            borderColor: sb.autoActive ? "#2ecc71" : "#2a3442"
            enabled: sb.autoEnabled()
            active: sb.autoActive
            opacity: sb.autoEnabled() ? 1.0 : 0.35
            visible: sb.loggedInRole !== 0

            onClicked: { sb.pressAuto(); sb.pressed("auto") }

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 6
                text: "Automatic Mode"
                color: "#ffffff"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sideBtnFont
                font.bold: true
            }
        }

        InteractiveSurface {
            id: bManual
            height: sb.btnH
            width: parent.width
            radius: Theme.sideBtnradius
            normalColor:  sb.manualActive ? "#4d3a00" : Theme.sideBtnBase
            pressedColor: "#6b5200"
            disabledColor: Theme.btnDisabled
            glowColor: "#f0b429"
            borderWidth: 2
            borderColor: sb.manualActive ? "#f0b429" : "#2a3442"
            enabled: sb.loggedInRole !== 0
            active: sb.manualActive
            visible: sb.loggedInRole !== 0

            onClicked: { sb.pressManual(); sb.pressed("manual") }

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 6
                text: "Manual Mode"
                color: "#ffffff"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sideBtnFont
                font.bold: true
            }
        }

        InteractiveSurface {
            id: bStart
            height: sb.btnH
            width: parent.width
            radius: Theme.sideBtnradius
            normalColor: Theme.sideBtnBase
            pressedColor: Theme.btnPressed
            disabledColor: Theme.btnDisabled
            borderWidth: 2
            borderColor: "#2a3442"
            enabled: sb._autoReq
            active: sb.startActive
            opacity: sb._autoReq ? 1.0 : 0.35
            visible: sb.loggedInRole !== 0  // hide if not logged in

            onPressed: { sb.pressStart(true); sb.pressed("start") }
            onReleased:{ sb.pressStart(false) }

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 6
                text: "Cycle Start"
                color: Theme.sideBtnText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sideBtnFont
                font.bold: true
            }
        }

        InteractiveSurface {
            id: bStop
            height: sb.btnH
            width: parent.width
            radius: Theme.sideBtnradius
            normalColor: Theme.sideBtnBase
            pressedColor: Theme.btnPressed
            disabledColor: Theme.btnDisabled
            borderWidth: 2
            borderColor: "#2a3442"
            enabled: sb._autoReq
            active: sb.stopActive
            opacity: sb._autoReq ? 1.0 : 0.35
            visible: sb.loggedInRole !== 0  // hide if not logged in

            onPressed: { sb.pressStop(true); sb.pressed("stop") }
            onReleased:{ sb.pressStop(false) }

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 6
                text: "Cycle Stop"
                color: Theme.sideBtnText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sideBtnFont
                font.bold: true
            }
        }

        InteractiveSurface {
            id: bHold
            height: sb.btnH
            width: parent.width
            radius: Theme.sideBtnradius
            normalColor:  sb.holdActive ? "#4d2e00" : Theme.sideBtnBase
            pressedColor: "#6b4000"
            disabledColor: Theme.btnDisabled
            glowColor: "#e07b20"
            borderWidth: 2
            borderColor: sb.holdActive ? "#e07b20" : "#2a3442"
            enabled: sb._autoReq || sb._manualReq
            active: sb.holdActive
            opacity: (sb._autoReq || sb._manualReq) ? 1.0 : 0.35
            visible: sb.loggedInRole !== 0

            onClicked: { sb.pressHold(); sb.pressed("hold") }

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 6
                text: sb.holdActive ? "Hold  (ON)" : "Hold"
                color: "#ffffff"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sideBtnFont
                font.bold: true
            }
        }

        InteractiveSurface {
            id: bReset
            height: sb.btnH
            width: parent.width
            radius: Theme.sideBtnradius
            normalColor: Theme.sideBtnBase
            pressedColor: Theme.btnPressed
            disabledColor: Theme.btnDisabled
            borderWidth: sb.faultAny ? 3 : 2
            borderColor: sb.faultAny ? "red" : "#2a3442"
            enabled: sb.loggedInRole !== 0
            active: sb.resetActive
            visible: sb.loggedInRole !== 0  // hide if not logged in

            onPressed: { sb.pressReset(true); sb.pressed("reset") }
            onReleased:{ sb.pressReset(false) }

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 6
                text: "Fault Reset"
                color: Theme.sideBtnText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sideBtnFont
                font.bold: true
            }
        }

        InteractiveSurface {
            id: bEstop
            height: sb.btnH
            width: parent.width
            radius: Theme.sideBtnradius
            normalColor: sb.stopButtonColor()
            pressedColor: Theme.btnPressed
            disabledColor: Theme.btnDisabled
            borderWidth: 3
            borderColor: "#000000"
            enabled: true
            active: sb.stopSafe

            onPressed: { sb.pressImstp(true); sb.pressed("estop") }
            onReleased: { sb.pressImstp(false) }

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 6
                text: "STOP"
                color: Theme.sideBtnstopText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sideBtnFont + 4
                font.bold: true
            }
        }
    }
}

