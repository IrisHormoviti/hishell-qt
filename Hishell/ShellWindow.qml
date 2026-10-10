import QtQuick
import QtQuick.Controls
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

	// Selection state lives in the folder views; this points at the manager of
	// the view that last took focus so the window actions operate on it.
	property SelectionManager selectionManager: null
	property alias focusManager: focusManager
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

	FocusManager {
		id: focusManager
		window: root
	}

	Timer {
		interval: 90
		running: true
		repeat: true
		onTriggered: focusManager.poll_gamepad()
	}

	ActionManager {
		id: actionManager
		window: root
		directory: directory
		fileManager: fileManager
	}

	DragTooltip {
		active: dragDropHandler.tooltip_active
		action: dragDropHandler.drag_action
		reposition: dragDropHandler.reposition_active
		cursorX: dragDropHandler.drag_cursor_x
		cursorY: dragDropHandler.drag_cursor_y
	}

	DragPreview {
		previewActive: dragDropHandler.reposition_active && !!dragDropHandler.reposition_preview
		cursorX: dragDropHandler.drag_cursor_x
		cursorY: dragDropHandler.drag_cursor_y
		previewData: dragDropHandler.reposition_preview
		fileManager: root.fileManager
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

			// Folder config load error banner
			Rectangle {
				id: configErrorBanner
				property string dismissedError: ""

				visible: directory.config.error.length > 0 && directory.config.error !== configErrorBanner.dismissedError
				Layout.fillWidth: true
				Layout.preferredHeight: configErrorRow.implicitHeight + Kirigami.Units.largeSpacing * 2
				color: Kirigami.Theme.negativeBackgroundColor

				RowLayout {
					id: configErrorRow
					anchors.horizontalCenter: parent.horizontalCenter
					anchors.verticalCenter: parent.verticalCenter
					width: parent.width - Kirigami.Units.largeSpacing * 2
					spacing: Kirigami.Units.largeSpacing

					Label {
						Layout.fillWidth: true
						text: directory.config.error
						color: Kirigami.Theme.negativeTextColor
						wrapMode: Text.WordWrap
					}

					Button {
						visible: directory.config.error_file.length > 0
						text: "Open Config"
						onClicked: fileManager.open_file(directory.config.error_file)
					}

					ToolButton {
						icon.name: "dialog-close"
						onClicked: configErrorBanner.dismissedError = directory.config.error
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
