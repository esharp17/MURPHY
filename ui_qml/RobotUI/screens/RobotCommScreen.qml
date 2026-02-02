// ui_qml/RobotUI/screens/RobotCommScreen.qml
// UPDATED: Scrollable I/O grids + load I/O names from JSON per-robot in:
//   C:\Py\Murphy\ui_qml\RobotUI\assets\IO_config_Robot_N.json
//
// Expected JSON shape (example keys):
//   { "DI1": {"label":"IMSTP"}, ..., "DO1": {"label":"CMD Enabled"}, ... }


import QtQuick 2.15
import QtQuick.Controls 2.15
import RobotUI 1.0

Item {
    id: root
    anchors.fill: parent
    anchors.margins: 10

    property int loggedInRole: 0  // User's current role (0=NONE, 1=OPERATOR, 2=TECHNICIAN, 3=ADMIN)

    // ----------------------------
    // Auto-connect behavior
    // ----------------------------
    Timer {
        id: autoConnectTimer
        interval: 5000
        repeat: true
        running: true
        onTriggered: {
            refresh()
            if (state !== 2) {
                RobotComm.connectRobot(robotIndex+1)
            }
        }
    }

    // ----------------------------
    // Data model (per selected robot)
    // ----------------------------
    property int robotIndex: 0

    property var inputsWords: []     // ROBOT -> HMI (RX)
    property var outputsWords: []    // HMI -> ROBOT (TX)

    property int state: 0
    property int lastRxMs: 0
    property string faultText: ""

    // ----------------------------
    // Local layout tuning
    // ----------------------------
    property int tile_H: 28
    property int tile_PAD: 2
    property int led_SZ: 12
    property int grid_GAP: 6

    // ----------------------------
    // I/O naming (loaded from JSON)
    // - outNames = DI1..DI32 labels (HMI->ROBOT)
    // - inNames  = DO1..DO32 labels (ROBOT->HMI)
    property var outNames: []
    property var inNames:  []

    function _defaultOutNames() {
        var a = []
        for (var i = 1; i <= 32; i++) a.push("OUT" + i)
        return a
    }
    function _defaultInNames() {
        var a = []
        for (var i = 1; i <= 32; i++) a.push("IN" + i)
        return a
    }

    function _ioFileUrlForRobot(idx) {
        var n = idx + 1
        // relative to this QML file; works in dev + PyInstaller
        return Qt.resolvedUrl("../assets/IO_config_Robot_" + n + ".json")
    }

    // Expected JSON: { "DI1": {"label":"..."}, ..., "DO1": {"label":"..."}, ... }
    function loadIoNames() {
        outNames = _defaultOutNames()
        inNames  = _defaultInNames()

        var url = _ioFileUrlForRobot(robotIndex)
        console.log("IO_CONFIG load:", url)

        var xhr = new XMLHttpRequest()
        xhr.open("GET", url)
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return

            console.log("IO_CONFIG status:", xhr.status, "bytes:", xhr.responseText ? xhr.responseText.length : 0)

            // file:// often returns 0 on success
            if (!(xhr.status === 200 || xhr.status === 0)) return
            if (!xhr.responseText || xhr.responseText.length < 2) return

            var obj
            try { obj = JSON.parse(xhr.responseText) }
            catch (e) { console.log("IO_CONFIG JSON parse fail:", e); return }

            var o = []
            var inn = []
            for (var i = 1; i <= 32; i++) {
                var dik = "DI" + i
                var dok = "DO" + i
                o.push((obj[dik] && obj[dik].label) ? obj[dik].label : ("OUT" + i))
                inn.push((obj[dok] && obj[dok].label) ? obj[dok].label : ("IN" + i))
            }
            outNames = o
            inNames  = inn
            console.log("IO_CONFIG loaded for robot", robotIndex + 1)
        }
        xhr.send()
    }

    // ----------------------------
    // Helpers
    // ----------------------------
    function bitFromWords(words, bitIndex) {
        if (!words || words.length === 0) return 0
        var wi = Math.floor(bitIndex / 16)
        var bi = bitIndex % 16
        if (wi < 0 || wi >= words.length) return 0
        var w = Number(words[wi]) & 0xFFFF
        return (w >> bi) & 1
    }

    function refresh() {
        state = RobotComm.getState(robotIndex)
        inputsWords = RobotComm.getInputs(robotIndex)
        outputsWords = RobotComm.getOutputs(robotIndex)
        lastRxMs = RobotComm.getLastRxMs(robotIndex)
        faultText = RobotComm.getFault(robotIndex)
    }

    Component.onCompleted: {
        refresh()
        loadIoNames()
    }

    Connections {
        target: RobotComm

        function onIoUpdated(i) { if (i === robotIndex) refresh() }
        function onStateChanged(i) { if (i === robotIndex) refresh() }
        function onFaulted(i, text) { if (i === robotIndex) refresh() }
        function onConfigChanged(i) { if (i === robotIndex) refresh() }
        function onLogUpdated(i) { }
    }

    Timer {
        interval: 250
        repeat: true
        running: true
        onTriggered: refresh()
    }

    // ----------------------------
    // Layout
    // ----------------------------
    Column {
        anchors.fill: parent
        anchors.margins: Theme.pad
        spacing: Theme.pad

        Row {
            id: topBar
            width: parent.width
            height: Theme.btnH - 5
            spacing: Theme.gap
            z: 1000

            Row {
                id: robotBtns
                width: Math.max(0, topBar.width - configBtn.width - Theme.gap)
                height: parent.height
                spacing: Theme.gap
                clip: true

                Repeater {
                    model: 4
                    delegate: Rectangle {
                        width: (robotBtns.width - (Theme.gap * 3)) / 4
                        height: robotBtns.height
                        radius: Theme.radius
                        color: (index === robotIndex) ? Theme.accent : Theme.panel

                        Text {
                            anchors.centerIn: parent
                            text: "ROBOT " + (index + 1)
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.h2
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                robotIndex = index
                                refresh()
                                loadIoNames()
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: configBtn
                width: 140
                height: parent.height
                radius: Theme.radius
                color: Theme.panel
                z: 2000
                visible: root.loggedInRole !== 0 && root.loggedInRole !== 1  // hide if not logged in or operator

                Text {
                    anchors.centerIn: parent
                    text: "CONFIG"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.h2
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    preventStealing: true
                    onClicked: {
                        var c = RobotComm.getConfig(robotIndex)
                        configPopup.ip     = c.ip
                        configPopup.port   = "" + c.port
                        configPopup.slot   = "" + c.slot
                        configPopup.inSize = "" + c.in_words
                        configPopup.outSize= "" + c.out_words
                        configPopup.open()
                    }
                }
            }
        }

        Row {
            id: gridsRow
            width: parent.width
            height: parent.height - topBar.height - (Theme.pad * 2)
            spacing: Theme.gap

            // LEFT PANEL: HMI → ROBOT (Outputs)
            Rectangle {
                id: outputsPanel
                width: (gridsRow.width - Theme.gap) / 2
                height: gridsRow.height
                radius: Theme.radius
                color: Theme.panel

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.pad
                    spacing: Theme.pad

                    Text {
                        text: "HMI → ROBOT (Outputs)"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.h2
                        font.bold: true
                    }

                    ScrollView {
                        width: parent.width
                        height: parent.height - parent.spacing - 20
                        clip: true
                        
                        ScrollBar.vertical.policy: ScrollBar.AsNeeded
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                        Grid {
                            id: outGrid
                            width: outputsPanel.width - Theme.pad * 2 - 10
                            columns: 2
                            columnSpacing: grid_GAP
                            rowSpacing: grid_GAP

                            Repeater {
                                model: 32
                                delegate: Rectangle {
                                    width: (outGrid.width - (outGrid.columnSpacing * (outGrid.columns - 1))) / outGrid.columns
                                    height: tile_H
                                    radius: Theme.radius
                                    color: Theme.bg

                                    readonly property int bitIndex: index
                                    readonly property int bitVal: root.bitFromWords(root.outputsWords, bitIndex)

                                    Row {
                                        anchors.fill: parent
                                        anchors.margins: tile_PAD
                                        spacing: 10

                                        Rectangle {
                                            width: led_SZ
                                            height: led_SZ
                                            radius: led_SZ / 2
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: bitVal ? "#00ff3a" : "#003300"
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: (root.outNames && root.outNames.length > bitIndex) ? root.outNames[bitIndex] : ("OUT" + (bitIndex + 1))
                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.body
                                            font.bold: true
                                            elide: Text.ElideRight
                                            width: parent.width - (led_SZ + 18)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // RIGHT PANEL: ROBOT → HMI (Inputs)
            Rectangle {
                id: inputsPanel
                width: (gridsRow.width - Theme.gap) / 2
                height: gridsRow.height
                radius: Theme.radius
                color: Theme.panel

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.pad
                    spacing: Theme.pad

                    Text {
                        text: "ROBOT → HMI (Inputs)"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.h2
                        font.bold: true
                    }

                    ScrollView {
                        width: parent.width
                        height: parent.height - parent.spacing - 20
                        clip: true
                        
                        ScrollBar.vertical.policy: ScrollBar.AsNeeded
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                        Grid {
                            id: inGrid
                            width: inputsPanel.width - Theme.pad * 2 - 10
                            columns: 2
                            columnSpacing: grid_GAP
                            rowSpacing: grid_GAP

                            Repeater {
                                model: 32
                                delegate: Rectangle {
                                    width: (inGrid.width - (inGrid.columnSpacing * (inGrid.columns - 1))) / inGrid.columns
                                    height: tile_H
                                    radius: Theme.radius
                                    color: Theme.bg

                                    readonly property int bitIndex: index
                                    readonly property int bitVal: root.bitFromWords(root.inputsWords, bitIndex)

                                    Row {
                                        anchors.fill: parent
                                        anchors.margins: tile_PAD
                                        spacing: 10

                                        Rectangle {
                                            width: led_SZ
                                            height: led_SZ
                                            radius: led_SZ / 2
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: bitVal ? "#00ff3a" : "#003300"
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: (root.inNames && root.inNames.length > bitIndex) ? root.inNames[bitIndex] : ("IN" + (bitIndex + 1))
                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.body
                                            font.bold: true
                                            elide: Text.ElideRight
                                            width: parent.width - (led_SZ + 18)
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

    // ----------------------------
    // Config popup
    // ----------------------------
    Popup {
        id: configPopup
        modal: true
        focus: true
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
        width: Math.min(root.width * 0.8, 700)
        height: Math.min(root.height * 0.8, 500)
        x: (root.width - width) / 2
        y: (root.height - height) / 2

        property string ip: "192.168.2.1"
        property string port: "44818"
        property string slot: "1"
        property string inSize: "4"
        property string outSize: "4"

        background: Rectangle { radius: Theme.radius; color: Theme.panel }

        Column {
            anchors.fill: parent
            anchors.margins: Theme.pad
            spacing: Theme.gap

            Text {
                text: "ROBOT CONFIG"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.h1
                font.bold: true
            }

            Text {
                text: "Robot " + (root.robotIndex + 1)
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.body
            }

            Rectangle { width: parent.width; height: 2; color: Theme.bg }

            Column {
                width: parent.width
                spacing: Theme.gap

                Row {
                    width: parent.width
                    spacing: Theme.gap
                    Text { width: 220; text: "ROBOT_IP"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.body; anchors.verticalCenter: parent.verticalCenter }
                    TextField { width: parent.width - 230; text: configPopup.ip; onTextChanged: configPopup.ip = text; font.pixelSize: Theme.body }
                }

                Row {
                    width: parent.width
                    spacing: Theme.gap
                    Text { width: 220; text: "EIP_PORT"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.body; anchors.verticalCenter: parent.verticalCenter }
                    TextField { width: parent.width - 230; text: configPopup.port; onTextChanged: configPopup.port = text; font.pixelSize: Theme.body }
                }

                Row {
                    width: parent.width
                    spacing: Theme.gap
                    Text { width: 220; text: "ETH_SLOT"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.body; anchors.verticalCenter: parent.verticalCenter }
                    TextField { width: parent.width - 230; text: configPopup.slot; onTextChanged: configPopup.slot = text; font.pixelSize: Theme.body }
                }

                Row {
                    width: parent.width
                    spacing: Theme.gap
                    Text { width: 220; text: "INPUT_SIZE (words)"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.body; anchors.verticalCenter: parent.verticalCenter }
                    TextField { width: parent.width - 230; text: configPopup.inSize; onTextChanged: configPopup.inSize = text; font.pixelSize: Theme.body }
                }

                Row {
                    width: parent.width
                    spacing: Theme.gap
                    Text { width: 220; text: "OUTPUT_SIZE (words)"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.body; anchors.verticalCenter: parent.verticalCenter }
                    TextField { width: parent.width - 230; text: configPopup.outSize; onTextChanged: configPopup.outSize = text; font.pixelSize: Theme.body }
                }
            }

            Item { width: 1; height: 1 }

            Row {
                width: parent.width
                spacing: Theme.gap

                Rectangle {
                    width: (parent.width - Theme.gap) / 2
                    height: Theme.btnH
                    radius: Theme.radius
                    color: Theme.bg
                    Text { anchors.centerIn: parent; text: "CLOSE"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.h2; font.bold: true }
                    MouseArea { anchors.fill: parent; onClicked: configPopup.close() }
                }

                Rectangle {
                    width: (parent.width - Theme.gap) / 2
                    height: Theme.btnH
                    radius: Theme.radius
                    color: Theme.accent
                    Text { anchors.centerIn: parent; text: "APPLY"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.h2; font.bold: true }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            RobotComm.setConfig(
                                root.robotIndex,
                                configPopup.ip,
                                parseInt(configPopup.port),
                                parseInt(configPopup.slot),
                                parseInt(configPopup.inSize),
                                parseInt(configPopup.outSize)
                            )
                            configPopup.close()
                        }
                    }
                }
            }
        }
    }
}