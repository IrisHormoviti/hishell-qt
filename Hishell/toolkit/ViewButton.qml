pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Hishell.Theme
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

	// The dialog is not a child of the button: it sizes itself to the window,
	// so creating it under the 40px button would clamp its height. It is
	// created on first use, like the folder menus.
	//
	// It hangs off the window's *overlay*, not its contentItem. Both are
	// children of the window, but the overlay layer is drawn above all content
	// no matter what z the content uses; a sheet under contentItem is merely a
	// sibling of the panes, so a focused FileSlot (whose focus indicator is
	// z: 3) would otherwise sort against it. Dialogs should not depend on
	// that comparison.
	property var viewDialog: null

	function openViewDialog() {
		if (!viewButton.viewDialog) {
			const w = viewButton.window;
			const overlay = (w && w.overlay) ? w.overlay : ((w && w.contentItem) ? w.contentItem : viewButton);
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
	Layout.preferredWidth: Units.gridUnit * 2
	Layout.preferredHeight: Units.gridUnit * 2
	Layout.leftMargin: Units.smallSpacing
	Layout.rightMargin: Units.smallSpacing

	display: AbstractButton.IconOnly
	icon.name: viewButton.viewActions.viewModeIcon
	icon.width: Units.iconSizes.medium
	icon.height: Units.iconSizes.medium

	ToolTip.text: viewButton.viewActions.isListView ? qsTr("View options (list)") : qsTr("View options (grid)")
	ToolTip.visible: hovered

	onPressed: viewButton.viewActions.playSound("button-pressed")
	onReleased: viewButton.viewActions.playSound("button-released")
	onClicked: {
		viewButton.viewActions.playSound("dialog-open");
		viewButton.openViewDialog();
	}
}
