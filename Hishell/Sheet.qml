import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Hishell.Theme

// The shell's modal sheet: a rounded card that slides over the window, sized
// to its content and anchored to the bottom of the screen. It replaces the
// Kirigami overlay sheet with the same shape the dialogs use: a title, an
// optional pinned header, the content, and an optional footer.
//
// Content children go to `content`; a dialog that needs a fixed part above a
// scrolling list puts it in `header`.

Popup {
	id: sheet

	property string title: ""
	property Item header: null
	property Item footer: null
	default property alias content: body.data

	modal: true
	dim: true
	focus: true
	padding: 0
	closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

	width: Math.min(implicitWidth > 0 ? implicitWidth : Units.gridUnit * 20,
		(parent ? parent.width : Units.gridUnit * 20) - Units.largeSpacing * 4)
	height: Math.min(implicitHeight, (parent ? parent.height : Units.gridUnit * 20) - Units.largeSpacing * 4)
	x: parent ? Math.round((parent.width - width) / 2) : 0
	y: parent ? Math.max(Units.largeSpacing, parent.height - height - Units.largeSpacing) : 0

	onHeaderChanged: {
		if (sheet.header) {
			sheet.header.parent = headerSlot
			sheet.header.width = Qt.binding(function() { return headerSlot.width })
		}
	}
	onFooterChanged: {
		if (sheet.footer) {
			sheet.footer.parent = footerSlot
			sheet.footer.width = Qt.binding(function() { return footerSlot.width })
		}
	}

	background: Rectangle {
		radius: Units.cornerRadius * 3
		color: Theme.backgroundColor
		border.width: 1
		border.color: Qt.rgba(0, 0, 0, 0.18)
	}

	contentItem: ColumnLayout {
		spacing: Units.smallSpacing

		RowLayout {
			Layout.fillWidth: true
			Layout.leftMargin: Units.largeSpacing
			Layout.rightMargin: Units.smallSpacing
			Layout.topMargin: Units.smallSpacing
			visible: sheet.title !== ""
			Label {
				Layout.fillWidth: true
				text: sheet.title
				font.bold: true
				font.pixelSize: Math.round(Units.gridUnit * 0.9)
				elide: Text.ElideRight
			}
			ToolButton {
				icon.name: "window-close"
				focusPolicy: Qt.NoFocus
				onClicked: sheet.close()
			}
		}

		Item {
			id: headerSlot
			Layout.fillWidth: true
			Layout.leftMargin: Units.largeSpacing
			Layout.rightMargin: Units.largeSpacing
			Layout.preferredHeight: sheet.header ? sheet.header.implicitHeight : 0
			visible: sheet.header !== null
		}

		ColumnLayout {
			id: body
			Layout.fillWidth: true
			Layout.fillHeight: true
			Layout.leftMargin: Units.largeSpacing
			Layout.rightMargin: Units.largeSpacing
			Layout.bottomMargin: sheet.footer ? 0 : Units.largeSpacing
			spacing: Units.smallSpacing
		}

		Item {
			id: footerSlot
			Layout.fillWidth: true
			Layout.leftMargin: Units.largeSpacing
			Layout.rightMargin: Units.largeSpacing
			Layout.bottomMargin: Units.largeSpacing
			Layout.preferredHeight: sheet.footer ? sheet.footer.implicitHeight : 0
			visible: sheet.footer !== null
		}
	}
}
