import QtQuick
import QtQuick.Layouts

// Mutually exclusive choices: `options` is a list of `{ text, icon, value }`,
// `currentValue` marks the selected one, and a click emits `activated(value)`.
//
// The control itself comes from the platform style when it has one: the ClamOS
// QQC2 style ships a segmented control that matches the rest of the UI, so the
// shell uses that rather than drawing its own. A desktop build without the
// ClamOS modules falls back to Generic, which follows the theme tokens (the KDE
// palette there).

Loader {
	id: segmented

	property var options: []
	property var currentValue: undefined
	signal activated(var value)

	Layout.fillWidth: true

	Component.onCompleted: {
		// The style's control only compiles when its module is installed,
		// which is exactly when it should be used.
		let component = Qt.createComponent("qrc:/Hishell/SegmentedButtonsStyle.qml")
		if (component.status !== Component.Ready)
			component = Qt.createComponent("qrc:/Hishell/SegmentedButtonsGeneric.qml")
		if (component.status === Component.Ready)
			segmented.sourceComponent = component
	}

	onLoaded: {
		item.options = Qt.binding(function() { return segmented.options })
		item.currentValue = Qt.binding(function() { return segmented.currentValue })
		item.activated.connect(function(value) { segmented.activated(value) })
	}
}
