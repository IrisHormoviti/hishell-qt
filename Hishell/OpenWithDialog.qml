pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Hishell.Theme
import Hishell

// Touch-friendly application picker for "Open With", presented as a bottom
// sheet: it slides up over the window, stays a comfortable column, scrolls as
// one surface and dismisses with a swipe or a tap on the dimmed area. Rows are
// finger-sized tap targets and a single tap opens, while a "Set as default"
// box applies the same choice as the handler for the file's type going forward.
Sheet {
	id: openWithDialog
	property string filePath: ""
	property string mime: ""
	property string mimeDescription: ""
	property var apps: []
	required property FileManager fileManager
	property var window

	title: qsTr("Open With")
	implicitWidth: Units.gridUnit * 20

	// Escape (the controller's cancel button maps to it) and a tap outside both
	// dismiss the sheet.
	closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

	// Event sounds (ClamOS XDG sound theme).
	function playSound(name) {
		if (openWithDialog.window && openWithDialog.window.sound)
			openWithDialog.window.sound.play(name);
	}

	function refresh() {
		const payload = JSON.parse(openWithDialog.fileManager.get_open_with_apps(openWithDialog.filePath));
		openWithDialog.mime = payload.mime || "";
		openWithDialog.mimeDescription = payload.mimeDescription || "";
		openWithDialog.apps = payload.apps || [];
		appList.currentIndex = openWithDialog.apps.length > 0 ? 0 : -1;
	}

	// Launch the app at `index` (the list cursor when omitted), first recording
	// it as the default handler when the box is ticked.
	function openSelected(index) {
		const i = index === undefined ? appList.currentIndex : index;
		if (i < 0 || i >= openWithDialog.apps.length)
			return;
		const app = openWithDialog.apps[i];
		if (openWithDialog.window && typeof openWithDialog.window.clearReturnFrame === 'function')
			openWithDialog.window.clearReturnFrame();
		if (rememberCheck.checked && openWithDialog.mime !== "")
			openWithDialog.fileManager.set_default_app(openWithDialog.mime, app.id);
		const warning = String(openWithDialog.fileManager.open_with_app(openWithDialog.filePath, app.id));
		openWithDialog.close();
		if (warning !== "" && openWithDialog.window
			&& typeof openWithDialog.window.requestLaunchConfirm === 'function')
			openWithDialog.window.requestLaunchConfirm(warning, openWithDialog.filePath);
	}

	onOpened: {
		openWithDialog.playSound("dialog-open");
		rememberCheck.checked = false;
		refresh();
		appList.forceActiveFocus();
	}
	onClosed: openWithDialog.playSound("dialog-cancel")

	// Pinned header: what is being opened, and the association choice. It sits
	// outside the scrolling list, so the box is always reachable.
	header: ColumnLayout {
		spacing: Units.smallSpacing

		Label {
			Layout.fillWidth: true
			text: openWithDialog.title
			font.bold: true
			font.pixelSize: Math.round(Units.gridUnit * 0.9)
			elide: Text.ElideRight
		}

		RowLayout {
			Layout.fillWidth: true
			spacing: Units.largeSpacing

			Icon {
				source: openWithDialog.fileManager.get_icon(openWithDialog.filePath)
				implicitWidth: Units.iconSizes.medium
				implicitHeight: Units.iconSizes.medium
			}

			ColumnLayout {
				Layout.fillWidth: true
				spacing: 0

				Label {
					Layout.fillWidth: true
					text: openWithDialog.filePath.substring(openWithDialog.filePath.lastIndexOf("/") + 1)
					elide: Text.ElideMiddle
					font.bold: true
				}

				Label {
					Layout.fillWidth: true
					visible: text.length > 0
					text: openWithDialog.mimeDescription
					elide: Text.ElideRight
					opacity: 0.7
					font: Theme.smallFont
				}
			}
		}

		CheckBox {
			id: rememberCheck
			Layout.fillWidth: true
			visible: openWithDialog.apps.length > 0 && openWithDialog.mime !== ""
			// The list owns the keyboard so the controller cursor stays in one
			// place; the row is still a full-width tap target for touch and the
			// box state is what the launch reads.
			focusPolicy: Qt.NoFocus
			text: openWithDialog.mimeDescription.length > 0
				? qsTr("Set as default for %1").arg(openWithDialog.mimeDescription)
				: qsTr("Set as default")
			onToggled: openWithDialog.playSound(checked ? "button-toggle-on" : "button-toggle-off")
		}
	}

	// The list is the sheet's own scroll surface, so it flickers, scrolls to the
	// cursor and takes the arrow keys instead of nesting a second flickable.
	ListView {
		id: appList
		clip: true
		Layout.fillWidth: true
		Layout.fillHeight: true
		Layout.preferredHeight: Units.gridUnit * 12
		model: openWithDialog.apps
		Keys.onReturnPressed: openWithDialog.openSelected()
		Keys.onEnterPressed: openWithDialog.openSelected()

		header: Label {
			width: appList.width
			visible: openWithDialog.apps.length === 0
			height: visible ? implicitHeight : 0
			leftPadding: Units.largeSpacing
			text: qsTr("No applications found for this file")
			opacity: 0.7
		}

		delegate: ItemDelegate {
			id: appDelegate
			required property var modelData
			required property int index

			width: appList.width
			highlighted: ListView.isCurrentItem
			// A single tap opens, so the whole row is the target. The list still
			// tracks currentIndex for the controller and the arrow keys.
			focusPolicy: Qt.NoFocus
			onClicked: {
				appList.currentIndex = appDelegate.index;
				openWithDialog.openSelected();
			}

			background: Rectangle {
				radius: Units.smallRadius
				color: appDelegate.highlighted ? Theme.highlightColor
					: appDelegate.hovered ? Theme.hoverColor : "transparent"
			}

			contentItem: RowLayout {
				spacing: Units.largeSpacing

				Icon {
					source: appDelegate.modelData.icon || "application-x-executable"
					implicitWidth: Units.iconSizes.medium
					implicitHeight: Units.iconSizes.medium
				}

				ColumnLayout {
					Layout.fillWidth: true
					spacing: 0

					Label {
						Layout.fillWidth: true
						text: appDelegate.modelData.name
						color: appDelegate.highlighted ? Theme.highlightedTextColor : Theme.textColor
						elide: Text.ElideRight
					}

					Label {
						Layout.fillWidth: true
						visible: text.length > 0
						text: appDelegate.modelData.comment || ""
						color: appDelegate.highlighted ? Theme.highlightedTextColor : Theme.textColor
						opacity: 0.7
						font: Theme.smallFont
						elide: Text.ElideRight
					}
				}

				Label {
					visible: appDelegate.modelData.isDefault
					text: qsTr("default")
					color: appDelegate.highlighted ? Theme.highlightedTextColor : Theme.textColor
					opacity: 0.7
					font: Theme.smallFont
				}
			}
		}
	}
}
