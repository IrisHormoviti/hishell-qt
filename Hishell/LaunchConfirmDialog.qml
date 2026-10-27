import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Hishell

// Touch- and controller-friendly confirmation for a launch the host's execution
// wrapper held back because it would close a suspended app. Kirigami's
// OverlaySheet gives finger-sized rows; the sheet grabs focus while it is up so
// the controller drives it (A accepts, B/Back cancels) and the two items'
// keyboard focus is routed here.
Kirigami.OverlaySheet {
	id: launchConfirm
	property var window
	property var fileManager
	property string blockedItem: ""
	property string launchItem: ""

	// Set when the user accepted, so the sheet's close does not also cancel the
	// held-back launch.
	property bool accepted: false

	title: qsTr("Launch")
	implicitWidth: Kirigami.Units.gridUnit * 20
	closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

	readonly property var info: {
		if (!launchConfirm.fileManager || launchConfirm.blockedItem === "")
			return {};
		const raw = String(launchConfirm.fileManager.launch_warning(launchConfirm.blockedItem, launchConfirm.launchItem));
		return raw === "" ? {} : JSON.parse(raw);
	}

	function playSound(name) {
		if (launchConfirm.window && launchConfirm.window.sound)
			launchConfirm.window.sound.play(name);
	}

	function ask(blockedItem: string, launchItem: string) {
		launchConfirm.accepted = false;
		launchConfirm.blockedItem = blockedItem;
		launchConfirm.launchItem = launchItem;
		launchConfirm.open();
	}

	// Thumbnails and custom art come as a file URL or an absolute path; themed
	// icons are a name. Render them the way the file view does.
	Component {
		id: itemArtComponent
		Item {
			property string artSource: ""
			property bool isThumbnail: artSource.startsWith("file://") || artSource.startsWith("/")

			Image {
				anchors.fill: parent
				visible: parent.isThumbnail
				fillMode: Image.PreserveAspectFit
				asynchronous: true
				smooth: parent.artSource.indexOf("/hishell/descriptors/") === -1
				source: parent.isThumbnail ? parent.artSource : ""
			}

			Kirigami.Icon {
				anchors.fill: parent
				visible: !parent.isThumbnail
				source: parent.artSource !== "" ? parent.artSource : "application-x-executable"
			}
		}
	}

	function accept() {
		const fm = launchConfirm.fileManager;
		launchConfirm.accepted = true;
		// The compositor plays app-launch when the confirmed launch spawns.
		launchConfirm.close();
		if (fm)
			fm.confirm_launch();
	}

	onOpened: {
		launchConfirm.playSound("dialog-open");
		// Take the keyboard so the controller drives this sheet (A accepts,
		// B/Back cancels) instead of the file view underneath.
		Qt.callLater(() => confirmContent.forceActiveFocus());
	}
	onClosed: {
		// Dismissing without accepting (swipe, tap outside, Escape, Back) drops
		// the held-back launch.
		if (!launchConfirm.accepted && launchConfirm.fileManager)
			launchConfirm.fileManager.cancel_launch();
			launchConfirm.playSound("dialog-cancel");
	}

	// The controller's A (Return) and B/Escape are delivered to the focused
	// item, so the sheet's own content handles them while it owns focus.
	ColumnLayout {
		id: confirmContent
		focus: true
		Layout.fillWidth: true
		// A fixed content width keeps the wrapped labels' heights independent of
		// the sheet's own width, which would otherwise be a binding loop.
		Layout.preferredWidth: Kirigami.Units.gridUnit * 20
		spacing: Kirigami.Units.largeSpacing

		Keys.onReturnPressed: launchConfirm.accept()
		Keys.onEnterPressed: launchConfirm.accept()
		Keys.onEscapePressed: launchConfirm.close()

		// The two items at the centre of the decision, like the classic
		// "close X and launch Y?" prompt: the app to close on the left, the one
		// to launch on the right.
		RowLayout {
			Layout.alignment: Qt.AlignHCenter
			spacing: Kirigami.Units.largeSpacing

			ColumnLayout {
				Layout.alignment: Qt.AlignVCenter
				spacing: Kirigami.Units.smallSpacing

				Loader {
					Layout.alignment: Qt.AlignHCenter
					Layout.preferredWidth: Kirigami.Units.iconSizes.large
					Layout.preferredHeight: Kirigami.Units.iconSizes.large
					sourceComponent: itemArtComponent
					onLoaded: item.artSource = Qt.binding(() => launchConfirm.info.blockedIcon || "")
				}

				Label {
					Layout.maximumWidth: Kirigami.Units.gridUnit * 8
					horizontalAlignment: Text.AlignHCenter
					elide: Text.ElideRight
					text: launchConfirm.info.blockedTitle || ""
				}
			}

			Kirigami.Icon {
				Layout.alignment: Qt.AlignVCenter
				source: "go-next"
				implicitWidth: Kirigami.Units.iconSizes.medium
				implicitHeight: Kirigami.Units.iconSizes.medium
			}

			ColumnLayout {
				Layout.alignment: Qt.AlignVCenter
				spacing: Kirigami.Units.smallSpacing

				Loader {
					Layout.alignment: Qt.AlignHCenter
					Layout.preferredWidth: Kirigami.Units.iconSizes.large
					Layout.preferredHeight: Kirigami.Units.iconSizes.large
					sourceComponent: itemArtComponent
					onLoaded: item.artSource = Qt.binding(() => launchConfirm.info.launchIcon || "")
				}

				Label {
					Layout.maximumWidth: Kirigami.Units.gridUnit * 8
					horizontalAlignment: Text.AlignHCenter
					elide: Text.ElideRight
					text: launchConfirm.info.launchTitle || ""
				}
			}
		}

		Label {
			Layout.fillWidth: true
			Layout.maximumWidth: Kirigami.Units.gridUnit * 18
			Layout.alignment: Qt.AlignHCenter
			horizontalAlignment: Text.AlignHCenter
			wrapMode: Text.WordWrap
			text: qsTr("Close the suspended app and launch this one?\nAny unsaved data will be lost.")
		}

		RowLayout {
			Layout.fillWidth: true
			spacing: Kirigami.Units.largeSpacing

			Button {
				Layout.fillWidth: true
				Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5
				text: qsTr("Close and Launch")
				icon.name: "system-run"
				onClicked: launchConfirm.accept()
			}

			Button {
				Layout.fillWidth: true
				Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5
				text: qsTr("Cancel")
				icon.name: "dialog-cancel"
				onClicked: {
					launchConfirm.playSound("button-pressed");
					launchConfirm.close();
				}
			}
		}
	}

	footer: null
}
