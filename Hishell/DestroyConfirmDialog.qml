import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Hishell.Theme

// The delete warning for a thing the provider marked as not the user's to
// remove. It is not a confirmation: resetting the settings and unmounting a
// device are different wants, so the sheet asks which one the user means (docs
// `clam-configd.md` §5.2). Touch- and controller-friendly, like
// LaunchConfirmDialog: full-width rows and a sheet that owns focus while it is
// up.
Sheet {
	id: destroyConfirm
	property var window
	property var fileManager
	property string path: ""
	property var info: ({})
	property bool answered: false
	property string pendingAction: ""

	signal decided(string action)

	title: qsTr("Delete")
	implicitWidth: Units.gridUnit * 22
	closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

	readonly property string itemTitle: info.title ? String(info.title) : path
	readonly property bool canDestroy: info.destroy === true
	readonly property bool canReset: info.reset === true
	readonly property bool canUnmount: info.unmount === true

	readonly property string message: {
		if (canUnmount)
			return qsTr("“%1” is a mounted device. Unmount it to make it go away.").arg(itemTitle);
		if (canDestroy && canReset)
			return qsTr("“%1” is a settings section. Remove this link, or reset its settings?").arg(itemTitle);
		if (canDestroy)
			return qsTr("Remove the link “%1”? Its settings stay where they are.").arg(itemTitle);
		if (canReset)
			return qsTr("“%1” cannot be deleted. Reset its settings instead?").arg(itemTitle);
		return qsTr("“%1” belongs to the system and cannot be deleted.").arg(itemTitle);
	}

	function playSound(name) {
		if (destroyConfirm.window && destroyConfirm.window.sound)
			destroyConfirm.window.sound.play(name);
	}

	function ask(itemPath, choices) {
		destroyConfirm.path = itemPath;
		destroyConfirm.info = choices || ({});
		destroyConfirm.answered = false;
		destroyConfirm.pendingAction = "";
		destroyConfirm.open();
	}

	function choose(action) {
		destroyConfirm.answered = true;
		destroyConfirm.pendingAction = action;
		destroyConfirm.close();
	}

	onOpened: {
		destroyConfirm.playSound("dialog-open");
		Qt.callLater(function() {
			if (resetButton.visible)
				resetButton.forceActiveFocus();
			else if (removeButton.visible)
				removeButton.forceActiveFocus();
			else if (unmountButton.visible)
				unmountButton.forceActiveFocus();
			else
				closeButton.forceActiveFocus();
		});
	}
	onClosed: {
		const action = destroyConfirm.answered ? destroyConfirm.pendingAction : "cancel";
		destroyConfirm.pendingAction = "";
		if (action === "cancel")
			destroyConfirm.playSound("dialog-cancel");
		destroyConfirm.decided(action);
	}

	ColumnLayout {
		id: warningContent
		focus: true
		Layout.fillWidth: true
		// A fixed content width keeps the wrapped label's height independent of
		// the sheet's width, which would otherwise be a binding loop.
		Layout.preferredWidth: Units.gridUnit * 22
		spacing: Units.largeSpacing

		Keys.onEscapePressed: destroyConfirm.choose("cancel")

		Label {
			Layout.fillWidth: true
			text: destroyConfirm.message
			wrapMode: Text.WordWrap
			horizontalAlignment: Text.AlignHCenter
		}

		Button {
			id: removeButton
			Layout.fillWidth: true
			visible: destroyConfirm.canDestroy
			text: qsTr("Remove link")
			icon.name: "edit-delete"
			onClicked: destroyConfirm.choose("destroy")
		}

		Button {
			id: resetButton
			Layout.fillWidth: true
			visible: destroyConfirm.canReset
			text: qsTr("Reset settings")
			icon.name: "edit-reset"
			onClicked: destroyConfirm.choose("reset")
		}

		Button {
			id: unmountButton
			Layout.fillWidth: true
			visible: destroyConfirm.canUnmount
			text: qsTr("Unmount")
			icon.name: "media-eject"
			onClicked: destroyConfirm.choose("unmount")
		}

		Button {
			id: closeButton
			Layout.fillWidth: true
			text: qsTr("Cancel")
			icon.name: "dialog-cancel"
			onClicked: destroyConfirm.choose("cancel")
		}
	}
}
