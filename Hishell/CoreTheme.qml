pragma Singleton

// Theme values the shell needs that are not part of Kirigami's own theme.
//
// Hishell must start on a plain KDE desktop where ClamOS's `ClamOS.Theme` QML
// module is not installed. Importing that module statically made the whole
// window fail to load, so this singleton owns the few Clam-specific values
// instead:
//
//   * when a ClamOS theme is installed, its header height, icon theme and
//     shadow colour are used, exactly like the system ClamTheme singleton;
//   * otherwise Kirigami's live KDE palette supplies the accent and the
//     fallbacks are sane desktop values.
//
// Everything here is optional and re-read at runtime, so a theme applied on a
// ClamOS device still reaches the running shell.

import QtQuick
import QtCore
import org.kde.kirigami as Kirigami

QtObject {
	id: coreTheme

	// The icon theme declared by the active ClamOS theme, or "" on a desktop
	// without one (leave the system icon theme alone then).
	property string iconTheme: ""

	// Header bar height for the shell's own in-window header. On a plain KDE
	// desktop this tracks Kirigami's metrics; a ClamOS theme may override it.
	property real headerHeight: coreTheme.desktopHeaderHeight

	// Shadow used by the themed button plates.
	property color shadowColor: Qt.rgba(0, 0, 0, 0.35)

	// Accent colours for recolouring folder icons, matching what KDE apps get
	// from the same colour scheme.
	readonly property color accentColor: Kirigami.Theme.highlightColor
	readonly property color accentTextColor: Kirigami.Theme.textColor

	readonly property real desktopHeaderHeight: Math.max(48, Kirigami.Units.gridUnit * 3)

	// The four faces a file label can use. A folder's delegates all share the
	// same font; measuring the italic face once here (Qt resolves it at a
	// slightly smaller metric on this device, so the symlink label needs
	// scaling) keeps two FontMetrics and a QFont construction out of every
	// slot.
	readonly property real labelBasePixelSize: Qt.application.font.pixelSize
	property FontMetrics labelRegularMetrics: FontMetrics {
		font: Qt.font({
			family: Qt.application.font.family,
			pixelSize: coreTheme.labelBasePixelSize,
			italic: false
		})
	}
	property FontMetrics labelItalicMetrics: FontMetrics {
		font: Qt.font({
			family: Qt.application.font.family,
			pixelSize: coreTheme.labelBasePixelSize,
			italic: true
		})
	}
	readonly property real labelItalicScale: coreTheme.labelItalicMetrics.height > 0
		? coreTheme.labelRegularMetrics.height / coreTheme.labelItalicMetrics.height
		: 1.0
	readonly property int labelItalicPixelSize: Math.round(coreTheme.labelBasePixelSize * coreTheme.labelItalicScale)
	readonly property font labelFont: Qt.font({
		family: Qt.application.font.family,
		pixelSize: coreTheme.labelBasePixelSize,
		weight: Qt.application.font.weight,
		italic: false,
		bold: false
	})
	readonly property font labelFontBold: Qt.font({
		family: Qt.application.font.family,
		pixelSize: coreTheme.labelBasePixelSize,
		weight: Qt.application.font.weight,
		italic: false,
		bold: true
	})
	readonly property font labelFontItalic: Qt.font({
		family: Qt.application.font.family,
		pixelSize: coreTheme.labelItalicPixelSize,
		weight: Qt.application.font.weight,
		italic: true,
		bold: false
	})
	readonly property font labelFontItalicBold: Qt.font({
		family: Qt.application.font.family,
		pixelSize: coreTheme.labelItalicPixelSize,
		weight: Qt.application.font.weight,
		italic: true,
		bold: true
	})

	readonly property string configDir: coreTheme.localPath(StandardPaths.writableLocation(StandardPaths.GenericConfigLocation))
	readonly property string dataDir: coreTheme.localPath(StandardPaths.writableLocation(StandardPaths.GenericDataLocation))
	readonly property string themeIniPath: coreTheme.configDir + "/clam/theme.ini"
	readonly property string themePath: coreTheme.themeId ? coreTheme.dataDir + "/themes/" + coreTheme.themeId : ""
	readonly property string manifestPath: coreTheme.themePath ? coreTheme.themePath + "/.directory" : coreTheme.themeIniPath
	// QtCore's Settings takes a URL (`location`), while Qt.labs.settings used a
	// path. Encode it so paths with spaces still resolve.
	readonly property url themeIniLocation: coreTheme.fileUrl(coreTheme.themeIniPath)
	readonly property url manifestLocation: coreTheme.fileUrl(coreTheme.manifestPath)

	property string themeId: ""

	// Qt 6's StandardPaths returns a `file://` URL; QSettings wants a path.
	function localPath(value) {
		const text = String(value || "");
		return text.indexOf("file://") === 0 ? text.substring(7) : text;
	}

	function fileUrl(path) {
		return "file://" + encodeURI(String(path || ""));
	}

	property Settings themeIniSettings: Settings {
		location: coreTheme.themeIniLocation
	}
	property Settings manifestSettings: Settings {
		location: coreTheme.manifestLocation
	}

	property Timer poll: Timer {
		interval: 1500
		running: true
		repeat: true
		onTriggered: coreTheme.reload()
	}

	Component.onCompleted: coreTheme.reload()

	function reload() {
		coreTheme.themeIniSettings.sync();
		coreTheme.themeId = String(coreTheme.themeIniSettings.value("Theme/Id", "") || "");

		// The manifestSettings fileName binding follows themePath; sync after
		// setting the theme id so the read below sees the active theme.
		coreTheme.manifestSettings.sync();

		const icon = String(coreTheme.manifestSettings.value("Icons/Theme", "") || "");
		if (icon !== coreTheme.iconTheme)
			coreTheme.iconTheme = icon;

		const height = parseFloat(String(coreTheme.manifestSettings.value("Metrics/HeaderHeight", "") || ""));
		coreTheme.headerHeight = isNaN(height) || height <= 0 ? coreTheme.desktopHeaderHeight : height;

		const shadow = String(coreTheme.manifestSettings.value("Colors/Shadow", "") || "");
		coreTheme.shadowColor = shadow.startsWith("#") ? shadow : Qt.rgba(0, 0, 0, 0.35);
	}

	// The `file://` source of a themed place icon (folder, home, ...)
	// recoloured to the accent, or "" when it cannot be rendered.
	function accentFolderIcon(fileManager, name, size) {
		if (!fileManager || !name)
			return "";
		if (name.indexOf("file:") === 0 || name.indexOf("/") === 0)
			return "";
		const accent = coreTheme.accentColor;
		const text = coreTheme.accentTextColor;
		const component = Math.round(Math.max(16, size));
		return String(fileManager.accent_icon(
			name, component,
			Math.round(accent.r * 255), Math.round(accent.g * 255), Math.round(accent.b * 255),
			Math.round(text.r * 255), Math.round(text.g * 255), Math.round(text.b * 255)));
	}
}
