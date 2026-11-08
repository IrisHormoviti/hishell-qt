import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

RowLayout {
	property var window: null
	visible: window && window.currentDirectory
		? !window.currentDirectory.config.native_titlebar : true
	spacing: Kirigami.Units.smallSpacing
	Layout.preferredWidth: implicitWidth

	ToolButton {
		icon.name: "window-minimize"
		onClicked: if (window) window.showMinimized()
	}

	ToolButton {
		icon.name: window && window.visibility === Window.Maximized
			? "window-restore" : "window-maximize"
		onClicked: {
			if (!window)
				return
			if (window.visibility === Window.Maximized)
				window.showNormal()
			else
				window.showMaximized()
		}
	}

	ToolButton {
		icon.name: "window-close"
		onClicked: if (window) window.close()
	}
}
