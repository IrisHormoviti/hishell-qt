import QtQuick
import QtQuick.Controls

// Qt Quick Controls lays the shortcut label directly against the item text.
// A small gap keeps the two readable in narrow menus.
MenuItem {
	Component.onCompleted: if (contentItem && contentItem.spacing !== undefined)
		contentItem.spacing = 12
}
