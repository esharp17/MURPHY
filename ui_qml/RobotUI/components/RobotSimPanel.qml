import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

import RobotUI 1.0

// ============================================================
// ROBOT SIMULATION BACKDOOR PANEL  ("act as the robot")
// Exercise the full HMI<->robot handshake with NO physical robot
// or network. Toggle the robot INPUT bits by hand (you become the
// robot) and watch the HMI OUTPUT commands update live.
// ============================================================
Item {
    id: root
    anchors.fill: parent
    visible: false

    signal closed()

    // Selected robot index (0..3). Panel "Robot N" == index N-1.
    property int sel: 0

    property var inWords: []
    property var outWords: []
    property int connState: 0
    property bool simulated: false
    property bool showFullBitMap: false

    property var inputBits: [
        { bit: 1,  name: "Ready / Auto" },
        { bit: 3,  name: "Running" },
        { bit: 4,  name: "Paused" },
        { bit: 6,  name: "Fault" },
        { bit: 7,  name: "At Home" },
        { bit: 11, name: "Welding" },
        { bit: 19, name: "Resume Weld Ack" },
        { bit: 20, name: "C-Stop Ack" },
        { bit: 22, name: "Scanning" }
    ]

    property var outputBits: [
        { bit: 2,  name: "OPERATE" },
        { bit: 4,  name: "CYCLE_STOP" },
        { bit: 7,  name: "Go Home cmd" },
        { bit: 9,  name: "PROD_START" },
        { bit: 19, name: "Resume Weld cmd" },
        { bit: 20, name: "C-Stop" }
    ]

    function stateName(s) {
        if (s === 0) return "DISCONNECTED"
        if (s === 1) return "CONNECTING"
        if (s === 2) return "CONNECTED (CYCLIC)"
        if (s === 3) return "FAULTED"
        return "?"
    }

    function bitOf(words, b) {
        if (!words || b <= 0) return false
        var wi = Math.floor((b - 1) / 16)
        var bi = (b - 1) % 16
        if (wi < 0 || wi >= words.length) return false
        var w = Number(words[wi]) & 0xFFFF
        return ((w >> bi) & 1) === 1
    }

    function bitLabel(direction, bitNum) {
        var labels = direction === "in" ? root.inputBits : root.outputBits
        for (var i = 0; i < labels.length; i++) {
            if (labels[i].bit === bitNum) return labels[i].name
        }
        return ""
    }

    property var allHighBits: []

    function refreshHighBits() {
        var result = []
        if (root.inWords) {
            for (var wi = 0; wi < root.inWords.length; wi++) {
                var w = Number(root.inWords[wi]) & 0xFFFF
                if (w === 0) continue
                for (var bi = 0; bi < 16; bi++) {
                    if ((w >> bi) & 1) {
                        var bn = wi * 16 + bi + 1
                        result.push({ bit: bn, dir: "IN", name: root.bitLabel("in", bn) })
                    }
                }
            }
        }
        if (root.outWords) {
            for (var wi2 = 0; wi2 < root.outWords.length; wi2++) {
                var w2 = Number(root.outWords[wi2]) & 0xFFFF
                if (w2 === 0) continue
                for (var bi2 = 0; bi2 < 16; bi2++) {
                    if ((w2 >> bi2) & 1) {
                        var bn2 = wi2 * 16 + bi2 + 1
                        result.push({ bit: bn2, dir: "OUT", name: root.bitLabel("out", bn2) })
                    }
                }
            }
        }
        root.allHighBits = result
    }

    function inPos()  { return (root.inWords  && root.inWords.length  > 4) ? (Number(root.inWords[4])  & 0x03FF) : 0 }
    function outPos() { return (root.outWords && root.outWords.length > 4) ? (Number(root.outWords[4]) & 0x03FF) : 0 }

    function hasComm() { return (typeof RobotComm !== "undefined") && RobotComm }

    function refresh() {
        if (!hasComm()) return
        root.connState = RobotComm.getState(root.sel)
        root.simulated = RobotComm.isSimulated(root.sel)
        root.inWords = RobotComm.getInputs(root.sel)
        root.outWords = RobotComm.getOutputs(root.sel)
        root.refreshHighBits()
    }

    function toggleInput(b) {
        if (!hasComm()) return
        RobotComm.setInputBit(root.sel, b, !bitOf(root.inWords, b))
        refresh()
    }

    function open(robotIdx) {
        root.sel = robotIdx || 0
        root.visible = true
        refresh()
    }

    onVisibleChanged: if (visible) refresh()

    property int pulseBit: -1
    Timer {
        id: pulseTimer
        interval: 400
        repeat: false
        onTriggered: {
            if (root.pulseBit > 0 && root.hasComm()) {
                RobotComm.setInputBit(root.sel, root.pulseBit, false)
                root.pulseBit = -1
                root.refresh()
            }
        }
    }
    function pulseInput(b) {
        if (!hasComm()) return
        RobotComm.setInputBit(root.sel, b, true)
        root.pulseBit = b
        pulseTimer.restart()
        refresh()
    }

    Connections {
        target: root.hasComm() ? RobotComm : null
        enabled: root.visible
        function onIoUpdated(i)    { if (i === root.sel) root.refresh() }
        function onStateChanged(i) { if (i === root.sel) root.refresh() }
    }

    Timer {
        interval: 500; repeat: true; running: root.visible
        onTriggered: root.refresh()
    }

    // ---- dim scrim ----
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.55
        MouseArea { anchors.fill: parent; onClicked: {} }
    }

    // ---- main card ----
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 980)
        height: Math.min(parent.height - 40, 940)
        radius: Theme.radiusLg
        color: Theme.bg
        border.color: Theme.accent
        border.width: 2

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.padLg
            spacing: Theme.pad

            // ===== Header =====
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.pad

                Text {
                    text: "\u26A0  ROBOT SIMULATOR — Act as the Robot"
                    color: Theme.warning
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.h2
                    font.bold: true
                    Layout.fillWidth: true
                }
                Rectangle {
                    Layout.preferredWidth: 120
                    Layout.preferredHeight: 40
                    radius: 6
                    color: bitMapMa.pressed ? Qt.darker(Theme.accent, 1.2) : (root.showFullBitMap ? Theme.accent : Theme.panel)
                    border.color: Theme.accent; border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: root.showFullBitMap ? "\u2190 Back" : "Full Bit Map"
                        color: root.showFullBitMap ? Theme.panel : Theme.accent
                        font.family: Theme.fontFamily; font.pixelSize: Theme.caption; font.bold: true
                    }
                    MouseArea {
                        id: bitMapMa
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showFullBitMap = !root.showFullBitMap
                    }
                }
                Rectangle {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    radius: 20
                    color: closeMa.pressed ? Theme.danger : Theme.panel
                    border.color: Theme.danger; border.width: 1
                    Text { anchors.centerIn: parent; text: "\u2715"; color: Theme.text; font.pixelSize: 18; font.bold: true }
                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.visible = false; root.closed() }
                    }
                }
            }

            // ===== FULL BIT MAP SUB-PAGE =====
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.showFullBitMap
                spacing: Theme.pad

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.pad

                    Text {
                        text: "INPUT BITS (click to toggle)"
                        color: Theme.success
                        font.family: Theme.fontFamily; font.pixelSize: Theme.bodySm; font.bold: true
                        Layout.fillWidth: true
                    }
                    Text {
                        text: "OUTPUT BITS (read-only)"
                        color: Theme.accent
                        font.family: Theme.fontFamily; font.pixelSize: Theme.bodySm; font.bold: true
                        Layout.fillWidth: true
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Theme.pad

                    // ---- Input bits grid ----
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Theme.radiusSm
                        color: Theme.panel
                        border.color: Theme.border; border.width: 1

                        Flickable {
                            anchors.fill: parent
                            anchors.margins: Theme.pad
                            clip: true
                            contentWidth: width
                            contentHeight: inBitsGrid.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                            GridLayout {
                                id: inBitsGrid
                                width: parent.width
                                columns: 8
                                rowSpacing: 3
                                columnSpacing: 3

                                Repeater {
                                    model: 256
                                    delegate: Rectangle {
                                        required property int index
                                        property int bitNum: index + 1
                                        property bool isHigh: root.bitOf(root.inWords, bitNum)
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 32
                                        radius: 3
                                        color: isHigh ? Qt.rgba(0.06,0.72,0.51,0.25) : Theme.bg
                                        border.color: isHigh ? Theme.success : Theme.border
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: parent.bitNum
                                            color: parent.isHigh ? Theme.success : Theme.muted
                                            font.family: Theme.fontFamilyMono
                                            font.pixelSize: Theme.caption
                                            font.bold: true
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.toggleInput(parent.bitNum)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---- Output bits grid ----
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Theme.radiusSm
                        color: Theme.panel
                        border.color: Theme.border; border.width: 1

                        Flickable {
                            anchors.fill: parent
                            anchors.margins: Theme.pad
                            clip: true
                            contentWidth: width
                            contentHeight: outBitsGrid.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                            GridLayout {
                                id: outBitsGrid
                                width: parent.width
                                columns: 8
                                rowSpacing: 3
                                columnSpacing: 3

                                Repeater {
                                    model: 256
                                    delegate: Rectangle {
                                        required property int index
                                        property int bitNum: index + 1
                                        property bool isHigh: root.bitOf(root.outWords, bitNum)
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 32
                                        radius: 3
                                        color: isHigh ? Qt.rgba(0.95,0.52,0.0,0.20) : Theme.bg
                                        border.color: isHigh ? Theme.accent : Theme.border
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: parent.bitNum
                                            color: parent.isHigh ? Theme.accent : Theme.muted
                                            font.family: Theme.fontFamilyMono
                                            font.pixelSize: Theme.caption
                                            font.bold: true
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ===== MAIN PAGE (robot selector + columns + high bits) =====
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !root.showFullBitMap
                spacing: Theme.pad

            // ===== Robot selector =====
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gap
                Repeater {
                    model: 4
                    delegate: Rectangle {
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredHeight: 46
                        radius: Theme.radiusSm
                        color: root.sel === index ? Theme.accent : Theme.panel
                        border.color: (root.hasComm() && RobotComm.isSimulated(index)) ? Theme.success : Theme.border
                        border.width: (root.hasComm() && RobotComm.isSimulated(index)) ? 2 : 1
                        Text {
                            anchors.centerIn: parent
                            text: "Robot " + (index + 1) + ((root.hasComm() && RobotComm.isSimulated(index)) ? "  \u25CF" : "")
                            color: root.sel === index ? Theme.panel : Theme.text
                            font.family: Theme.fontFamily; font.pixelSize: Theme.body; font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.sel = index; root.refresh() }
                        }
                    }
                }
            }

            // ===== Connection controls =====
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gap

                Rectangle {
                    Layout.preferredWidth: 260
                    Layout.preferredHeight: 46
                    radius: Theme.radiusSm
                    color: Theme.panel
                    border.color: Theme.border; border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: "State: " + root.stateName(root.connState) + (root.simulated ? "  [SIM]" : "")
                        color: root.connState === 2 ? Theme.success : (root.connState === 3 ? Theme.danger : Theme.muted)
                        font.family: Theme.fontFamily; font.pixelSize: Theme.bodySm; font.bold: true
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    radius: Theme.radiusSm
                    color: simMa.pressed ? Qt.darker(Theme.success, 1.2) : Theme.success
                    Text {
                        anchors.centerIn: parent; text: "Simulate Connect"
                        color: Theme.panel
                        font.family: Theme.fontFamily; font.pixelSize: Theme.body; font.bold: true
                    }
                    MouseArea {
                        id: simMa
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { if (root.hasComm()) RobotComm.simulateRobot(root.sel); root.refresh() }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    radius: Theme.radiusSm
                    color: discMa.pressed ? Qt.darker(Theme.danger, 1.2) : Theme.panel
                    border.color: Theme.danger; border.width: 1
                    Text {
                        anchors.centerIn: parent; text: "Disconnect"
                        color: Theme.text
                        font.family: Theme.fontFamily; font.pixelSize: Theme.body; font.bold: true
                    }
                    MouseArea {
                        id: discMa
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { if (root.hasComm()) RobotComm.disconnectRobot(root.sel); root.refresh() }
                    }
                }
            }

            // ===== Two columns =====
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.pad

                // ---- LEFT: Robot INPUTS ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusSm
                    color: Theme.panel
                    border.color: Theme.border; border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.pad
                        spacing: Theme.gapSm

                        Text {
                            text: "ROBOT INPUTS  (you drive these)"
                            color: Theme.success
                            font.family: Theme.fontFamily; font.pixelSize: Theme.bodySm; font.bold: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.gapSm
                            Text {
                                text: "Reported Pos:"
                                color: Theme.text
                                font.family: Theme.fontFamily; font.pixelSize: Theme.caption
                                Layout.preferredWidth: 110
                            }
                            Rectangle {
                                Layout.preferredWidth: 90
                                Layout.preferredHeight: 34
                                radius: 4; color: Theme.bg
                                border.color: Theme.accent; border.width: 1
                                TextInput {
                                    id: posInput
                                    anchors.fill: parent; anchors.margins: 6
                                    text: String(root.inPos())
                                    color: Theme.text
                                    font.family: Theme.fontFamilyMono; font.pixelSize: Theme.body
                                    horizontalAlignment: TextInput.AlignHCenter
                                    verticalAlignment: TextInput.AlignVCenter
                                    inputMethodHints: Qt.ImhDigitsOnly
                                    onEditingFinished: {
                                        if (root.hasComm()) RobotComm.setInputPos(root.sel, parseInt(text) || 0)
                                        root.refresh()
                                    }
                                }
                            }
                            Text {
                                text: "\u00B0"; color: Theme.muted
                                font.family: Theme.fontFamily; font.pixelSize: Theme.body
                                Layout.fillWidth: true
                            }
                        }

                        Repeater {
                            model: root.inputBits
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                radius: 4
                                color: root.bitOf(root.inWords, modelData.bit) ? Qt.rgba(0.06,0.72,0.51,0.18) : Theme.bg
                                border.color: root.bitOf(root.inWords, modelData.bit) ? Theme.indicatorOn : Theme.border
                                border.width: 1
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8
                                    Rectangle {
                                        Layout.preferredWidth: 16; Layout.preferredHeight: 16; radius: 8
                                        color: root.bitOf(root.inWords, modelData.bit) ? Theme.indicatorOn : Theme.indicatorOff
                                    }
                                    Text {
                                        text: modelData.name + "  (bit " + modelData.bit + ")"
                                        color: Theme.text
                                        font.family: Theme.fontFamily; font.pixelSize: Theme.caption
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: root.bitOf(root.inWords, modelData.bit) ? "HIGH" : "LOW"
                                        color: root.bitOf(root.inWords, modelData.bit) ? Theme.indicatorOn : Theme.muted
                                        font.family: Theme.fontFamily; font.pixelSize: Theme.caption; font.bold: true
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleInput(modelData.bit)
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        Text {
                            text: "Quick handshakes"
                            color: Theme.muted
                            font.family: Theme.fontFamily; font.pixelSize: Theme.caption
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.gapSm
                            Repeater {
                                model: [
                                    { label: "Ack C-Stop", b: 20, pulse: true },
                                    { label: "Signal Home", b: 7, pulse: false },
                                    { label: "Ack Resume", b: 19, pulse: true }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: 4
                                    color: qaMa.pressed ? Theme.accent : Theme.btnNormal
                                    border.color: Theme.accent; border.width: 1
                                    Text {
                                        anchors.centerIn: parent; text: modelData.label
                                        color: Theme.text
                                        font.family: Theme.fontFamily; font.pixelSize: Theme.caption; font.bold: true
                                    }
                                    MouseArea {
                                        id: qaMa
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (modelData.pulse) root.pulseInput(modelData.b)
                                            else { if (root.hasComm()) RobotComm.setInputBit(root.sel, modelData.b, true); root.refresh() }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- RIGHT: HMI OUTPUTS (read-only) ----
                Rectangle {
                    Layout.preferredWidth: 320
                    Layout.fillHeight: true
                    radius: Theme.radiusSm
                    color: Theme.panel
                    border.color: Theme.border; border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.pad
                        spacing: Theme.gapSm

                        Text {
                            text: "HMI OUTPUTS  (commands sent)"
                            color: Theme.accent
                            font.family: Theme.fontFamily; font.pixelSize: Theme.bodySm; font.bold: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.gapSm
                            Text {
                                text: "Desired Pos:"
                                color: Theme.text
                                font.family: Theme.fontFamily; font.pixelSize: Theme.caption
                                Layout.fillWidth: true
                            }
                            Text {
                                text: root.outPos() + "\u00B0"
                                color: Theme.accent
                                font.family: Theme.fontFamilyMono; font.pixelSize: Theme.body; font.bold: true
                            }
                        }

                        Repeater {
                            model: root.outputBits
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                radius: 4
                                color: Theme.bg
                                border.color: root.bitOf(root.outWords, modelData.bit) ? Theme.accent : Theme.border
                                border.width: 1
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8
                                    Rectangle {
                                        Layout.preferredWidth: 16; Layout.preferredHeight: 16; radius: 8
                                        color: root.bitOf(root.outWords, modelData.bit) ? Theme.accent : Theme.indicatorOff
                                    }
                                    Text {
                                        text: modelData.name + "  (bit " + modelData.bit + ")"
                                        color: Theme.text
                                        font.family: Theme.fontFamily; font.pixelSize: Theme.caption
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: root.bitOf(root.outWords, modelData.bit) ? "HIGH" : "LOW"
                                        color: root.bitOf(root.outWords, modelData.bit) ? Theme.accent : Theme.muted
                                        font.family: Theme.fontFamily; font.pixelSize: Theme.caption; font.bold: true
                                    }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        Text {
                            text: "Tip: Simulate Connect, press C-STOP on the\nCell Status screen, then pulse \"Ack C-Stop\"\nhere to close the window."
                            color: Theme.muted
                            font.family: Theme.fontFamily; font.pixelSize: Theme.caption
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            // ===== All High Bits Monitor (scrollable) =====
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 220
                radius: Theme.radiusSm
                color: Theme.panel
                border.color: Theme.border; border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.pad
                    spacing: Theme.gapSm

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "ALL HIGH BITS"
                            color: Theme.warning
                            font.family: Theme.fontFamily; font.pixelSize: Theme.bodySm; font.bold: true
                        }
                        Text {
                            text: root.allHighBits.length + " bit(s) HIGH  \u2014  scroll to see all"
                            color: Theme.muted
                            font.family: Theme.fontFamily; font.pixelSize: Theme.caption
                            Layout.fillWidth: true
                        }
                    }

                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: width
                        contentHeight: bitsCol.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        Column {
                            id: bitsCol
                            width: parent.width
                            spacing: 2

                            Repeater {
                                model: root.allHighBits
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: bitsCol.width
                                    height: 30
                                    radius: 3
                                    color: modelData.dir === "IN" ? Qt.rgba(0.06, 0.72, 0.51, 0.12) : Qt.rgba(0.95, 0.52, 0.0, 0.10)
                                    border.color: modelData.dir === "IN" ? Theme.success : Theme.accent
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        Rectangle {
                                            Layout.preferredWidth: 38; Layout.preferredHeight: 18
                                            radius: 3
                                            color: modelData.dir === "IN" ? Theme.success : Theme.accent
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.dir
                                                color: Theme.panel
                                                font.family: Theme.fontFamily; font.pixelSize: 10; font.bold: true
                                            }
                                        }
                                        Text {
                                            text: "bit " + modelData.bit
                                            color: Theme.text
                                            font.family: Theme.fontFamilyMono; font.pixelSize: Theme.caption; font.bold: true
                                            Layout.preferredWidth: 70
                                        }
                                        Text {
                                            text: modelData.name || "(unnamed)"
                                            color: modelData.name ? Theme.text : Theme.muted
                                            font.family: Theme.fontFamily; font.pixelSize: Theme.caption
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                            }

                            Text {
                                visible: root.allHighBits.length === 0
                                text: "No bits are currently HIGH"
                                color: Theme.muted
                                font.family: Theme.fontFamily; font.pixelSize: Theme.caption
                                topPadding: 30
                                horizontalAlignment: Text.AlignHCenter
                                width: bitsCol.width
                            }
                        }
                    }
                }
            }
            } // end main page ColumnLayout
        }
    }
}
