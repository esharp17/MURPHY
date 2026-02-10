import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

import RobotUI 1.0

ApplicationWindow {
    id: win
    width: 1920
    height: 1200
    visible: true
    title: "Robot UI"
    color: Theme.bg

    property int tabIndex: 0
    property bool sessionLoggedIn: false
    property string sessionUser: ""
    property string sessionUserFirstName: ""
    property bool sessionIsAdmin: false
    property int sessionRole: 0  // Role enum: 0=NONE, 1=OPERATOR, 2=TECHNICIAN, 3=ADMIN

    // Persistent weld screen state
    property bool weldPreCheckConfirmed: false
    property bool weldShowWeldRecord: false
    property string weldId: ""
    property string weldProject: ""
    property string weldClient: ""
    property string weldComments: ""
    property string weldUpstreamHeat: ""
    property string weldDownstreamHeat: ""
    property bool weldShowScanView: false
    property bool weldScanDataLoaded: false
    property real weldScanAzim: 140
    property real weldScanElev: 20
    property real weldScanZoom: 1.0

// Main.qml (ApplicationWindow)
// Global robot comm watchdog:
// - tries to connect all 4 robots on startup
// - retries every 5 seconds for any robot not in CYCLIC

Timer {
    id: robotCommWatchdog
    interval: 5000
    repeat: true
    running: true

    function tick() {
        for (var i = 0; i < 4; i++) {
            var st = RobotComm.getState(i)
            // CYCLIC == 2 (your existing mapping)
            if (st !== 2) {
                RobotComm.connectRobot(i)
            }
        }
    }

    onTriggered: tick()
    Component.onCompleted: tick()   // immediate attempt at app start
}


    // Drives tab label swap (Splash <-> Admin)
    property bool adminLoggedIn: false

    Item {
        anchors.fill: parent

        // RIGHT SIDEBAR
        SideBar {
            id: sidebar
            bridge: RobotCommBridge
            robotIndex: 0
            loggedInRole: win.sessionRole
            width: Theme.sideBarW


            anchors.top: parent.top
            anchors.right: parent.right
            anchors.bottom: parent.bottom

            anchors.topMargin: Theme.pad
            anchors.rightMargin: Theme.pad
            anchors.bottomMargin: Theme.pad
        }

        // BOTTOM TABS (always visible)
        TabBar {
            id: tabs
            anchors.left: parent.left
            anchors.right: sidebar.left
            anchors.bottom: parent.bottom

            anchors.leftMargin: Theme.pad
            anchors.rightMargin: Theme.gap
            anchors.bottomMargin: Theme.pad

            z: 1

            labels: [
                win.adminLoggedIn ? "Admin" : "Login",
                "Robot Comm",
                "Cell Status",
                "Welding"
            ]

            sessionRole: win.sessionRole
            currentIndex: win.tabIndex

            onTabSelected: (i) => {
                // Check if user has permission to access this page
                if (!PermissionChecker.canAccessPage(i, win.sessionRole)) {
                    console.log("Access denied to page " + i + " with role " + win.sessionRole)
                    return
                }
                win.tabIndex = i
            }

            // safety net if someone sets tabIndex directly
            onCurrentIndexChanged: {
                if (!PermissionChecker.canAccessPage(currentIndex, win.sessionRole)) {
                    win.tabIndex = 0
                }
            }
        }

        // LEFT MAIN CONTENT
        Rectangle {
            id: contentFrame
            z: 10
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: sidebar.left
            anchors.bottom: parent.bottom

            anchors.topMargin: Theme.pad
            anchors.leftMargin: Theme.pad
            anchors.rightMargin: Theme.gap
            anchors.bottomMargin: Theme.tabOverlap

            radius: Theme.radius
            color: Theme.panel

            border.width: 6
            border.color: tabs.activeColor

            Loader {
                anchors.fill: parent
                anchors.margins: Theme.pad

                sourceComponent: (
                    win.tabIndex === 0 ? splash :
                    win.tabIndex === 1 ? robot  :
                    win.tabIndex === 2 ? status :
                    win.tabIndex === 3 ? weld   :
                    splash
                )
            }
        }
    }

    // Combined Splash/Admin screen
    Component {
        id: splash
        SplashAdminScreen {
            // pull state from Main -> screen
            loggedIn: win.sessionLoggedIn
            loggedInUser: win.sessionUser
            loggedInIsAdmin: win.sessionIsAdmin

            // keep label swap in sync
            adminModeActive: loggedIn && loggedInIsAdmin
            onAdminModeActiveChanged: win.adminLoggedIn = adminModeActive

            // push state from screen -> Main
            onLoggedInChanged: win.sessionLoggedIn = loggedIn
            onLoggedInUserChanged: win.sessionUser = loggedInUser
            onLoggedInUserFirstNameChanged: win.sessionUserFirstName = loggedInUserFirstName
            onLoggedInIsAdminChanged: win.sessionIsAdmin = loggedInIsAdmin
            onLoggedInRoleChanged: win.sessionRole = loggedInRole
        }
    }

    Component { id: robot;  RobotCommScreen { loggedInRole: win.sessionRole } }
    Component { id: status; CellStatusScreen {} }
    Component {
        id: weld
        WeldingScreen {
            loggedInUserFirstName: win.sessionUserFirstName
            preCheckConfirmed: win.weldPreCheckConfirmed
            showWeldRecord: win.weldShowWeldRecord
            weldId: win.weldId
            weldProject: win.weldProject
            weldClient: win.weldClient
            weldComments: win.weldComments
            weldUpstreamHeat: win.weldUpstreamHeat
            weldDownstreamHeat: win.weldDownstreamHeat
            onPreCheckConfirmedChanged: win.weldPreCheckConfirmed = preCheckConfirmed
            onShowWeldRecordChanged: win.weldShowWeldRecord = showWeldRecord
            onWeldIdChanged: win.weldId = weldId
            onWeldProjectChanged: win.weldProject = weldProject
            onWeldClientChanged: win.weldClient = weldClient
            onWeldCommentsChanged: win.weldComments = weldComments
            onWeldUpstreamHeatChanged: win.weldUpstreamHeat = weldUpstreamHeat
            onWeldDownstreamHeatChanged: win.weldDownstreamHeat = weldDownstreamHeat
            showScanView: win.weldShowScanView
            scanDataLoaded: win.weldScanDataLoaded
            scanAzim: win.weldScanAzim
            scanElev: win.weldScanElev
            scanZoom: win.weldScanZoom
            onShowScanViewChanged: win.weldShowScanView = showScanView
            onScanDataLoadedChanged: win.weldScanDataLoaded = scanDataLoaded
            onScanAzimChanged: win.weldScanAzim = scanAzim
            onScanElevChanged: win.weldScanElev = scanElev
            onScanZoomChanged: win.weldScanZoom = scanZoom
        }
    }
}
