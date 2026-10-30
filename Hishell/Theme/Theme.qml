pragma Singleton

// The shell's theme tokens, independent of where the colours come from.
//
// A backend object supplies the same property names as the tokens below. The
// backend is chosen at runtime, so this file (and every app component) knows
// nothing about KDE or ClamOS:
//
//   * a ClamOS theme file (`~/.config/clam/theme.ini`) selects Clamos.qml,
//     which reads the ClamOS theme singleton;
//   * otherwise Kde.qml follows the live KDE colour scheme, so the desktop
//     build keeps the desktop palette.
//
// With no backend the defaults below keep the UI renderable.

import QtQuick
import Hishell

QtObject {
	id: theme

	property QtObject backend: null
	// "clamos", "kde" or "" for the built-in defaults. Useful in logs.
	property string backendName: ""

	// ── Colours ───────────────────────────────────────────────────────────
	readonly property color textColor: theme.token("textColor", "#24222a")
	readonly property color disabledTextColor: theme.token("disabledTextColor", "#a29eaa")
	readonly property color backgroundColor: theme.token("backgroundColor", "#e9e7ee")
	readonly property color alternateBackgroundColor: theme.token("alternateBackgroundColor", "#f2f0f7")

	readonly property color highlightColor: theme.token("highlightColor", "#8a6ff0")
	readonly property color highlightedTextColor: theme.token("highlightedTextColor", "#ffffff")
	readonly property color activeTextColor: theme.token("activeTextColor", "#ffffff")
	readonly property color activeBackgroundColor: theme.token("activeBackgroundColor", "#8a6ff0")
	readonly property color hoverColor: theme.token("hoverColor", "#8a6ff0")
	readonly property color focusColor: theme.token("focusColor", "#8a6ff0")

	readonly property color linkColor: theme.token("linkColor", "#6f57c9")
	readonly property color linkBackgroundColor: theme.token("linkBackgroundColor", "#6f57c9")
	readonly property color visitedLinkColor: theme.token("visitedLinkColor", "#6f6b7a")
	readonly property color visitedLinkBackgroundColor: theme.token("visitedLinkBackgroundColor", "#6f6b7a")

	readonly property color negativeTextColor: theme.token("negativeTextColor", "#c94f6d")
	readonly property color negativeBackgroundColor: theme.token("negativeBackgroundColor", "#c94f6d")
	readonly property color neutralTextColor: theme.token("neutralTextColor", "#c9893f")
	readonly property color neutralBackgroundColor: theme.token("neutralBackgroundColor", "#c9893f")
	readonly property color positiveTextColor: theme.token("positiveTextColor", "#4f9d69")
	readonly property color positiveBackgroundColor: theme.token("positiveBackgroundColor", "#4f9d69")

	readonly property color buttonTextColor: theme.token("buttonTextColor", "#24222a")
	readonly property color buttonBackgroundColor: theme.token("buttonBackgroundColor", "#ffffff")
	readonly property color buttonAlternateBackgroundColor: theme.token("buttonAlternateBackgroundColor", "#f2f0f7")
	readonly property color buttonHoverColor: theme.token("buttonHoverColor", "#8a6ff0")
	readonly property color buttonFocusColor: theme.token("buttonFocusColor", "#8a6ff0")

	readonly property color viewTextColor: theme.token("viewTextColor", "#24222a")
	readonly property color viewBackgroundColor: theme.token("viewBackgroundColor", "#ffffff")
	readonly property color viewAlternateBackgroundColor: theme.token("viewAlternateBackgroundColor", "#f2f0f7")
	readonly property color viewHoverColor: theme.token("viewHoverColor", "#8a6ff0")
	readonly property color viewFocusColor: theme.token("viewFocusColor", "#8a6ff0")

	readonly property color selectionTextColor: theme.token("selectionTextColor", "#ffffff")
	readonly property color selectionBackgroundColor: theme.token("selectionBackgroundColor", "#8a6ff0")
	readonly property color selectionAlternateBackgroundColor: theme.token("selectionAlternateBackgroundColor", "#8a6ff0")
	readonly property color selectionHoverColor: theme.token("selectionHoverColor", "#8a6ff0")
	readonly property color selectionFocusColor: theme.token("selectionFocusColor", "#8a6ff0")

	readonly property color headerTextColor: theme.token("headerTextColor", "#ffffff")
	readonly property color headerBackgroundColor: theme.token("headerBackgroundColor", "#2b2930")
	readonly property color headerAlternateBackgroundColor: theme.token("headerAlternateBackgroundColor", "#2b2930")
	readonly property color headerHoverColor: theme.token("headerHoverColor", "#8a6ff0")
	readonly property color headerFocusColor: theme.token("headerFocusColor", "#8a6ff0")

	readonly property color tooltipTextColor: theme.token("tooltipTextColor", "#ffffff")
	readonly property color tooltipBackgroundColor: theme.token("tooltipBackgroundColor", "#2b2930")

	// ── Fonts ─────────────────────────────────────────────────────────────
	readonly property font defaultFont: theme.token("defaultFont", Qt.application.font)
	readonly property font smallFont: theme.token("smallFont", Qt.font({
		family: Qt.application.font.family,
		pixelSize: Math.max(10, Math.round(Qt.application.font.pixelSize * 0.8))
	}))

	// ── Metrics (mirrored in Units) ───────────────────────────────────────
	readonly property real gridUnit: theme.token("gridUnit", 18)
	readonly property real smallSpacing: theme.token("smallSpacing", 4)
	readonly property real mediumSpacing: theme.token("mediumSpacing", 6)
	readonly property real largeSpacing: theme.token("largeSpacing", 8)
	readonly property real cornerRadius: theme.token("cornerRadius", 5)
	readonly property real smallRadius: theme.token("smallRadius", 2)
	readonly property int iconSizeSmall: theme.token("iconSizeSmall", 16)
	readonly property int iconSizeSmallMedium: theme.token("iconSizeSmallMedium", 22)
	readonly property int iconSizeMedium: theme.token("iconSizeMedium", 32)
	readonly property int iconSizeLarge: theme.token("iconSizeLarge", 48)
	readonly property int iconSizeHuge: theme.token("iconSizeHuge", 64)

	/// One token, or the fallback when the backend does not provide it. The
	/// backend is a plain QtObject with the same property names.
	function token(name, fallback) {
		const value = theme.backend ? theme.backend[name] : undefined
		return value === undefined || value === null ? fallback : value
	}

	Component.onCompleted: theme.loadBackend()

	/// Load the backend that matches this system. The ClamOS theme file is the
	/// signal: a device that applied a ClamOS theme uses it, anything else (a
	/// plain KDE desktop) keeps the live KDE palette. Both are QML files of
	/// this module, so neither platform's module is required at build time.
	function loadBackend() {
		// The host names its backend ("clamos" on a device, "kde" on a
		// desktop). Without a name, the ClamOS backend is tried first: it only
		// compiles when that theme module is installed, which is exactly the
		// condition for using it. A desktop falls through to the KDE palette.
		const forced = String(ThemeIcons.backend() || "")
		const order = (forced === "clamos" || forced === "kde")
			? [forced] : ["clamos", "kde"]

		for (let i = 0; i < order.length; i++) {
			const name = order[i]
			const source = "qrc:/Hishell/Theme/" + (name === "clamos" ? "Clamos.qml" : "Kde.qml")
			const component = Qt.createComponent(source)
			if (component.status !== Component.Ready) {
				component.destroy()
				continue
			}
			const object = component.createObject(theme)
			if (!object)
				continue
			theme.backend = object
			theme.backendName = name
			console.warn("hishell theme: " + name + " backend")
			return
		}
		console.warn("hishell theme: no backend, using built-in defaults")
	}
}
