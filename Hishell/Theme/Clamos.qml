// Theme backend for ClamOS: the tokens the ClamOS theme singleton publishes.
//
// The mapping is the same one the ClamOS Kirigami definition used, so a shell
// that ran on Kirigami before this backend looks identical afterwards.

import QtQuick
import ClamOS.Theme

QtObject {
	property color textColor: ClamTheme.textColor
	property color disabledTextColor: ClamTheme.disabledTextColor
	property color backgroundColor: ClamTheme.windowColor
	property color alternateBackgroundColor: ClamTheme.surfaceAltColor

	property color highlightColor: ClamTheme.accentColor
	property color highlightedTextColor: ClamTheme.accentTextColor
	property color activeTextColor: ClamTheme.accentTextColor
	property color activeBackgroundColor: ClamTheme.accentColor
	property color hoverColor: ClamTheme.accentColor
	property color focusColor: ClamTheme.accentColor

	property color linkColor: ClamTheme.linkColor
	property color linkBackgroundColor: ClamTheme.linkColor
	property color visitedLinkColor: ClamTheme.textMutedColor
	property color visitedLinkBackgroundColor: ClamTheme.textMutedColor

	property color negativeTextColor: ClamTheme.dangerColor
	property color negativeBackgroundColor: ClamTheme.dangerColor
	property color neutralTextColor: ClamTheme.warningColor
	property color neutralBackgroundColor: ClamTheme.warningColor
	property color positiveTextColor: ClamTheme.successColor
	property color positiveBackgroundColor: ClamTheme.successColor

	property color buttonTextColor: ClamTheme.textColor
	property color buttonBackgroundColor: ClamTheme.surfaceColor
	property color buttonAlternateBackgroundColor: ClamTheme.surfaceAltColor
	property color buttonHoverColor: ClamTheme.accentColor
	property color buttonFocusColor: ClamTheme.accentColor

	property color viewTextColor: ClamTheme.textColor
	property color viewBackgroundColor: ClamTheme.surfaceColor
	property color viewAlternateBackgroundColor: ClamTheme.surfaceAltColor
	property color viewHoverColor: ClamTheme.accentColor
	property color viewFocusColor: ClamTheme.accentColor

	property color selectionTextColor: ClamTheme.accentTextColor
	property color selectionBackgroundColor: ClamTheme.accentColor
	property color selectionAlternateBackgroundColor: ClamTheme.accentColor
	property color selectionHoverColor: ClamTheme.accentColor
	property color selectionFocusColor: ClamTheme.accentColor

	property color headerTextColor: ClamTheme.headerTextColor
	property color headerBackgroundColor: ClamTheme.headerColor
	property color headerAlternateBackgroundColor: ClamTheme.headerColor
	property color headerHoverColor: ClamTheme.accentColor
	property color headerFocusColor: ClamTheme.accentColor

	property color tooltipTextColor: ClamTheme.tooltipTextColor
	property color tooltipBackgroundColor: ClamTheme.tooltipColor

	property font defaultFont: Qt.font({
		family: ClamTheme.fontFamily,
		pixelSize: ClamTheme.fontSize,
		weight: ClamTheme.fontWeight
	})
	property font smallFont: Qt.font({
		family: ClamTheme.fontFamily,
		pixelSize: ClamTheme.smallFontSize,
		weight: ClamTheme.fontWeight
	})

	// The ClamOS theme leaves the control metrics to the toolkit, which used
	// Kirigami's defaults; these are those defaults, kept so the layout does
	// not move when the backend changes.
	property real gridUnit: 18
	property real smallSpacing: 4
	property real mediumSpacing: 6
	property real largeSpacing: 8
	property real cornerRadius: 5
	property real smallRadius: 2

	property int iconSizeSmall: 16
	property int iconSizeSmallMedium: 22
	property int iconSizeMedium: 32
	property int iconSizeLarge: 48
	property int iconSizeHuge: 64
}
