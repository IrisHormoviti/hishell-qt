import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// The editor for a `Type=Number` settings control.
//
// The provider supplies the labels, values and ranges; this dialog only lays
// them out and collects the integers.  Each field is a vertical column: up
// arrow, value box, down arrow.  The arrows are touch targets, and Return /
// Escape accept or cancel so the controller can drive the dialog too.
Dialog {
	id: numberDialog
	property var window
	property var fileManager
	property string filePath: ""
	property var spec: ({ ok: false, fields: [] })

	// Working copy; `values` is only written back when the user accepts.
	property var values: []
	property bool accepted: false

	popupType: Popup.Item
	modal: true
	anchors.centerIn: parent
	width: Math.min(720, parent ? parent.width - 48 : 720)

	title: qsTr("Set values")

	function playSound(name) {
		if (numberDialog.window && numberDialog.window.sound)
			numberDialog.window.sound.play(name);
	}

	function openFor(path: string) {
		numberDialog.filePath = path;
		let parsed = { ok: false, fields: [] };
		try {
			parsed = JSON.parse(String(numberDialog.fileManager.number_spec(path)));
		} catch (error) {
			parsed = { ok: false, fields: [] };
		}
		numberDialog.spec = parsed;
		numberDialog.values = (parsed.fields || []).map(field => Number(field.value));
		if (parsed.ok) {
			numberDialog.accepted = false;
			numberDialog.playSound("dialog-open");
			numberDialog.open();
		}
	}

	function bump(index, delta) {
		const field = numberDialog.spec.fields[index];
		if (!field)
			return;
		const current = Number(numberDialog.values[index]);
		numberDialog.values[index] = Math.max(Number(field.min), Math.min(Number(field.max), current + delta));
		numberDialog.values = numberDialog.values.slice();
	}

	function apply() {
		const fm = numberDialog.fileManager;
		if (!fm || numberDialog.filePath === "")
			return;
		numberDialog.accepted = true;
		const ok = fm.run_number(numberDialog.filePath, numberDialog.values.join(","));
		if (ok) {
			numberDialog.playSound("button-released");
			// The provider writes the file when the command returns; give it
			// a moment, then refresh the open folder so the row's value is
			// current.
			reloadTimer.restart();
		}
		numberDialog.accept();
	}

	Timer {
		id: reloadTimer
		interval: 350
		repeat: false
		onTriggered: {
			const view = numberDialog.window ? numberDialog.window.focusedFolderView : null;
			if (view && view.directory)
				view.directory.reload();
			else if (numberDialog.window && numberDialog.window.directory)
				numberDialog.window.directory.reload();
		}
	}

	onOpened: Qt.callLater(() => content.forceActiveFocus())
	onClosed: {
		if (!numberDialog.accepted)
			numberDialog.playSound("dialog-cancel");
	}

	contentItem: ColumnLayout {
		id: content
		focus: true
		spacing: Kirigami.Units.largeSpacing

		Keys.onReturnPressed: numberDialog.apply()
		Keys.onEnterPressed: numberDialog.apply()
		Keys.onEscapePressed: numberDialog.reject()

		RowLayout {
			Layout.fillWidth: true
			Layout.alignment: Qt.AlignHCenter
			spacing: Kirigami.Units.largeSpacing

			Repeater {
				model: numberDialog.spec.fields || []

				delegate: ColumnLayout {
					required property var modelData
					required property int index
					Layout.alignment: Qt.AlignVCenter
					spacing: Kirigami.Units.smallSpacing

					Button {
						Layout.alignment: Qt.AlignHCenter
						Layout.preferredWidth: Kirigami.Units.gridUnit * 3
						Layout.preferredHeight: Kirigami.Units.gridUnit * 2
						text: "▲"
						font.pixelSize: Kirigami.Units.gridUnit
						onPressed: numberDialog.playSound("button-pressed")
						onClicked: numberDialog.bump(index, 1)
					}

					Rectangle {
						Layout.alignment: Qt.AlignHCenter
						Layout.preferredWidth: Math.max(Kirigami.Units.gridUnit * 4,
							Kirigami.Units.gridUnit * (String(modelData.max).length + 1))
						Layout.preferredHeight: Kirigami.Units.gridUnit * 2.4
						radius: Kirigami.Units.cornerRadius
						color: Kirigami.Theme.backgroundColor
						border.width: 1
						border.color: Kirigami.Theme.disabledTextColor

						Label {
							anchors.centerIn: parent
							text: String(numberDialog.values[index])
							font.pixelSize: Kirigami.Units.gridUnit * 1.4
							font.bold: true
							horizontalAlignment: Text.AlignHCenter
						}
					}

					Button {
						Layout.alignment: Qt.AlignHCenter
						Layout.preferredWidth: Kirigami.Units.gridUnit * 3
						Layout.preferredHeight: Kirigami.Units.gridUnit * 2
						text: "▼"
						font.pixelSize: Kirigami.Units.gridUnit
						onPressed: numberDialog.playSound("button-pressed")
						onClicked: numberDialog.bump(index, -1)
					}

					Label {
						Layout.alignment: Qt.AlignHCenter
						text: modelData.label
						font.bold: true
						opacity: 0.85
					}
				}
			}
		}

		DialogButtonBox {
			Layout.alignment: Qt.AlignHCenter
			Button {
				text: qsTr("Set")
				DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
				onPressed: numberDialog.playSound("button-pressed")
				onClicked: numberDialog.apply()
			}
			Button {
				text: qsTr("Cancel")
				DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
				onPressed: numberDialog.playSound("button-pressed")
				onClicked: numberDialog.reject()
			}
		}
	}
}
