pragma Singleton

// The spacing scale the layout uses. Kept as its own singleton so component
// code reads `Units.gridUnit` rather than reaching through the theme, and so a
// backend can supply platform metrics without every call site changing.

import QtQuick

QtObject {
	id: units

	readonly property real gridUnit: Theme.gridUnit
	readonly property real smallSpacing: Theme.smallSpacing
	readonly property real mediumSpacing: Theme.mediumSpacing
	readonly property real largeSpacing: Theme.largeSpacing
	readonly property real cornerRadius: Theme.cornerRadius
	readonly property real smallRadius: Theme.smallRadius

	readonly property QtObject iconSizes: QtObject {
		readonly property int small: Theme.iconSizeSmall
		readonly property int smallMedium: Theme.iconSizeSmallMedium
		readonly property int medium: Theme.iconSizeMedium
		readonly property int large: Theme.iconSizeLarge
		readonly property int huge: Theme.iconSizeHuge
		readonly property int enormous: Theme.iconSizeHuge * 2
	}
}
