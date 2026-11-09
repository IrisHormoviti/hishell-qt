import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// The old FileSlot rendering: selection plate, focus border, icon/thumbnail and
// label. Pointer, drag and drop handling stay with the view so the input path
// remains unchanged while the slot markup is shared.
Item {
	id: fileSlot

	property string name
	property string title
	property string icon
	property string thumb
	property bool isDirectory: false
	property bool selected: false
	property bool active: false
	property bool showLabels: true
	property bool labelsBeside: false
	property bool showIcon: true
	property bool listMode: false
	property var columnValues: []
	property bool hovered: false
	property bool pressed: false
	property bool dragging: false
	property bool dotfile: false
	property bool isSymlink: false
	property int controlKind: 0
	property string numberValue: ""
	property bool radioActive: false
	property bool radioSelected: false
	property int iconSize: 48
	property int listIconSize: 18
	property int gridSize: 0

	readonly property bool isButton: fileSlot.controlKind === 1
	readonly property bool isToggle: fileSlot.controlKind === 2 || fileSlot.controlKind === 3
	readonly property bool isNumber: fileSlot.controlKind === 4
	readonly property bool isControl: fileSlot.controlKind !== 0
	readonly property bool hasControlPlate: fileSlot.isControl && !fileSlot.isToggle
	readonly property bool toggleOn: fileSlot.controlKind === 3

	opacity: fileSlot.dragging ? 0.2 : (fileSlot.dotfile ? 0.5 : 1.0)
	scale: fileSlot.listMode ? 1.0
		: (fileSlot.pressed ? 0.9 : (fileSlot.hovered ? 1.05 : 1.0))

	Behavior on opacity {
		NumberAnimation {
			duration: 120
			easing.type: Easing.OutCubic
		}
	}

	Behavior on scale {
		NumberAnimation {
			duration: 120
			easing.type: Easing.OutCubic
		}
	}

	Rectangle {
		anchors.fill: parent
		anchors.margins: 2
		radius: 6
		color: Kirigami.Theme.highlightColor
		opacity: fileSlot.selected ? 0.28 : 0
	}

	Rectangle {
		anchors.fill: parent
		anchors.margins: 1
		color: "transparent"
		border.width: 2
		border.color: Kirigami.Theme.highlightColor
		visible: fileSlot.active
	}

	// A `Type=Button` entry is a control, not a thing to open, so it is drawn
	// as a raised key. A child of a folder-owned radio group is a choice, so it
	// gets a card with an accent border and wash when selected.
	Loader {
		id: plateLoader
		anchors.fill: parent
		active: fileSlot.hasControlPlate || fileSlot.radioActive
		sourceComponent: fileSlot.hasControlPlate
			? buttonPlateComponent : radioPlateComponent
	}

	Component {
		id: buttonPlateComponent

		Item {
			id: buttonPlate
			anchors.fill: parent
			anchors.margins: Kirigami.Units.smallSpacing

			readonly property bool down: fileSlot.pressed
			readonly property bool hot: fileSlot.hovered
			readonly property real plateRadius: 6
			readonly property color body: down
				? Qt.lighter(Kirigami.Theme.highlightColor, 1.25)
				: (hot ? Qt.lighter(Kirigami.Theme.backgroundColor, 1.10)
					: Kirigami.Theme.backgroundColor)

			readonly property var shadowLayers: [
				{ "s": 1.0, "d": 1.5, "o": 0.10 },
				{ "s": 2.0, "d": 2.5, "o": 0.07 },
				{ "s": 3.0, "d": 3.5, "o": 0.05 },
				{ "s": 4.0, "d": 4.5, "o": 0.03 }
			]

			Repeater {
				model: buttonPlate.shadowLayers

				Rectangle {
					required property var modelData
					anchors.fill: buttonRim
					anchors.leftMargin: -modelData.s
					anchors.rightMargin: -modelData.s
					anchors.topMargin: modelData.d - modelData.s
					anchors.bottomMargin: -(modelData.s + modelData.d)
					radius: buttonRim.radius + modelData.s
					color: Qt.rgba(0, 0, 0, 0.35)
					opacity: buttonPlate.down ? modelData.o * 0.5 : modelData.o
				}
			}

			Rectangle {
				id: buttonRim
				anchors.fill: parent
				anchors.topMargin: buttonPlate.down ? 1 : 0
				radius: buttonPlate.plateRadius
				gradient: Gradient {
					GradientStop { position: 0.0; color: Qt.darker(buttonPlate.body, 1.03) }
					GradientStop { position: 0.5; color: Qt.darker(buttonPlate.body, 1.08) }
					GradientStop {
						position: 1.0
						color: buttonPlate.down
							? Qt.darker(buttonPlate.body, 1.12)
							: Qt.darker(buttonPlate.body, 1.16)
					}
				}
				border.width: 1
				border.color: buttonPlate.down || buttonPlate.hot
					? Kirigami.Theme.highlightColor
					: Qt.alpha(Kirigami.Theme.disabledTextColor, 0.7)
			}

			Rectangle {
				id: buttonFace
				anchors.fill: buttonRim
				anchors.margins: 2
				radius: Math.max(2, buttonPlate.plateRadius - 2)
				gradient: Gradient {
					GradientStop {
						position: 0.0
						color: buttonPlate.down
							? Qt.darker(buttonPlate.body, 1.05)
							: Qt.lighter(buttonPlate.body, 1.08)
					}
					GradientStop { position: 0.10; color: buttonPlate.body }
					GradientStop { position: 0.72; color: buttonPlate.body }
					GradientStop {
						position: 0.92
						color: buttonPlate.down
							? Qt.darker(buttonPlate.body, 1.06)
							: Qt.darker(buttonPlate.body, 1.03)
					}
					GradientStop {
						position: 1.0
						color: buttonPlate.down
							? Qt.darker(buttonPlate.body, 1.10)
							: Qt.darker(buttonPlate.body, 1.07)
					}
				}
			}
		}
	}

	Component {
		id: radioPlateComponent

		Rectangle {
			id: radioPlate
			anchors.fill: parent
			anchors.margins: Kirigami.Units.smallSpacing
			radius: 6
			color: fileSlot.pressed
				? Qt.alpha(Kirigami.Theme.highlightColor, 0.25)
				: (fileSlot.hovered
					? Qt.lighter(Kirigami.Theme.backgroundColor, 1.15)
					: Kirigami.Theme.backgroundColor)
			border.width: 1
			border.color: fileSlot.radioSelected
				? Kirigami.Theme.highlightColor : Kirigami.Theme.disabledTextColor
			opacity: fileSlot.radioSelected ? 1.0 : 0.75

			Rectangle {
				anchors.fill: parent
				radius: parent.radius
				color: Kirigami.Theme.highlightColor
				opacity: fileSlot.radioSelected ? 0.12 : 0.0
				Behavior on opacity { NumberAnimation { duration: 120 } }
			}

			Behavior on border.color {
				ColorAnimation { duration: 120 }
			}
			Behavior on opacity {
				NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
			}
		}
	}

	GridLayout {
		anchors.centerIn: parent
		visible: !fileSlot.listMode
		columns: fileSlot.labelsBeside && fileSlot.showLabels ? 2 : 1
		columnSpacing: 4
		rowSpacing: 4

		Item {
			Layout.preferredWidth: fileSlot.iconSize
			Layout.preferredHeight: fileSlot.iconSize
			Layout.alignment: Qt.AlignHCenter

			Image {
				anchors.fill: parent
				source: fileSlot.thumb
				fillMode: Image.PreserveAspectCrop
				visible: fileSlot.thumb.length > 0 && fileSlot.showIcon
					&& !fileSlot.isToggle
			}

			Image {
				anchors.fill: parent
				source: fileSlot.icon.length > 0 && fileSlot.icon.startsWith("file:")
					? fileSlot.icon : ""
				fillMode: Image.PreserveAspectFit
				visible: fileSlot.thumb.length === 0 && fileSlot.showIcon
					&& fileSlot.icon.startsWith("file:") && !fileSlot.isToggle
			}

			Kirigami.Icon {
				anchors.fill: parent
				source: fileSlot.icon
				visible: fileSlot.thumb.length === 0 && fileSlot.showIcon
					&& !fileSlot.icon.startsWith("file:") && !fileSlot.isToggle
			}

			ToggleSwitch {
				anchors.centerIn: parent
				width: parent.width
				height: parent.height
				on: fileSlot.toggleOn
				visible: fileSlot.isToggle
			}
		}

		Label {
			Layout.fillWidth: fileSlot.labelsBeside && fileSlot.showLabels
			Layout.preferredWidth: fileSlot.labelsBeside && fileSlot.showLabels
				? Math.max(0, fileSlot.width - fileSlot.iconSize - 12)
				: fileSlot.width - 8
			Layout.alignment: Qt.AlignVCenter
			visible: fileSlot.showLabels
			text: fileSlot.title.length > 0 ? fileSlot.title : fileSlot.name
			elide: Text.ElideMiddle
			font.bold: fileSlot.active
			font.italic: fileSlot.isSymlink
			horizontalAlignment: fileSlot.labelsBeside && fileSlot.showLabels
				? Text.AlignLeft : Text.AlignHCenter
		}
	}
	RowLayout {
		anchors.fill: parent
		anchors.leftMargin: 6
		anchors.rightMargin: 6
		spacing: 8
		visible: fileSlot.listMode

		Item {
			Layout.preferredWidth: 24
			Layout.preferredHeight: 24

			Image {
				anchors.fill: parent
				source: fileSlot.thumb
				fillMode: Image.PreserveAspectCrop
				visible: fileSlot.thumb.length > 0 && !fileSlot.isToggle
			}
			Image {
				anchors.fill: parent
				source: fileSlot.icon.startsWith("file:") ? fileSlot.icon : ""
				fillMode: Image.PreserveAspectFit
				visible: fileSlot.thumb.length === 0
					&& fileSlot.icon.startsWith("file:") && !fileSlot.isToggle
			}
			Kirigami.Icon {
				anchors.fill: parent
				source: fileSlot.icon
				visible: fileSlot.thumb.length === 0
					&& !fileSlot.icon.startsWith("file:") && !fileSlot.isToggle
			}
			ToggleSwitch {
				anchors.centerIn: parent
				width: parent.width
				height: parent.height
				on: fileSlot.toggleOn
				visible: fileSlot.isToggle
			}
		}

		Repeater {
			model: fileSlot.columnValues

			Label {
				required property var modelData
				Layout.fillWidth: modelData.fill
				Layout.preferredWidth: modelData.fill ? -1 : modelData.width
				text: modelData.text
				elide: Text.ElideRight
				horizontalAlignment: modelData.align
				font.bold: modelData.nameColumn && fileSlot.active
				font.italic: modelData.nameColumn && fileSlot.isSymlink
				opacity: modelData.nameColumn ? 1.0 : 0.85
				visible: fileSlot.showLabels
			}
		}
	}
}
