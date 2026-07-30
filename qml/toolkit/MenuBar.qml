import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

MenuBar {
	Menu {
		title: qsTr("New")
		MenuItem {
			text: qsTr("Folder")
			icon.name: "folder-add"
			onTriggered: {
				// Handle new folder action
			}
		}
		MenuItem {
			text: qsTr("Text File")
			icon.name: "text-plain"
			onTriggered: {
				// Handle new file action
			}
		}
	}

	Menu {
		title: qsTr("Edit")
		MenuItem {
			text: qsTr("Copy")
			icon.name: "edit-copy"
			onTriggered: { /* ... */ }
		}
		MenuItem {
			text: qsTr("Cut")
			icon.name: "edit-cut"
			onTriggered: { /* ... */ }
		}
		MenuItem {
			text: qsTr("Duplicate")
			icon.name: "edit-duplicate"
			onTriggered: { /* ... */ }
		}
		MenuItem {
			text: qsTr("Link")
			icon.name: "edit-link"
			onTriggered: { /* ... */ }
		}
		MenuItem {
			text: qsTr("Rename")
			icon.name: "edit-rename"
			onTriggered: { /* ... */ }
		}
	}

	Menu {
		title: qsTr("View")

		MenuItem {
			contentItem: RowLayout {
				spacing: 2

				Kirigami.NavigationTabButton {
					text: "General"
					checked: true
				}

				Kirigami.NavigationTabButton {
					text: "Here"
				}
			}
		}

		MenuItem {
			onTriggered: {
				// optional code
			}

			contentItem: RowLayout {
				spacing: 10

				Label {
					text: qsTr("Icon Size")
				}

				Slider {
					from: 32
					to: 128
					value: 64
					onMoved: {
						// Handle slider value changes here
					}
				}
			}
		}


		MenuItem {
			text: qsTr("Show Dotfiles")
			checkable: true
			// checked: config.stash_dotfiles // bind if applicable
			onToggled: {
				// Toggle config setting
			}
		}
	}
}
