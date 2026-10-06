pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Hishell

Dialog {
	id: openWithDialog
	property string filePath: ""
	property string mime: ""
	property string mimeDescription: ""
	property var apps: []
	required property FileManager fileManager

	popupType: Popup.Window
	title: qsTr("Open With")
	modal: true
	anchors.centerIn: parent
	width: 460

	function refresh() {
		const payload = JSON.parse(openWithDialog.fileManager.get_open_with_apps(openWithDialog.filePath));
		openWithDialog.mime = payload.mime || "";
		openWithDialog.mimeDescription = payload.mimeDescription || "";
		openWithDialog.apps = payload.apps || [];
		appList.currentIndex = openWithDialog.apps.length > 0 ? 0 : -1;
	}

	function openSelected() {
		const index = appList.currentIndex;
		if (index < 0 || index >= openWithDialog.apps.length)
			return;
		const app = openWithDialog.apps[index];
		if (rememberCheck.checked && openWithDialog.mime !== "")
			openWithDialog.fileManager.set_default_app(openWithDialog.mime, app.id);
		openWithDialog.fileManager.open_with_app(openWithDialog.filePath, app.id);
		openWithDialog.close();
	}

	onOpened: {
		rememberCheck.checked = false;
		refresh();
		appList.forceActiveFocus();
	}
	onAccepted: openSelected()

	ColumnLayout {
		spacing: Kirigami.Units.smallSpacing

		RowLayout {
			Layout.fillWidth: true
			spacing: Kirigami.Units.largeSpacing

			Kirigami.Icon {
				source: openWithDialog.fileManager.get_icon(openWithDialog.filePath)
				implicitWidth: Kirigami.Units.iconSizes.medium
				implicitHeight: Kirigami.Units.iconSizes.medium
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
					font: Kirigami.Theme.smallFont
				}
			}
		}

		Item {
			Layout.fillWidth: true
			Layout.preferredHeight: 280

			ListView {
				id: appList
				anchors.fill: parent
				visible: openWithDialog.apps.length > 0
				clip: true
				model: openWithDialog.apps
				Keys.onUpPressed: decrementCurrentIndex()
				Keys.onDownPressed: incrementCurrentIndex()
				Keys.onReturnPressed: openWithDialog.openSelected()
				Keys.onEnterPressed: openWithDialog.openSelected()

				delegate: ItemDelegate {
					id: appDelegate
					required property var modelData
					required property int index

					width: ListView.view.width
					highlighted: ListView.isCurrentItem
					onClicked: appList.currentIndex = appDelegate.index
					onDoubleClicked: openWithDialog.openSelected()

					background: Rectangle {
						radius: Kirigami.Units.smallRadius
						color: appDelegate.highlighted ? Kirigami.Theme.highlightColor : appDelegate.hovered ? Kirigami.Theme.hoverColor : "transparent"
					}

					contentItem: RowLayout {
						spacing: Kirigami.Units.smallSpacing

						Kirigami.Icon {
							source: appDelegate.modelData.icon || "application-x-executable"
							implicitWidth: Kirigami.Units.iconSizes.smallMedium
							implicitHeight: Kirigami.Units.iconSizes.smallMedium
						}

						ColumnLayout {
							Layout.fillWidth: true
							spacing: 0

							Label {
								Layout.fillWidth: true
								text: appDelegate.modelData.name
								color: appDelegate.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
								elide: Text.ElideRight
							}

							Label {
								Layout.fillWidth: true
								visible: text.length > 0
								text: appDelegate.modelData.comment || ""
								color: appDelegate.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
								opacity: 0.7
								font: Kirigami.Theme.smallFont
								elide: Text.ElideRight
							}
						}

						Label {
							visible: appDelegate.modelData.isDefault
							text: qsTr("default")
							color: appDelegate.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
							opacity: 0.7
							font: Kirigami.Theme.smallFont
						}
					}
				}
			}

			Label {
				anchors.centerIn: parent
				visible: openWithDialog.apps.length === 0
				text: qsTr("No applications found for this file")
				opacity: 0.7
			}
		}

		CheckBox {
			id: rememberCheck
			visible: openWithDialog.apps.length > 0 && openWithDialog.mime !== ""
			text: openWithDialog.mimeDescription.length > 0 ? qsTr("Remember application association for '%1' files").arg(openWithDialog.mimeDescription) : qsTr("Remember application association for this file type")
			checked: false
		}
	}

	footer: DialogButtonBox {
		Button {
			text: qsTr("Open")
			enabled: appList.currentIndex >= 0
			DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
		}
		Button {
			text: qsTr("Cancel")
			DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
		}
	}
}
