pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami
import ClamOS.Theme

Kirigami.OverlaySheet {
	id: viewDialog
	// The shared settings object. Required so the dialog cannot be opened
	// without a Directory to act on.
	required property ViewActions viewActions

	title: qsTr("View Options")

	// Event sounds (ClamOS XDG sound theme). The View button that opens this
	// sheet plays the dialog sound; closing it is a "back" in the 3DS
	// vocabulary.
	function playSound(name) {
		viewDialog.viewActions.playSound(name);
	}
	onClosed: playSound("return")

	implicitWidth: Kirigami.Units.gridUnit * 20
	// OverlaySheet caps its height at the window and scrolls the content; the
	// explicit maximum keeps the last groups reachable on the short touch panel.
	closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

	// A row of connected buttons for a mutually exclusive choice: one segmented
	// control instead of separate radio buttons, so the selected value reads at a
	// glance and the tap targets are thicker.
	//
	// The buttons are created imperatively from `options` rather than through a
	// Repeater: on this Qt (6.8.2) the Repeater model roles never reached the
	// delegate — `index` and `modelData` were undefined at runtime, so every
	// segment drew with empty text and unrounded edges. Creating each button and
	// assigning its entry directly avoids delegate context entirely.
	// Each option is { text, icon, value }; `currentValue` marks the selected one
	// and `activated(value)` reports a choice.
	component Segmented: Item {
		id: segmented
		property var options: []
		property var currentValue: null
		signal activated(var value)
		Layout.fillWidth: true
		Layout.margins: Kirigami.Units.largeSpacing
		implicitHeight: segmentRow.implicitHeight

		readonly property real groupRadius: Kirigami.Units.cornerRadius + 2

		// A soft stacked shadow under the whole group, so the control reads as
		// one raised key rather than a row of separate buttons.
		Rectangle {
			anchors.fill: groupRim
			anchors.topMargin: 5
			anchors.bottomMargin: -7
			radius: groupRim.radius + 5
			color: ClamTheme.shadowColor
			opacity: 0.05
		}
		Rectangle {
			anchors.fill: groupRim
			anchors.topMargin: 2
			anchors.bottomMargin: -3
			radius: groupRim.radius + 1
			color: ClamTheme.shadowColor
			opacity: 0.08
		}

		// One shaded frame the segments sit inside, so the shared edges between
		// segments stay clean and the group has a single outer bevel.
		Rectangle {
			id: groupRim
			anchors.fill: parent
			radius: segmented.groupRadius
			gradient: Gradient {
				GradientStop { position: 0.0; color: Qt.darker(ClamTheme.surfaceColor, 1.03) }
				GradientStop { position: 1.0; color: Qt.darker(ClamTheme.surfaceColor, 1.16) }
			}
			border.width: 1
			border.color: Qt.alpha(ClamTheme.borderDarkColor, 0.7)
		}

		RowLayout {
			id: segmentRow
			anchors.fill: groupRim
			anchors.margins: 2
			spacing: 0
		}

		Component {
			id: segmentComponent

			Button {
				id: segButton

				// Set at creation by rebuild(); never read from a model role.
				property var entry: null
				property int segIndex: 0
				property int segCount: 1
				property bool segCurrent: false

				readonly property bool isSelected: segButton.segCurrent
				readonly property bool isFirst: segButton.segIndex === 0
				readonly property bool isLast: segButton.segIndex === segButton.segCount - 1
				// A light accent tint for the recessed cell, kept readable: on a
				// light fill the label goes dark, otherwise it stays white.
				readonly property color sunkBody: Qt.lighter(ClamTheme.accentColor, 1.15)
				readonly property color sunkText: ClamTheme.luminance(segButton.sunkBody) > 0.6 ? "#24222a" : "#ffffff"

				Layout.fillWidth: true
				Layout.minimumHeight: Kirigami.Units.gridUnit * 2

				highlighted: segButton.isSelected
				text: segButton.entry ? segButton.entry.text : ""
				icon.name: (segButton.entry && segButton.entry.icon !== undefined) ? segButton.entry.icon : ""
				display: icon.name.length > 0 ? AbstractButton.TextBesideIcon : AbstractButton.TextOnly
				onPressed: viewDialog.playSound("button-pressed")
				onReleased: viewDialog.playSound("button-released")
				onClicked: segmented.activated(segButton.entry.value)

				// The style's Button would paint a whole raised key; a segment is
				// one cell of a group, so draw the label here and a flat cell
				// below, keeping the group's shared edges straight.
				contentItem: Label {
					text: segButton.text
					font: segButton.font
					horizontalAlignment: Text.AlignHCenter
					verticalAlignment: Text.AlignVCenter
					elide: Text.ElideRight
					visible: segButton.display !== AbstractButton.IconOnly
					color: segButton.isSelected ? segButton.sunkText : ClamTheme.textColor
				}

				// One cell of the group. Only the outer corners are rounded, so
				// the row reads as a single control. Unselected cells are raised
				// (light top, shaded bottom); the selected cell is pressed into
				// the frame instead (dark top shadow, bright bottom lip) so it
				// reads as the recessed current choice. A divider separates
				// neighbours.
				background: Item {
					id: segCell
					readonly property real r: segmented.groupRadius - 2
					readonly property bool sunk: segButton.isSelected

					Rectangle {
						id: segFace
						anchors.fill: parent
						topLeftRadius: segButton.isFirst ? segCell.r : 0
						bottomLeftRadius: segButton.isFirst ? segCell.r : 0
						topRightRadius: segButton.isLast ? segCell.r : 0
						bottomRightRadius: segButton.isLast ? segCell.r : 0
						gradient: Gradient {
							GradientStop { position: 0.0; color: segCell.sunk ? Qt.darker(segButton.sunkBody, 1.10) : Qt.lighter(ClamTheme.surfaceColor, 1.06) }
							GradientStop { position: 0.14; color: segCell.sunk ? segButton.sunkBody : ClamTheme.surfaceColor }
							GradientStop { position: 0.78; color: segCell.sunk ? segButton.sunkBody : ClamTheme.surfaceColor }
							GradientStop { position: 1.0; color: segCell.sunk ? Qt.lighter(segButton.sunkBody, 1.08) : Qt.darker(ClamTheme.surfaceColor, 1.08) }
						}
					}

					// The frame's shadow falls into the recessed cell.
					Rectangle {
						visible: segCell.sunk
						anchors.top: segFace.top
						anchors.left: segFace.left
						anchors.right: segFace.right
						height: Math.round(segFace.height * 0.45)
						topLeftRadius: segFace.topLeftRadius
						topRightRadius: segFace.topRightRadius
						gradient: Gradient {
							GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.22) }
							GradientStop { position: 1.0; color: "transparent" }
						}
					}
					// ...and the recessed lip catches a bright line at the bottom.
					Rectangle {
						visible: segCell.sunk
						anchors.left: segFace.left
						anchors.right: segFace.right
						anchors.bottom: segFace.bottom
						height: 1
						color: Qt.rgba(1, 1, 1, 0.4)
					}

					// Press and hover feedback, painted over the cell.
					Rectangle {
						anchors.fill: segFace
						topLeftRadius: segFace.topLeftRadius
						bottomLeftRadius: segFace.bottomLeftRadius
						topRightRadius: segFace.topRightRadius
						bottomRightRadius: segFace.bottomRightRadius
						color: ClamTheme.shadowColor
						opacity: segButton.down ? 0.14 : 0.0
						Behavior on opacity { NumberAnimation { duration: 120 } }
					}
					Rectangle {
						anchors.fill: segFace
						topLeftRadius: segFace.topLeftRadius
						bottomLeftRadius: segFace.bottomLeftRadius
						topRightRadius: segFace.topRightRadius
						bottomRightRadius: segFace.bottomRightRadius
						color: ClamTheme.accentColor
						opacity: (segButton.hovered && !segButton.down && !segCell.sunk) ? 0.06 : 0.0
						Behavior on opacity { NumberAnimation { duration: 120 } }
					}

					// Divider between neighbours.
					Rectangle {
						visible: !segButton.isFirst
						anchors.left: parent.left
						anchors.top: parent.top
						anchors.bottom: parent.bottom
						width: 1
						color: Qt.alpha(ClamTheme.borderDarkColor, 0.7)
					}
				}
			}
		}

		property var _buttons: []

		Component.onCompleted: segmented.rebuild()
		onOptionsChanged: segmented.rebuild()
		onCurrentValueChanged: segmented.updateSelection()

		function rebuild() {
			for (let i = 0; i < segmented._buttons.length; i++)
				segmented._buttons[i].destroy();
			segmented._buttons = [];

			const list = segmented.options || [];
			for (let i = 0; i < list.length; i++) {
				const button = segmentComponent.createObject(segmentRow, {
					entry: list[i],
					segIndex: i,
					segCount: list.length,
					segCurrent: segmented.currentValue === list[i].value
				});
				if (button)
					segmented._buttons.push(button);
			}
		}

		function updateSelection() {
			const list = segmented.options || [];
			for (let i = 0; i < segmented._buttons.length; i++) {
				segmented._buttons[i].segCurrent = i < list.length
					&& segmented.currentValue === list[i].value;
			}
		}
	}

	// A labelled switch that spans the row, with the knob on the trailing edge
	// so it lines up with the rest of the full-width controls.
	component ToggleRow: RowLayout {
		id: toggleRow
		property alias text: toggleLabel.text
		property bool checked: false
		// Rows for settings that have no effect right now are shown greyed out
		// rather than hidden, so the option stays discoverable.
		property bool rowEnabled: true
		signal toggled(bool checked)
		Layout.fillWidth: true
		enabled: toggleRow.rowEnabled
		Label {
			id: toggleLabel
			Layout.fillWidth: true
			wrapMode: Text.WordWrap
		}
		Switch {
			id: toggleSwitch
			Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
			onToggled: {
				toggleRow.toggled(checked);
				viewDialog.playSound(checked ? "button-toggle-on" : "button-toggle-off");
			}
			Binding {
				target: toggleSwitch
				property: "checked"
				value: toggleRow.checked
				restoreMode: Binding.RestoreNone
			}
		}
	}

	component SectionHeading: Label {
		Layout.fillWidth: true
		Layout.topMargin: Kirigami.Units.largeSpacing
		font.bold: true
		font.capitalization: Font.AllUppercase
		opacity: 0.6
	}

	ColumnLayout {
		// The dialog sizes itself to this content and scrolls it when it is
		// taller than the panel; width comes from the dialog's preferredWidth.
		spacing: Kirigami.Units.largeSpacing

		// ── Scope ────────────────────────────────────────────────────────
		SectionHeading {
			text: qsTr("Apply To")
		}
		Segmented {
			options: [
				{ text: qsTr("General"), value: false },
				{ text: qsTr("This Folder"), value: true }
			]
			currentValue: viewDialog.viewActions.isLocal
			onActivated: value => viewDialog.viewActions.isLocal = value
		}

		// ── Display ──────────────────────────────────────────────────────
		SectionHeading {
			text: qsTr("Display")
		}
		Segmented {
			options: [
				{ text: qsTr("Grid"), icon: "view-grid", value: "GRID" },
				{ text: qsTr("List"), icon: "view-list-details", value: "LIST" }
			]
			currentValue: viewDialog.viewActions.viewMode === 0 ? "GRID" : "LIST"
			onActivated: value => viewDialog.viewActions.setViewModeSilent(value)
		}
		RowLayout {
			Layout.fillWidth: true
			spacing: Kirigami.Units.smallSpacing

			Label {
				text: qsTr("Icon Size")
			}
			ViewSlider {
				id: gridSizeSlider
				Layout.fillWidth: true
				// The setting is the single source of truth; the slider shows it
				// whenever it is not being dragged.
				boundValue: viewDialog.viewActions.gridSize
				from: viewDialog.viewActions.gridSizeMin
				to: viewDialog.viewActions.gridSizeMax
				stepSize: viewDialog.viewActions.gridSizeStep
				onMovedTo: value => viewDialog.viewActions.setGridSize(value)
				onDragStarted: viewDialog.playSound("button-pressed")
				onStepped: viewDialog.playSound("slider-tick")
				onReachedEdge: viewDialog.playSound("scroll-edge")
			}
			Label {
				Layout.minimumWidth: Kirigami.Units.gridUnit * 3
				horizontalAlignment: Text.AlignHCenter
				text: viewDialog.viewActions.gridSize
			}
		}

		// ── Labels ───────────────────────────────────────────────────────
		SectionHeading {
			text: qsTr("Labels")
		}
		ToggleRow {
			text: qsTr("Show Labels")
			checked: viewDialog.viewActions.showLabels
			onToggled: checked => viewDialog.viewActions.setConfig("ShowLabels", String(checked))
		}
		ToggleRow {
			text: qsTr("Labels Beside Icons")
			enabled: viewDialog.viewActions.showLabels
			checked: viewDialog.viewActions.labelsBesideIcons
			onToggled: checked => viewDialog.viewActions.setConfig("GridLabelsBesidesIcons", String(checked))
		}
		Segmented {
			enabled: viewDialog.viewActions.showLabels
			options: [
				{ text: qsTr("Titles"), value: "TITLE" },
				{ text: qsTr("File Names"), value: "FILENAME" }
			]
			currentValue: viewDialog.viewActions.labelText === 0 ? "TITLE" : "FILENAME"
			onActivated: value => viewDialog.viewActions.setConfig("LabelText", value)
		}

		// ── Sorting ──────────────────────────────────────────────────────
		SectionHeading {
			text: qsTr("Sort By")
		}
		Segmented {
			options: {
				const list = [
					{ text: qsTr("Newest"), value: "NEWEST" },
					{ text: qsTr("Oldest"), value: "OLDEST" },
					{ text: qsTr("Name"), value: "ALPHABETICAL" }
				];
				// Free placement only makes sense for a folder's own config.
				if (viewDialog.viewActions.isLocal)
					list.push({ text: qsTr("Free"), value: "FREE" });
				return list;
			}
			currentValue: ["NEWEST", "OLDEST", "ALPHABETICAL", "FREE"][viewDialog.viewActions.sort]
			onActivated: value => viewDialog.viewActions.setSortSilent(value)
		}
		RowLayout {
			Layout.fillWidth: true
			spacing: Kirigami.Units.smallSpacing
			visible: viewDialog.viewActions.sort === 0 || viewDialog.viewActions.sort === 1

			Label {
				text: qsTr("By date")
			}
			Segmented {
				options: [
					{ text: qsTr("Modified"), value: "MODIFIED" },
					{ text: qsTr("Created"), value: "CREATED" },
					{ text: qsTr("Accessed"), value: "ACCESSED" }
				]
				currentValue: ["MODIFIED", "CREATED", "ACCESSED"][viewDialog.viewActions.sortDateMode]
				onActivated: value => viewDialog.viewActions.setConfig("SortDateMode", value)
			}
		}
		RowLayout {
			Layout.fillWidth: true
			spacing: Kirigami.Units.smallSpacing
			visible: viewDialog.viewActions.sort === 2

			Label {
				text: qsTr("By name")
			}
			Segmented {
				options: [
					{ text: qsTr("Titles"), value: "TITLES" },
					{ text: qsTr("File Names"), value: "FILENAMES" }
				]
				currentValue: viewDialog.viewActions.sortAlphaMode === 0 ? "TITLES" : "FILENAMES"
				onActivated: value => viewDialog.viewActions.setConfig("SortAlphaMode", value)
			}
		}
		// Only offered while there is something to reset.
		Button {
			Layout.fillWidth: true
			Layout.minimumHeight: Kirigami.Units.gridUnit * 2.4
			visible: viewDialog.viewActions.hasFreePlacementPositions
			text: qsTr("Reset Manual Placement")
			icon.name: "edit-reset"
			onPressed: viewDialog.playSound("button-pressed")
			onReleased: viewDialog.playSound("button-released")
			onClicked: viewDialog.viewActions.resetFreePlacement()
		}

		// ── Arrangement ──────────────────────────────────────────────────
		SectionHeading {
			text: qsTr("Arrange")
		}
		RowLayout {
			Layout.fillWidth: true
			spacing: Kirigami.Units.smallSpacing

			Label {
				text: qsTr("Lines")
			}
			ViewSlider {
				id: linesSlider
				Layout.fillWidth: true
				boundValue: viewDialog.viewActions.gridLines
				from: 0
				to: 10
				stepSize: 1
				onMovedTo: value => viewDialog.viewActions.setConfig("Lines", String(value))
				onDragStarted: viewDialog.playSound("button-pressed")
				onStepped: viewDialog.playSound("slider-tick")
				onReachedEdge: viewDialog.playSound("scroll-edge")
			}
			Label {
				Layout.minimumWidth: Kirigami.Units.gridUnit * 3
				horizontalAlignment: Text.AlignHCenter
				text: viewDialog.viewActions.gridLines === 0 ? qsTr("Auto") : viewDialog.viewActions.gridLines
			}
		}
		RowLayout {
			Layout.fillWidth: true
			spacing: Kirigami.Units.smallSpacing
			Label {
				text: qsTr("Scroll")
			}
			Segmented {
				options: [
					{ text: qsTr("Vertical"), value: "VERTICAL" },
					{ text: qsTr("Horizontal"), value: "HORIZONTAL" }
				]
				currentValue: viewDialog.viewActions.scrollHorizontal ? "HORIZONTAL" : "VERTICAL"
				onActivated: value => viewDialog.viewActions.setConfig("ScrollDirection", value)
			}
		}
		RowLayout {
			Layout.fillWidth: true
			spacing: Kirigami.Units.smallSpacing
			Label {
				text: qsTr("Align X")
			}
			Segmented {
				options: [
					{ text: qsTr("Fill"), value: "FILL" },
					{ text: qsTr("Left"), value: "LEFT" },
					{ text: qsTr("Center"), value: "CENTER" },
					{ text: qsTr("Right"), value: "RIGHT" }
				]
				currentValue: ["FILL", "LEFT", "CENTER", "RIGHT"][viewDialog.viewActions.horizontalAlign]
				onActivated: value => viewDialog.viewActions.setConfig("GridHorizontalAlign", value)
			}
		}
		RowLayout {
			Layout.fillWidth: true
			spacing: Kirigami.Units.smallSpacing
			Label {
				text: qsTr("Align Y")
			}
			Segmented {
				options: [
					{ text: qsTr("Fill"), value: "FILL" },
					{ text: qsTr("Top"), value: "TOP" },
					{ text: qsTr("Center"), value: "CENTER" },
					{ text: qsTr("Bottom"), value: "BOTTOM" }
				]
				currentValue: ["FILL", "TOP", "CENTER", "BOTTOM"][viewDialog.viewActions.verticalAlign]
				onActivated: value => viewDialog.viewActions.setConfig("GridVerticalAlign", value)
			}
		}

		// ── Navigation ───────────────────────────────────────────────────
		SectionHeading {
			text: qsTr("Navigation")
		}
		ToggleRow {
			text: qsTr("Center Focus")
			checked: viewDialog.viewActions.centerFocus
			onToggled: checked => viewDialog.viewActions.setNavigationConfig("CenterFocus", String(checked))
		}
		ToggleRow {
			text: qsTr("Smooth Scrolling")
			checked: viewDialog.viewActions.smoothScrolling
			onToggled: checked => viewDialog.viewActions.setNavigationConfig("SmoothScrolling", String(checked))
		}
		ToggleRow {
			text: qsTr("Open on Click")
			checked: viewDialog.viewActions.openOnClick
			onToggled: checked => viewDialog.viewActions.setNavigationConfig("OpenOnClick", String(checked))
		}
		ToggleRow {
			text: qsTr("Focus Empty Slots")
			rowEnabled: viewDialog.viewActions.freePlacement
			checked: viewDialog.viewActions.focusEmptySlots
			onToggled: checked => viewDialog.viewActions.setNavigationConfig("FocusEmptySlots", String(checked))
		}

		// ── Wallpaper ────────────────────────────────────────────────────
		SectionHeading {
			text: qsTr("Wallpaper")
		}
		RowLayout {
			Layout.fillWidth: true
			spacing: Kirigami.Units.smallSpacing

			Button {
				Layout.fillWidth: true
				Layout.minimumHeight: Kirigami.Units.gridUnit * 2.4
				text: qsTr("Set Wallpaper...")
				icon.name: "document-open"
				onPressed: viewDialog.playSound("button-pressed")
				onReleased: viewDialog.playSound("button-released")
				onClicked: wallpaperDialog.open()
			}
			Button {
				Layout.fillWidth: true
				Layout.minimumHeight: Kirigami.Units.gridUnit * 2.4
				text: qsTr("Clear")
				icon.name: "edit-clear"
				enabled: viewDialog.viewActions.wallpaper.trim() !== ""
				onPressed: viewDialog.playSound("button-pressed")
				onReleased: viewDialog.playSound("button-released")
				onClicked: viewDialog.viewActions.setConfig("Wallpaper", "")
			}
		}

		// ── Stash ────────────────────────────────────────────────────────
		SectionHeading {
			text: qsTr("Stash")
		}
		ToggleRow {
			text: qsTr("Show Stash")
			checked: viewDialog.viewActions.stashShown
			onToggled: checked => viewDialog.viewActions.setConfig("StashShown", String(checked))
		}
		ToggleRow {
			text: qsTr("Stash Dotfiles")
			checked: viewDialog.viewActions.stashDotfiles
			onToggled: checked => viewDialog.viewActions.setConfig("StashDotFiles", String(checked))
		}

		FileDialog {
			id: wallpaperDialog
			title: qsTr("Choose Wallpaper")
			nameFilters: [qsTr("Images (*.png *.jpg *.jpeg *.webp *.avif *.bmp *.gif *.svg)"), qsTr("All files (*)")]
			onAccepted: viewDialog.viewActions.setConfig("Wallpaper", viewDialog.viewActions.pathFromUrl(wallpaperDialog.selectedFile))
		}
	}
}
