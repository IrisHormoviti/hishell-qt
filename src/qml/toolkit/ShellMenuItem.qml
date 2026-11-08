import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

MenuItem {
	id: item

	property string shortcutText: item.action && item.action.shortcut
		? String(item.action.shortcut) : ""
	property string iconName: item.icon.name
	property bool marked: false

	implicitWidth: Math.max(220, contentLayout.implicitWidth + leftPadding + rightPadding)
	implicitHeight: Math.max(implicitBackgroundHeight, contentLayout.implicitHeight + topPadding + bottomPadding)

	indicator: Item {}

	contentItem: RowLayout {
		id: contentLayout
		spacing: Kirigami.Units.smallSpacing

		Label {
			Layout.preferredWidth: Kirigami.Units.gridUnit
			horizontalAlignment: Text.AlignHCenter
			text: (item.checkable ? item.checked : item.marked) ? "✓" : ""
			color: Kirigami.Theme.highlightColor
			font.bold: true
			visible: item.checkable || item.marked
		}

		Kirigami.Icon {
			Layout.preferredWidth: Kirigami.Units.iconSizes.small
			Layout.preferredHeight: Kirigami.Units.iconSizes.small
			source: item.iconName
			visible: item.iconName.length > 0
		}

		Label {
			Layout.fillWidth: true
			text: item.text
			elide: Text.ElideRight
			opacity: item.enabled ? 1 : 0.5
		}

		Label {
			text: item.shortcutText
			opacity: 0.6
			visible: item.shortcutText.length > 0
		}
	}
}
