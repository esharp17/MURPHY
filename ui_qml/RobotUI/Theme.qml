pragma Singleton
import QtQuick 2.15

QtObject {
    // colors
    property color bg: "#0f1115"
    property color panel: "#151a22"
    property color text: "#e8ecf2"
    property color muted: "#a7b0bf"
    property color accent: "#3b82f6"
    property color danger: "#ef4444"

    // sizing
    property int pad: 12
    property int gap: 10
    property int btnH: 72
    property int radius: 14

    // typography
    property string fontFamily: "Segoe UI"
    property int h1: 28
    property int h2: 22
    property int body: 18
    property int fontSmall: 16
    property int fontMed: 28
    property int fontLg: 40
    property int tabFont: 28


    property color sideBtnpanel:   "#0f1115"   // darker panel
    property color sideBtnBase:    "#151a22"   // button fill
    property color sideBtnText:    "#e8eef7"
    property color sideBtnaccent:  "#3b82f6"
    property color sideBtnstopRed: "#ef4444"
    property color sideBtnstopText:"#000000"

    property int sideBarW: 280
    property int sideBtngap: 12
    property int sideBtnradius: 18
    property int sideBtnFont: 26


    //Tabs
    property int tabOverlap: 75



}
