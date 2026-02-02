pragma Singleton
import QtQuick 2.15

QtObject {
    // ============================================================
    // COLOR PALETTE - "Precision Calm"
    // Deep blues for focus, soft contrasts for reduced fatigue
    // ============================================================
    property color bg: "#0b0e13"           // Deep midnight (primary background)
    property color panel: "#151921"        // Elevated surfaces
    property color text: "#e3e8f0"         // Soft white (primary text)
    property color muted: "#8891a8"        // Subdued gray (secondary text)
    property color accent: "#4a9eff"       // Calm blue (primary actions)
    property color danger: "#f87171"       // Soft coral (alerts without alarm)

    // Extended palette for richer UI
    property color success: "#4ade80"      // Soft green (ready states)
    property color warning: "#fbbf24"      // Warm amber (caution states)
    property color surface: "#1a2029"      // Alternate surface
    property color border: "#2a3441"       // Subtle borders
    property color hover: "#1f2937"        // Hover states

    // ============================================================
    // SPACING & SIZING - Generous breathing room
    // ============================================================
    property int pad: 14               // Increased for breathing room
    property int padLg: 20             // Large padding
    property int padSm: 8              // Small padding
    property int gap: 12               // Increased gap
    property int gapSm: 6              // Small gap
    property int btnH: 68              // Slightly reduced for refinement
    property int radius: 12            // Slightly softer corners
    property int radiusLg: 16          // Large radius
    property int radiusSm: 8           // Small radius
    
    // ============================================================
    // TYPOGRAPHY - Clear hierarchy, excellent readability
    // ============================================================
    property string fontFamily: "Segoe UI"
    property string fontFamilyMono: "Consolas"  // For numeric displays
    
    property int h1: 26                // Slightly smaller for refinement
    property int h2: 20                // Better proportions
    property int h3: 18                // Added hierarchy level
    property int body: 16              // Reduced for better density
    property int bodyLg: 18
    property int bodySm: 14
    property int caption: 13           // Small labels
    
    property int fontSmall: 15         // Adjusted
    property int fontMed: 24           // Adjusted
    property int fontLg: 36            // Adjusted
    
    property int tabFont: 22           // More refined tab text
    
    // Font weights (if supported by your QML version)
    property int fontLight: Font.Light
    property int fontNormal: Font.Normal
    property int fontMedium: Font.Medium
    property int fontBold: Font.Bold
    
    // ============================================================
    // SIDEBAR - Refined appearance
    // ============================================================
    property color sideBtnpanel: "#0d1117"      // Darker, more recessed
    property color sideBtnBase: "#1a2029"       // Refined button surface
    property color sideBtnText: "#e3e8f0"       // Consistent with main text
    property color sideBtnaccent: "#4a9eff"     // Consistent accent
    property color sideBtnstopRed: "#ef4444"    // Vivid but not alarming red
    property color sideBtnstopText: "#ffffff"   // Pure white for contrast
    
    property int sideBarW: 280
    property int sideBtngap: 10              // Refined spacing
    property int sideBtnradius: 14           // Consistent radius system
    property int sideBtnFont: 22             // Better proportions
    
    // ============================================================
    // TABS
    // ============================================================
    property int tabOverlap: 75
    property int tabHeight: 56           // Defined tab height
    property int tabRadius: 12           // Tab-specific radius
    
    // ============================================================
    // SHADOWS & DEPTH - Subtle elevation system
    // ============================================================
    property color shadowColor: "#000000"
    property real shadowOpacity: 0.3
    property int shadowRadius: 8
    property int shadowOffsetX: 0
    property int shadowOffsetY: 2
    
    // ============================================================
    // ANIMATION - Smooth, professional transitions
    // ============================================================
    property int animationFast: 150      // Quick feedback
    property int animationNormal: 250    // Standard transitions
    property int animationSlow: 400      // Slower, more dramatic
    
    // ============================================================
    // STATE COLORS - Clear status indicators
    // ============================================================
    property color stateReady: "#4ade80"     // Soft green
    property color stateWelding: "#4a9eff"   // Calm blue
    property color statePaused: "#fbbf24"    // Warm amber
    property color stateFaulted: "#ef4444"   // Alert red
    property color stateDisabled: "#6b7280"  // Neutral gray
    
    // ============================================================
    // INDICATOR COLORS - For LEDs and status dots
    // ============================================================
    property color indicatorOn: "#10b981"     // Bright green
    property color indicatorOff: "#374151"    // Dark gray
    property color indicatorWarning: "#f59e0b" // Orange
    property color indicatorError: "#ef4444"   // Red
    
    // ============================================================
    // PANEL VARIANTS - Different surface types
    // ============================================================
    property color panelElevated: "#1a2029"   // Slightly elevated
    property color panelRecessed: "#0d1117"   // Slightly recessed
    property color panelHighlight: "#1f2937"  // Highlighted state

    // ============================================================
    // BUTTON STATES - Consistent interactive feedback
    // ============================================================
    property color btnNormal: "#1a2029"
    property color btnHover: "#1f2937"
    property color btnPressed: "#151921"
    property color btnDisabled: "#0f1419"
    
    // ============================================================
    // CHART & DATA VIZ - For future analytics
    // ============================================================
    property color chartPrimary: "#4a9eff"
    property color chartSecondary: "#8b5cf6"
    property color chartTertiary: "#ec4899"
    property color chartGrid: "#1f2937"
    property color chartAxis: "#6b7280"
}