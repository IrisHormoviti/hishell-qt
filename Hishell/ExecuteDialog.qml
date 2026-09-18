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

	popupType: Popup.Window

	title: qsTr("Run Executable?")
	modal: true
	anchors.centerIn: parent

	width: 400

	Connections {
		target: execDialog.directory
		function onRequestExecutePrompt(path: string) {
			execDialog.filePath = path;
			execDialog.open();
		}
	}

	ColumnLayout {
		spacing: Kirigami.Units.largeSpacing

		Kirigami.Icon {
			source: execDialog.fileManager.get_icon(execDialog.filePath)
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
		}
		Button {
			text: qsTr("Cancel")
			DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
		}
	}

	onAccepted: {
		if (execDialog.directory && execDialog.filePath !== "") {
			execDialog.directory.execute_file(execDialog.filePath);
		}
	}
}
