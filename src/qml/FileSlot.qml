import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

// The old FileSlot rendering: selection plate, focus outline, icon/thumbnail
// and label. Pointer, drag and drop handling stay with the view so the input
// path remains unchanged while the slot markup is shared.
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
	property bool selectionActive: false
	property bool dropHovered: false
	property bool activeApp: false
	property bool labelShowsFilename: false
	property int iconSize: 48
	property int listIconSize: 18
	property int gridSize: 0

	readonly property string fileName: fileSlot.name
	readonly property string displayTitle: fileSlot.title.length > 0
		? fileSlot.title : fileSlot.name
	readonly property string labelText: fileSlot.labelShowsFilename
		|| fileSlot.title.length === 0
		? fileSlot.name : fileSlot.displayTitle

	readonly property string tooltipText: {
		const label = fileSlot.title.length > 0 ? fileSlot.title : fileSlot.name
		const alternate = fileSlot.labelShowsFilename
			? fileSlot.title : fileSlot.name
		if (!fileSlot.showLabels)
			return alternate !== "" && alternate !== label
				? label + "\n" + alternate : label
		if (fileSlot.title === "" || fileSlot.title === fileSlot.name)
			return ""
		return alternate
	}

	ToolTip.visible: fileSlot.tooltipText.length > 0 && fileSlot.hovered
		&& !fileSlot.dragging
	ToolTip.text: fileSlot.tooltipText
	ToolTip.delay: 700

	readonly property bool isButton: fileSlot.controlKind === 1
	readonly property bool isToggle: fileSlot.controlKind === 2 || fileSlot.controlKind === 3
	readonly property bool isNumber: fileSlot.controlKind === 4
	readonly property bool isControl: fileSlot.controlKind !== 0
	readonly property bool hasControlPlate: fileSlot.isControl && !fileSlot.isToggle
	readonly property bool toggleOn: fileSlot.controlKind === 3
	// Without a label the icon takes over the whole slot, so the view reads as
	// a gallery, like the old FileSlot.
	readonly property real iconDisplaySize: fileSlot.showLabels
		? fileSlot.iconSize
		: Math.max(fileSlot.iconSize,
			Math.min(fileSlot.width, fileSlot.height)
				- Kirigami.Units.smallSpacing * 2)

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

	// The wash behind the active/radio choice and every selected item. The
	// view draws the focus outline above it.
	Rectangle {
		anchors.fill: parent
		anchors.margins: fileSlot.selected
			? Kirigami.Units.smallSpacing : 0
		radius: Kirigami.Units.cornerRadius
		color: Kirigami.Theme.highlightColor
		opacity: (fileSlot.selected ? 0.25 : 0.0)
			|| (fileSlot.active ? 0.5 : 0.0)
	}

	// A selected item in selection mode gets the old accent outline as well as
	// the wash, so it reads as a selection rather than only the current item.
	Rectangle {
		visible: fileSlot.selectionActive && fileSlot.selected
		anchors.fill: parent
		anchors.margins: Kirigami.Units.smallSpacing
		radius: Kirigami.Units.cornerRadius
		color: "transparent"
		border.width: 2
		border.color: Kirigami.Theme.highlightColor
	}

	// Selection mode puts a check badge on every selected choice, with an
	// empty square on the rest.
	Rectangle {
		visible: fileSlot.selectionActive
		anchors.top: parent.top
		anchors.right: parent.right
		anchors.margins: Kirigami.Units.mediumSpacing
		width: Kirigami.Units.iconSizes.small
		height: Kirigami.Units.iconSizes.small
		radius: 4
		border.width: 2
		border.color: Kirigami.Theme.highlightColor
		color: fileSlot.selected
			? Kirigami.Theme.highlightColor : "transparent"
		opacity: fileSlot.selected ? 1.0 : 0.4

		Kirigami.Icon {
			anchors.fill: parent
			anchors.margins: 2
			source: "emblem-ok-symbolic"
			color: Kirigami.Theme.highlightedTextColor
			opacity: fileSlot.selected ? 1.0 : 0.0
		}
	}

	Rectangle {
		visible: fileSlot.dropHovered
		anchors.fill: parent
		anchors.margins: 2
		radius: Kirigami.Units.cornerRadius
		color: Kirigami.Theme.focusColor
		opacity: 0.35
		border.color: Kirigami.Theme.highlightColor
		border.width: 2
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
			readonly property real plateRadius: Kirigami.Units.cornerRadius * 1.5
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
			radius: Kirigami.Units.cornerRadius * 1.5
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
		anchors.verticalCenter: parent.verticalCenter
		x: fileSlot.labelsBeside && fileSlot.showLabels && fileSlot.showIcon
			? Kirigami.Units.largeSpacing
			: (parent.width - width) / 2
		visible: !fileSlot.listMode
		columns: fileSlot.labelsBeside && fileSlot.showLabels ? 2 : 1
		columnSpacing: 4
		rowSpacing: Kirigami.Units.smallSpacing

		Item {
			Layout.preferredWidth: fileSlot.iconDisplaySize
			Layout.preferredHeight: fileSlot.iconDisplaySize
			Layout.alignment: fileSlot.labelsBeside && fileSlot.showLabels
				? Qt.AlignVCenter : Qt.AlignHCenter

			// Active glow when the app this item is attached to is running.
			Shape {
				id: activeGlow
				visible: fileSlot.activeApp
				z: -1
				width: parent.width
				height: parent.height
				anchors.centerIn: parent

				ShapePath {
					strokeColor: "transparent"

					PathRectangle {
						width: activeGlow.width
						height: activeGlow.height
						x: 0
						y: 0
					}

					fillGradient: RadialGradient {
						centerX: activeGlow.width / 2
						centerY: activeGlow.height / 2
						centerRadius: Math.min(activeGlow.width, activeGlow.height) / 2
						focalX: centerX
						focalY: centerY
						focalRadius: 0

						GradientStop { position: 1.0; color: "transparent" }
						GradientStop {
							position: 0.0
							color: Kirigami.Theme.highlightColor
						}
					}
				}

				SequentialAnimation on opacity {
					running: activeGlow.visible
					loops: Animation.Infinite
					NumberAnimation {
						to: 0.35
						duration: 1000
						easing.type: Easing.InOutQuad
					}
					NumberAnimation {
						to: 1.0
						duration: 1000
						easing.type: Easing.InOutQuad
					}
				}
			}

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

			Switch {
				anchors.centerIn: parent
				checked: fileSlot.toggleOn
				text: ""
				focusPolicy: Qt.NoFocus
				activeFocusOnTab: false
				hoverEnabled: false
				transformOrigin: Item.Center
				scale: Math.min(parent.width / Math.max(1, implicitWidth),
					parent.height / Math.max(1, implicitHeight))
				visible: fileSlot.isToggle
			}
		}

		Label {
			readonly property real maximumWidth: fileSlot.hasControlPlate
					|| fileSlot.radioActive
				? fileSlot.width - Kirigami.Units.smallSpacing * 2
					- Kirigami.Units.largeSpacing * 2
				: (fileSlot.labelsBeside && fileSlot.showLabels
					? Math.max(0, fileSlot.width - fileSlot.iconDisplaySize
						- Kirigami.Units.gridUnit * 2)
					: fileSlot.width - Kirigami.Units.smallSpacing * 4)
			Layout.preferredWidth: maximumWidth
			Layout.maximumWidth: maximumWidth
			Layout.alignment: Qt.AlignVCenter
			visible: fileSlot.showLabels
			text: fileSlot.labelText
			textFormat: Text.PlainText
			wrapMode: Text.Wrap
			maximumLineCount: 2
			elide: Text.ElideRight
			font.bold: fileSlot.active
			font.italic: fileSlot.isSymlink
			horizontalAlignment: fileSlot.labelsBeside && fileSlot.showLabels
				? Text.AlignLeft : Text.AlignHCenter
		}
	}
	RowLayout {
		anchors.fill: parent
		anchors.leftMargin: Kirigami.Units.smallSpacing * 2
		anchors.rightMargin: Kirigami.Units.smallSpacing * 2
		spacing: Kirigami.Units.mediumSpacing
		visible: fileSlot.listMode

		Item {
			Layout.preferredWidth: fileSlot.listIconSize
			Layout.preferredHeight: fileSlot.listIconSize

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
			Switch {
				anchors.centerIn: parent
				checked: fileSlot.toggleOn
				text: ""
				focusPolicy: Qt.NoFocus
				activeFocusOnTab: false
				hoverEnabled: false
				transformOrigin: Item.Center
				scale: Math.min(parent.width / Math.max(1, implicitWidth),
					parent.height / Math.max(1, implicitHeight))
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
				textFormat: Text.PlainText
				maximumLineCount: 1
				elide: Text.ElideRight
				horizontalAlignment: modelData.align
				font.bold: modelData.nameColumn && fileSlot.active
				font.italic: modelData.nameColumn && fileSlot.isSymlink
				opacity: modelData.nameColumn ? 1.0 : 0.85
			}
		}
	}
}
