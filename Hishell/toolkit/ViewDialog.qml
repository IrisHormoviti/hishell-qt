pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami

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
	// The sheet owns the keyboard while it is up. Without this the folder view
	// keeps it, so the controller's cancel is handled by the view behind the
	// sheet (B could not close it) and accept is never sent to the sheet.
	focus: true
	onOpened: {
		const w = viewDialog.viewActions.window;
		if (w)
			w.sheetOpen = true;
	}
	onClosed: {
		playSound("return");
		// Qt leaves the focus on the control that was tapped inside the sheet,
		// which is hidden now. Hand the keyboard back once the popup has
		// settled: A/B pressed right after closing must reach the file list,
		// not the hidden control.
		const w = viewDialog.viewActions.window;
		if (w)
			w.sheetOpen = false;
		Qt.callLater(function () {
			const view = w ? (w.focusedFolderView || w.primaryFolderView) : null;
			if (view)
				view.forceActiveFocus();
		});
	}

	// Some popup paths deliver cancel as the FocusManager signal rather than as
	// a key (the folder view still considers itself the keyboard owner), so the
	// sheet closes on either path.
	Connections {
		target: viewDialog.viewActions.window ? viewDialog.viewActions.window.focusManager : null
		function onCancel_requested() {
			if (viewDialog.visible)
				viewDialog.close();
		}
	}

	implicitWidth: Kirigami.Units.gridUnit * 20
	// OverlaySheet caps its height at the window and scrolls the content; the
	// explicit maximum keeps the last groups reachable on the short touch panel.
	closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

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

	// One configurable list column: the switch shows or hides it, the arrows
	// move it left/right in the row. Mirrors the View menu's List Columns
	// submenu, which is the only surface on targets without a menu bar.
	component ListColumnRow: RowLayout {
		id: columnRow
		property string columnKey
		readonly property bool shown: viewDialog.viewActions.hasListColumn(columnRow.columnKey)
		Layout.fillWidth: true
		spacing: Kirigami.Units.smallSpacing

		Label {
			Layout.fillWidth: true
			text: viewDialog.viewActions.listColumnLabel(columnRow.columnKey)
		}
		ToolButton {
			icon.name: "go-up"
			display: AbstractButton.IconOnly
			enabled: viewDialog.viewActions.canMoveListColumn(columnRow.columnKey, -1)
			onClicked: viewDialog.viewActions.moveListColumn(columnRow.columnKey, -1)
		}
		ToolButton {
			icon.name: "go-down"
			display: AbstractButton.IconOnly
			enabled: viewDialog.viewActions.canMoveListColumn(columnRow.columnKey, 1)
			onClicked: viewDialog.viewActions.moveListColumn(columnRow.columnKey, 1)
		}
		Switch {
			id: columnSwitch
			onToggled: {
				viewDialog.viewActions.setListColumnVisible(columnRow.columnKey, checked);
				viewDialog.playSound(checked ? "button-toggle-on" : "button-toggle-off");
			}
			Binding {
				target: columnSwitch
				property: "checked"
				value: columnRow.shown
				restoreMode: Binding.RestoreNone
			}
		}
	}

	ColumnLayout {
		// The dialog sizes itself to this content and scrolls it when it is
		// taller than the panel; width comes from the dialog's preferredWidth.
		spacing: Kirigami.Units.largeSpacing

		// ── Scope ────────────────────────────────────────────────────────
		SectionHeading {
			text: qsTr("Apply To")
		}
		SegmentedButtons {
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
		SegmentedButtons {
			options: [
				{ text: qsTr("Grid"), icon: "view-grid", value: "GRID" },
				{ text: qsTr("List"), icon: "view-list-details", value: "LIST" }
			]
			currentValue: viewDialog.viewActions.viewMode === 0 ? "GRID" : "LIST"
			onActivated: value => viewDialog.viewActions.setViewModeSilent(value)
		}
		RowLayout {
			Layout.fillWidth: true
			visible: !viewDialog.viewActions.isListView
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
			visible: !viewDialog.viewActions.isListView
			text: qsTr("Labels")
		}
		ToggleRow {
			visible: !viewDialog.viewActions.isListView
			text: qsTr("Show Labels")
			checked: viewDialog.viewActions.showLabels
			onToggled: checked => viewDialog.viewActions.setConfig("ShowLabels", String(checked))
		}
		ToggleRow {
			visible: !viewDialog.viewActions.isListView
			text: qsTr("Labels Beside Icons")
			enabled: viewDialog.viewActions.showLabels
			checked: viewDialog.viewActions.labelsBesideIcons
			onToggled: checked => viewDialog.viewActions.setConfig("GridLabelsBesidesIcons", String(checked))
		}
		SegmentedButtons {
			visible: !viewDialog.viewActions.isListView
			enabled: viewDialog.viewActions.showLabels
			options: [
				{ text: qsTr("Titles"), value: "TITLE" },
				{ text: qsTr("File Names"), value: "FILENAME" }
			]
			currentValue: viewDialog.viewActions.labelText === 0 ? "TITLE" : "FILENAME"
			onActivated: value => viewDialog.viewActions.setConfig("LabelText", value)
		}

		// ── List columns ─────────────────────────────────────────────────
		SectionHeading {
			visible: viewDialog.viewActions.isListView
			text: qsTr("List Columns")
		}
		ToggleRow {
			visible: viewDialog.viewActions.isListView
			text: qsTr("Show Header")
			checked: viewDialog.viewActions.showListHeader
			onToggled: checked => viewDialog.viewActions.setListHeaderVisible(checked)
		}
		ListColumnRow {
			visible: viewDialog.viewActions.isListView
			columnKey: "TITLE"
		}
		ListColumnRow {
			visible: viewDialog.viewActions.isListView
			columnKey: "FILENAME"
		}
		ListColumnRow {
			visible: viewDialog.viewActions.isListView
			columnKey: "SIZE"
		}
		ListColumnRow {
			visible: viewDialog.viewActions.isListView
			columnKey: "MODIFIED"
		}
		ListColumnRow {
			visible: viewDialog.viewActions.isListView
			columnKey: "CREATED"
		}
		ListColumnRow {
			visible: viewDialog.viewActions.isListView
			columnKey: "ACCESSED"
		}
		ListColumnRow {
			visible: viewDialog.viewActions.isListView
			columnKey: "TYPE"
		}

		// ── Sorting ──────────────────────────────────────────────────────
		SectionHeading {
			text: qsTr("Sort By")
		}
		SegmentedButtons {
			options: {
				const list = [
					{ text: qsTr("Newest"), value: "NEWEST" },
					{ text: qsTr("Oldest"), value: "OLDEST" },
					{ text: qsTr("Name"), value: "ALPHABETICAL" }
				];
				// Free placement only makes sense for a folder's own config,
				// and only in grid view where cells can be positioned.
				if (viewDialog.viewActions.isLocal && !viewDialog.viewActions.isListView)
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
			SegmentedButtons {
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
			SegmentedButtons {
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
			visible: viewDialog.viewActions.hasFreePlacementPositions && !viewDialog.viewActions.isListView
			text: qsTr("Reset Manual Placement")
			icon.name: "edit-reset"
			onPressed: viewDialog.playSound("button-pressed")
			onReleased: viewDialog.playSound("button-released")
			onClicked: viewDialog.viewActions.resetFreePlacement()
		}

		// ── Arrangement ──────────────────────────────────────────────────
		SectionHeading {
			visible: !viewDialog.viewActions.isListView
			text: qsTr("Arrange")
		}
		RowLayout {
			Layout.fillWidth: true
			visible: !viewDialog.viewActions.isListView
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
			visible: !viewDialog.viewActions.isListView
			spacing: Kirigami.Units.smallSpacing
			Label {
				text: qsTr("Scroll")
			}
			SegmentedButtons {
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
			visible: !viewDialog.viewActions.isListView
			spacing: Kirigami.Units.smallSpacing
			Label {
				text: qsTr("Align X")
			}
			SegmentedButtons {
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
			visible: !viewDialog.viewActions.isListView
			spacing: Kirigami.Units.smallSpacing
			Label {
				text: qsTr("Align Y")
			}
			SegmentedButtons {
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
