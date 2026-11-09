import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// The type-to-filter bar: shown above the view while a filter is active, with
// the typed text, the match count and a clear button.
Rectangle {
	id: filterBar

	property var directory: null
	property int matchCount: 0
	property bool filterActive: false
	property var window: null

	signal focusRequested()
	signal clearRequested()

	z: 3
	anchors.top: parent.top
	anchors.left: parent.left
	anchors.right: parent.right
	anchors.margins: Kirigami.Units.mediumSpacing
	height: Kirigami.Units.gridUnit * 2
	radius: Kirigami.Units.cornerRadius

	visible: opacity > 0
	opacity: filterBar.filterActive ? 1 : 0
	Behavior on opacity {
		NumberAnimation {
			duration: 120
			easing.type: Easing.OutCubic
		}
	}

	color: Kirigami.Theme.backgroundColor
	border.width: 1
	border.color: Kirigami.Theme.highlightColor

	MouseArea {
		anchors.fill: parent
		acceptedButtons: Qt.AllButtons
		onPressed: function (mouse) {
			mouse.accepted = true
			filterBar.focusRequested()
		}
	}

	RowLayout {
		anchors.fill: parent
		anchors.leftMargin: Kirigami.Units.largeSpacing
		anchors.rightMargin: Kirigami.Units.smallSpacing
		spacing: Kirigami.Units.smallSpacing

		Kirigami.Icon {
			source: "search"
			Layout.preferredWidth: Kirigami.Units.iconSizes.small
			Layout.preferredHeight: Kirigami.Units.iconSizes.small
		}

		Label {
			text: filterBar.directory ? String(filterBar.directory.filter) : ""
			font.weight: Font.Medium
			elide: Text.ElideRight
			Layout.fillWidth: true
		}

		Label {
			text: filterBar.matchCount === 1 ? "1 match"
				: filterBar.matchCount + " matches"
			opacity: 0.7
			elide: Text.ElideRight
		}

		ToolButton {
			icon.name: "edit-clear"
			focusPolicy: Qt.NoFocus
			flat: true
			ToolTip.text: "Clear filter"
			ToolTip.visible: hovered
			onClicked: filterBar.clearRequested()
		}
	}
}
