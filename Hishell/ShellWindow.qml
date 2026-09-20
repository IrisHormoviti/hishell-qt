import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Hishell
import Hishell.toolkit

Kirigami.ApplicationWindow {
	id: root
	width: 800
	height: 600
	visible: true

	flags: directory.config.native_titlebar ? Qt.Window : Qt.Window | Qt.FramelessWindowHint

	property alias selectionManager: selectionManager
	property alias dragDropHandler: dragDropHandler
	property alias dropValidator: dropValidator
	property alias fileManager: fileManager
	property alias directory: directory
	property alias actionManager: actionManager

	WindowOverlay {}

	Directory {
		id: directory
	}

	FileManager {
		id: fileManager
	}

	DragDropHandler {
		id: dragDropHandler
	}

	DropValidator {
		id: dropValidator
	}

	SelectionManager {
		id: selectionManager
	}

	ActionManager {
		id: actionManager
		window: root
		directory: directory
		selectionManager: selectionManager
		fileManager: fileManager
	}

	DragTooltip {
		active: dragDropHandler.tooltip_active && dragDropHandler.Drag.active
		action: dragDropHandler.drag_action
		cursorX: dragDropHandler.drag_cursor_x + 16
		cursorY: dragDropHandler.drag_cursor_y + 16
	}

	Component.onCompleted: {
		directory.config.load(initialPath);
		directory.path = initialPath;

		// Set layout strings dynamically after config load
		headerLayoutEngine.layoutString = String(directory.config.header_layout);
		topLayoutEngine.layoutString = String(directory.config.top_layout);
		middleLayoutEngine.layoutString = String(directory.config.middle_layout);
		bottomLayoutEngine.layoutString = String(directory.config.bottom_layout);
	}

	menuBar: MenuBar {
		visible: directory.config.native_menubar

		window: root
		directory: root.directory
	}

	pageStack.initialPage: Kirigami.Page {
		padding: 0
		topPadding: 0
		leftPadding: 0
		rightPadding: 0
		bottomPadding: 0

		globalToolBarStyle: Kirigami.ApplicationHeaderStyle.Breadcrumb

		ColumnLayout {
			anchors.fill: parent
			spacing: 0

			// Header bar
			Kirigami.AbstractApplicationHeader {
				Layout.fillWidth: true
				Kirigami.Theme.colorSet: Kirigami.Theme.Header

				z: 1

				Rectangle {
					anchors.fill: parent
					z: -1
					color: Kirigami.Theme.backgroundColor
				}

				RowLayout {
					anchors.fill: parent

					Layout.fillWidth: true
					Layout.preferredHeight: 44
					Layout.margins: 0
					spacing: Kirigami.Units.smallSpacing

					// Make it draggable
					DragHandler {
						target: null
						onActiveChanged: if (active)
							root.startSystemMove()
					}

					LayoutEngine {
						id: headerLayoutEngine
						directory: directory
						window: root
						Layout.fillWidth: true
					}
				}
			}

			// Top Layout area
			LayoutEngine {
				id: topLayoutEngine
				directory: directory
				window: root
				Layout.fillWidth: true
			}

			// Main content area
			RowLayout {
				Layout.fillWidth: true
				Layout.fillHeight: true
				spacing: 0

				LayoutEngine {
					id: middleLayoutEngine
					directory: directory
					window: root
					Layout.fillHeight: true
					Layout.fillWidth: true
				}
			}

			// Bottom Layout area
			LayoutEngine {
				id: bottomLayoutEngine
				directory: directory
				window: root
				Layout.fillWidth: true
			}
		}
	}
}
