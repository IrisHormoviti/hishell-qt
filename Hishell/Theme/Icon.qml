import QtQuick
import Hishell

// A themed icon, independent of the icon toolkit.
//
// `source` is either an image path/URL the shell already rendered (the file
// view's icons are cached PNGs) or a theme icon name. Names are rendered once
// to a PNG by the host and reused, which keeps the decode off the GUI thread on
// every delegate.

Item {
	id: icon

	property string source: ""
	// Physical pixel size the name is rendered at; 0 follows the item size.
	property int pixelSize: 0
	property bool smooth: true

	implicitWidth: Units.iconSizes.medium
	implicitHeight: Units.iconSizes.medium

	readonly property bool isImageSource: icon.source === ""
		|| icon.source.indexOf("file:") === 0
		|| icon.source.indexOf("qrc:") === 0
		|| icon.source.indexOf("/") === 0

	readonly property int renderSize: icon.pixelSize > 0
		? icon.pixelSize
		: Math.max(16, Math.round(Math.max(icon.width, icon.height) * (Screen.devicePixelRatio || 1)))

	// Themed names are rendered with the accent the theme marks, the way KDE
	// applications draw folder icons. Re-evaluates when the theme changes.
	readonly property string resolved: {
		if (icon.source === "")
			return ""
		if (icon.isImageSource)
			return icon.source
		return ThemeIcons.resolve(icon.source, icon.renderSize,
			String(Theme.highlightColor), String(Theme.highlightedTextColor))
	}

	Image {
		anchors.fill: parent
		source: icon.resolved
		sourceSize.width: icon.renderSize
		sourceSize.height: icon.renderSize
		fillMode: Image.PreserveAspectFit
		smooth: icon.smooth
		asynchronous: true
	}
}
