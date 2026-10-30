// Theme backend for a desktop build: the live KDE colour scheme and metrics.
//
// This is the only file in the shell that imports Kirigami, and it is loaded
// only when no ClamOS theme is active, so a ClamOS build never initialises the
// KDE QML stack.
//
// Kirigami only publishes the per-context palettes (view, selection, header,
// button, tooltip) through its attached colour set, which a plain theme object
// cannot use. The tokens are therefore derived from the base palette: a desktop
// window's header and view are the window colours, selection is the highlight
// pair, and so on.

import QtQuick
import org.kde.kirigami as Kirigami

QtObject {
	property color textColor: Kirigami.Theme.textColor
	property color disabledTextColor: Kirigami.Theme.disabledTextColor
	property color backgroundColor: Kirigami.Theme.backgroundColor
	property color alternateBackgroundColor: Kirigami.Theme.alternateBackgroundColor

	property color highlightColor: Kirigami.Theme.highlightColor
	property color highlightedTextColor: Kirigami.Theme.highlightedTextColor
	property color activeTextColor: Kirigami.Theme.activeTextColor
	property color activeBackgroundColor: Kirigami.Theme.activeBackgroundColor
	property color hoverColor: Kirigami.Theme.hoverColor
	property color focusColor: Kirigami.Theme.focusColor

	property color linkColor: Kirigami.Theme.linkColor
	property color linkBackgroundColor: Kirigami.Theme.linkBackgroundColor
	property color visitedLinkColor: Kirigami.Theme.visitedLinkColor
	property color visitedLinkBackgroundColor: Kirigami.Theme.visitedLinkBackgroundColor

	property color negativeTextColor: Kirigami.Theme.negativeTextColor
	property color negativeBackgroundColor: Kirigami.Theme.negativeBackgroundColor
	property color neutralTextColor: Kirigami.Theme.neutralTextColor
	property color neutralBackgroundColor: Kirigami.Theme.neutralBackgroundColor

	property color buttonTextColor: Kirigami.Theme.textColor
	property color buttonBackgroundColor: Kirigami.Theme.backgroundColor
	property color buttonAlternateBackgroundColor: Kirigami.Theme.alternateBackgroundColor
	property color buttonHoverColor: Kirigami.Theme.highlightColor
	property color buttonFocusColor: Kirigami.Theme.highlightColor

	property color viewTextColor: Kirigami.Theme.textColor
	property color viewBackgroundColor: Kirigami.Theme.backgroundColor
	property color viewAlternateBackgroundColor: Kirigami.Theme.alternateBackgroundColor
	property color viewHoverColor: Kirigami.Theme.highlightColor
	property color viewFocusColor: Kirigami.Theme.highlightColor

	property color selectionTextColor: Kirigami.Theme.highlightedTextColor
	property color selectionBackgroundColor: Kirigami.Theme.highlightColor
	property color selectionAlternateBackgroundColor: Kirigami.Theme.highlightColor
	property color selectionHoverColor: Kirigami.Theme.highlightColor
	property color selectionFocusColor: Kirigami.Theme.highlightColor

	property color headerTextColor: Kirigami.Theme.textColor
	property color headerBackgroundColor: Kirigami.Theme.backgroundColor
	property color headerAlternateBackgroundColor: Kirigami.Theme.alternateBackgroundColor
	property color headerHoverColor: Kirigami.Theme.highlightColor
	property color headerFocusColor: Kirigami.Theme.highlightColor

	property color tooltipTextColor: Kirigami.Theme.textColor
	property color tooltipBackgroundColor: Kirigami.Theme.alternateBackgroundColor

	property font defaultFont: Kirigami.Theme.defaultFont
	property font smallFont: Kirigami.Theme.smallFont

	property real gridUnit: Kirigami.Units.gridUnit
	property real smallSpacing: Kirigami.Units.smallSpacing
	property real mediumSpacing: Kirigami.Units.mediumSpacing
	property real largeSpacing: Kirigami.Units.largeSpacing
	property real cornerRadius: Kirigami.Units.cornerRadius
	property real smallRadius: 2

	property int iconSizeSmall: Kirigami.Units.iconSizes.small
	property int iconSizeSmallMedium: Kirigami.Units.iconSizes.smallMedium
	property int iconSizeMedium: Kirigami.Units.iconSizes.medium
	property int iconSizeLarge: Kirigami.Units.iconSizes.large
	property int iconSizeHuge: Kirigami.Units.iconSizes.huge
}
