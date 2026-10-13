pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Hishell

ToolButton {
	id: viewButton
	property var window
	property Directory directory

	readonly property ViewActions viewActions: viewActionsObject

	ViewActions {
		id: viewActionsObject
		directory: viewButton.directory
		window: viewButton.window
	}

	// The dialog is not a child of the button: it is an overlay that sizes
	// itself to the window, so creating it under the 40px button would clamp
	// its height. It is created on first use, like the folder menus.
	property var viewDialog: null

	function openViewDialog() {
		if (!viewButton.viewDialog) {
			const overlay = viewButton.window && viewButton.window.contentItem ? viewButton.window.contentItem : viewButton;
			viewButton.viewDialog = viewDialogComponent.createObject(overlay, {
				viewActions: viewButton.viewActions
			});
		}
		if (viewButton.viewDialog)
			viewButton.viewDialog.open();
	}

	Component {
		id: viewDialogComponent
		ViewDialog {}
	}

	Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
	Layout.preferredWidth: Kirigami.Units.gridUnit * 2
	Layout.preferredHeight: Kirigami.Units.gridUnit * 2
	Layout.leftMargin: Kirigami.Units.smallSpacing
	Layout.rightMargin: Kirigami.Units.smallSpacing

	display: AbstractButton.IconOnly
	icon.name: viewButton.viewActions.viewModeIcon
	icon.width: Kirigami.Units.iconSizes.medium
	icon.height: Kirigami.Units.iconSizes.medium

	ToolTip.text: viewButton.viewActions.isListView ? qsTr("View options (list)") : qsTr("View options (grid)")
	ToolTip.visible: hovered

	onPressed: viewButton.viewActions.playSound("button-pressed")
	onReleased: viewButton.viewActions.playSound("button-released")
	onClicked: {
		viewButton.viewActions.playSound("dialog-open");
		viewButton.openViewDialog();
	}
}
