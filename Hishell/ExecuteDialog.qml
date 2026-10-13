import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Hishell

Dialog {
	id: execDialog
	property string filePath: ""
	required property Directory directory
	required property FileManager fileManager
	property var window

	// Event sounds (ClamOS XDG sound theme).
	function playSound(name) {
		if (execDialog.window && execDialog.window.sound)
			execDialog.window.sound.play(name);
	}

	// In-window popup: native (separate compositor) popups land on the wrong
	// output on this two-panel device and have been seen to close the wrong
	// window. See NativeMenus in the config for the same reasoning.
	popupType: Popup.Item

	title: qsTr("Run Executable?")
	modal: true
	anchors.centerIn: parent

	width: 400

	Connections {
		target: execDialog.directory
		function onRequestExecutePrompt(path: string) {
			execDialog.filePath = path;
			execDialog.playSound("dialog-information");
			execDialog.open();
		}
	}

	ColumnLayout {
		spacing: Kirigami.Units.largeSpacing

		Kirigami.Icon {
			source: execDialog.fileManager ? execDialog.fileManager.get_icon(execDialog.filePath) : ""
			Layout.alignment: Qt.AlignHCenter
		}

		Label {
			text: qsTr("'%1' contains an executable program.").arg(execDialog.filePath.substring(execDialog.filePath.lastIndexOf("/") + 1))
			horizontalAlignment: Text.AlignHCenter
			Layout.alignment: Qt.AlignHCenter
		}
	}

	footer: DialogButtonBox {
		Button {
			text: qsTr("Run")
			DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
			onPressed: execDialog.playSound("button-pressed")
			onReleased: execDialog.playSound("button-released")
		}
		Button {
			text: qsTr("Cancel")
			DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
			onPressed: execDialog.playSound("button-pressed")
			onReleased: execDialog.playSound("button-released")
		}
	}

	onAccepted: {
		if (execDialog.directory && execDialog.filePath !== "") {
			execDialog.directory.execute_file(execDialog.filePath);
		}
	}
}
