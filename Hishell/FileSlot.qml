pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ClamOS.Theme
import Hishell

Item {
	id: fileSlot

	required property string path

	// Untyped to avoid the ShellWindow <-> FileSlot cyclic dependency; see
	// ActionManager.qml for the explanation.
	property var window: Window.window
	property alias contentLayout: contentLayout

	property DragDropHandler dragDropHandler: window ? window.dragDropHandler : null
	property ActionManager actionManager: window ? window.actionManager : null
	property FileManager fileManager: window ? window.fileManager : null

	required property string icon
	required property string title
	property int gridSize: 64
	property bool labelBesideIcon: gridSize < 32
	property bool showLabels: true
	// Folders (and the home icon) are recoloured to the accent by the shell
	// (Breeze draws their bodies with its ColorScheme-Accent class); anything
	// else keeps the icon its resolver chose, and an icon that cannot be
	// recoloured falls back to its plain name.
	readonly property string displayIcon: {
		if (!fileSlot.is_dir)
			return fileSlot.icon;
		const recoloured = ClamTheme.accentFolderIcon(fileManager, fileSlot.icon, fileSlot.iconDisplaySize);
		return recoloured.length > 0 ? recoloured : fileSlot.icon;
	}
	// With no label the icon takes over the whole slot, so the view reads as a gallery.
	readonly property real iconDisplaySize: fileSlot.showLabels ? fileSlot.gridSize : Math.max(fileSlot.gridSize, Math.min(fileSlot.width, fileSlot.height) - Kirigami.Units.smallSpacing * 2)
	// Whether the label shows the file name instead of the item's title.
	property bool labelShowsFilename: false
	property bool fixedWidth: true
	property bool showIcon: icon !== ""
	required property bool is_symlink
	required property int index
	// The delegate model does not hand the `is_dir` role to a same-named
	// property, so derive it from the path. Views that know better (the path
	// bar) can still override it.
	property bool is_dir: fileManager ? fileManager.is_directory(String(fileSlot.path)) : false

	// A `Type=Button` entry is a control, not a thing to open (docs §2 of
	// docs/settings-as-folders.md): it acts where it stands. Drawing it like the
	// files and folders around it made the two read the same, so it is drawn as
	// a button instead — a filled, rounded plate behind the icon and label,
	// which is the shape every other control on the device already has.
	readonly property bool isButton: fileManager ? fileManager.is_button(String(fileSlot.path)) : false

	// Some slots represent the same path family without being a choice in the
	// parent folder's radio group (path-bar breadcrumbs); they opt out here.
	property bool radioMember: true

	// A child of a folder-owned `[Radio]` group (docs/theming.md): the parent
	// folder decides whether this item is selectable and owns the selection; the
	// child carries only display metadata.  `radio_only` narrows the group to
	// directories or files.
	readonly property bool isRadio: {
		if (!fileSlot.radioMember)
			return false;
		const view = fileSlot.folderView;
		if (!view || !view.directory || !view.directory.config || !view.directory.config.radio_enabled)
			return false;
		const only = view.directory.config.radio_only;
		return only === 0 || (only === 1 && fileSlot.is_dir) || (only === 2 && !fileSlot.is_dir);
	}
	readonly property string radioValue: {
		if (!fileSlot.isRadio || !fileSlot.folderView || !fileSlot.folderView.directory)
			return "";
		return String(fileSlot.folderView.directory.radio_value(fileSlot.path));
	}
	readonly property bool isRadioSelected: {
		const view = fileSlot.folderView;
		if (!fileSlot.isRadio || !view || !view.directory || !view.directory.config)
			return false;
		return String(view.directory.config.radio_selected) === fileSlot.radioValue;
	}

	// The selected radio choice is the folder's current item, so give it the
	// same active treatment (bold label, selection wash) as an active item.
	readonly property bool active: fileSlot.isActive || fileSlot.isRadioSelected

	// The FolderView that owns this slot; used to detect free-placement mode,
	// where the background DropArea owns all drops (including folder targets).
	readonly property var folderView: {
		let p = fileSlot.parent;
		while (p) {
			if (typeof p.isFreeRepositionDrop === 'function')
				return p;
			p = p.parent;
		}
		return null;
	}
	readonly property bool freePlacement: folderView && folderView.config ? (folderView.config.sort === 3 && folderView.config.view_mode === 0) : false

	// Whether a plain click opens the item. When off, the first click only
	// focuses it and a click on the (now focused) item opens it. See ViewActions.
	readonly property bool openOnClick: fileSlot.folderView && fileSlot.folderView.config ? fileSlot.folderView.config.open_on_click : true

	property int animationDuration: 200
	property int animationEase: Easing.OutCubic

	// Selection state passed from FolderView
	property bool selectionActive: false
	property bool isSelected: false

	// Used for when this item is open in another view
	property bool isActive: false

	// Owner hooks for plain left clicks, used by the path bar to open the current
	// folder's menu instead of reopening it: `pressHandler` is called on press
	// and `clickHandler` replaces the default activation on click.
	property var pressHandler: null
	property var clickHandler: null

	// Focus state passed from FolderView (independent of selection). The border
	// itself is drawn by the grid as one shared item (FocusBorder.qml), not per
	// slot; only `isFocused` is needed here, for the click-to-open rule below.
	property bool isFocused: false

	// The last item this slot opened and when. One gesture produces several
	// activation signals - a quick second tap is a double click to Qt, which
	// sends both `canceled` and `doubleClicked`, and a mouse double click sends
	// `doubleClicked` and then `clicked` - so they must collapse into one open.
	property string lastActivatedPath: ""
	property double lastActivatedTime: 0

	property int currentDragCount: 1

	// Event sounds (ClamOS XDG sound theme). Played through the window's sound
	// object; a null window (or a missing theme) simply stays silent.
	function playSound(name) {
		const w = fileSlot.Window.window;
		if (w && w.sound)
			w.sound.play(name);
	}

	// True while this slot's payload is the active native drag. Set by the drag
	// handlers (the drag source itself is the window's persistent item, so this
	// cannot be read from a Drag object here). Kept a plain property so the
	// cleanup below cannot form a binding loop with the drag handler's state.
	property bool isDraggingThisSlot: false
	onIsDraggingThisSlotChanged: {
		if (!isDraggingThisSlot && mouseArea.dragStarted) {
			mouseArea.dragStarted = false;
			mouseArea.dragInitiated = false;
			if (typeof fileSlot.dragDropHandler !== 'undefined' && fileSlot.dragDropHandler) {
				fileSlot.dragDropHandler.active_dragged_paths = [];
				fileSlot.dragDropHandler.tooltip_active = false;
				fileSlot.dragDropHandler.end_drag();
			}
		}
	}

	// A native drag is ended by the platform, so this slot's MouseArea never
	// sees the release. The window clears internalDragInProcess when the drag
	// finishes; drop the dragging state here so the slot is not left dimmed.
	Connections {
		target: fileSlot.window
		function onInternalDragInProcessChanged() {
			if (!fileSlot.isDraggingThisSlot)
				return;
			if (target && target.internalDragInProcess)
				return;
			mouseArea.dragStarted = false;
			fileSlot.isDraggingThisSlot = false;
		}
	}

	// Emitted when toggling this item's selection
	signal selectionToggled(string path, int idx)

	// Emitted for range selection
	signal shiftSelected(int idx)

	// Emitted on press and hold
	signal pressHeld(string path, int idx)

	// Emitted before the attached context menu opens.
	signal contextMenuRequested(string path, int idx)

	// The context menu for this item. This used to be an attached object named
	// "ContextMenu", which was never defined; Qt 6.8 rejects it with
	// "Non-existent attached object" and marks FileSlot unavailable, which in
	// turn breaks FolderView and PathBar.
	//
	// Built lazily: a folder can hold hundreds of slots, and each context menu
	// instantiates a ViewMenu plus every action group — thousands of QMenu
	// items whose themed icons Qt would resolve eagerly, which dominated
	// startup and made focusing items feel slow on the device. The menu is only
	// needed when one is actually opened.
	Loader {
		id: contextMenuLoader
		active: false
		sourceComponent: contextMenuComponent
	}

	Component {
		id: contextMenuComponent
		ShellContextMenu {
			actionManager: fileSlot.actionManager
			targetIsDir: fileSlot.is_dir
			targetIsImage: fileSlot.fileManager && fileSlot.fileManager.is_image_file(fileSlot.path)
		}
	}

	readonly property ShellContextMenu contextMenu: contextMenuLoader.item

	function openContextMenu() {
		if (fileSlot.actionManager)
			fileSlot.actionManager.pasteTargetPath = fileSlot.is_dir ? fileSlot.path : "";
		fileSlot.contextMenuRequested(fileSlot.path, fileSlot.index);

		contextMenuLoader.active = true;
		const menu = contextMenuLoader.item;
		if (!menu)
			return null;
		menu.parent = fileSlot;
		const position = fileSlot.mapToItem(menu.parent, 0, fileSlot.height);
		menu.x = position.x;
		menu.y = position.y;
		menu.open();
		return menu;
	}

	implicitWidth: contentLayout.implicitWidth + (fileSlot.labelBesideIcon && fileSlot.showIcon && fileSlot.showLabels ? Kirigami.Units.largeSpacing * 2 : Kirigami.Units.smallSpacing * 2)
	implicitHeight: contentLayout.implicitHeight + Kirigami.Units.smallSpacing * 2
	// The on-disk name, used by the FILENAME label mode and the tooltip.
	readonly property string fileName: {
		const path = fileSlot.path;
		const slash = path.lastIndexOf("/");
		const name = slash >= 0 ? path.substring(slash + 1) : path;
		return name !== "" ? name : path;
	}

	// The text the label shows; the other one is offered as a tooltip.
	readonly property string labelText: fileSlot.labelShowsFilename || fileSlot.title === "" ? fileSlot.fileName : fileSlot.title
	readonly property string tooltipText: {
		const alternate = fileSlot.labelShowsFilename ? fileSlot.title : fileSlot.fileName;
		if (!fileSlot.showLabels)
			return alternate !== "" && alternate !== fileSlot.labelText ? fileSlot.labelText + "\n" + alternate : fileSlot.labelText;
		if (fileSlot.title === "" || fileSlot.title === fileSlot.fileName)
			return "";
		return alternate;
	}

	// Dotfiles (hidden entries) are always dimmed so they read as secondary.
	readonly property bool isDotfile: fileSlot.fileName.startsWith(".")
	opacity: {
		if (fileSlot.dragDropHandler && fileSlot.dragDropHandler.active_dragged_paths && fileSlot.dragDropHandler.active_dragged_paths.indexOf(fileSlot.path) !== -1)
			return 0.2;
		return fileSlot.isDotfile ? 0.5 : 1.0;
	}
	scale: mouseArea.pressed ? 0.9 : (mouseArea.containsMouse ? 1.05 : 1.0)

	Behavior on opacity {
		NumberAnimation {
			duration: fileSlot.animationDuration
			easing.type: fileSlot.animationEase
		}
	}

	Behavior on scale {
		NumberAnimation {
			duration: fileSlot.animationDuration
			easing.type: fileSlot.animationEase
		}
	}

	// Free-placement repositioning animates the slot change; other layout
	// changes (resize, scroll) keep snapping as before.
	Behavior on x {
		enabled: fileSlot.folderView ? fileSlot.folderView.repositionAnimating : false
		NumberAnimation {
			duration: fileSlot.animationDuration
			easing.type: fileSlot.animationEase
		}
	}

	Behavior on y {
		enabled: fileSlot.folderView ? fileSlot.folderView.repositionAnimating : false
		NumberAnimation {
			duration: fileSlot.animationDuration
			easing.type: fileSlot.animationEase
		}
	}

	// ── Button plate ──
	// Only for `Type=Button` entries. The same footprint as the selection box:
	// the whole slot, inset by smallSpacing, so a button, a selected item and a
	// focused one all cover the same area. Every button being the same size
	// comes free. The surface is a raised key: a shaded rim with a lighter face
	// set into it, a top highlight, a bottom shade and a soft blurred drop
	// shadow; pressing sinks the face into the shadow.
	Item {
		id: buttonPlate
		visible: fileSlot.isButton
		anchors.fill: parent
		anchors.margins: Kirigami.Units.smallSpacing

		readonly property bool down: mouseArea.pressed
		readonly property bool hot: mouseArea.containsMouse
		readonly property real plateRadius: Kirigami.Units.cornerRadius * 1.5
		readonly property color body: down ? Qt.lighter(Kirigami.Theme.highlightColor, 1.25)
			: (hot ? Qt.lighter(Kirigami.Theme.backgroundColor, 1.10) : Kirigami.Theme.backgroundColor)

		// Soft drop shadow, stacked translucent rounded rectangles (renders on
		// every backend); each layer is the rim pushed down by `d` and grown
		// by `s`.
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
				color: ClamTheme.shadowColor
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
				GradientStop { position: 1.0; color: buttonPlate.down ? Qt.darker(buttonPlate.body, 1.12) : Qt.darker(buttonPlate.body, 1.16) }
			}
			border.width: 1
			border.color: buttonPlate.down || buttonPlate.hot ? Kirigami.Theme.highlightColor : Qt.alpha(Kirigami.Theme.disabledTextColor, 0.7)
		}
		Rectangle {
			id: buttonFace
			anchors.fill: buttonRim
			anchors.margins: 2
			radius: Math.max(2, buttonPlate.plateRadius - 2)
			gradient: Gradient {
				GradientStop { position: 0.0; color: buttonPlate.down ? Qt.darker(buttonPlate.body, 1.05) : Qt.lighter(buttonPlate.body, 1.08) }
				GradientStop { position: 0.10; color: buttonPlate.body }
				GradientStop { position: 0.72; color: buttonPlate.body }
				GradientStop { position: 0.92; color: buttonPlate.down ? Qt.darker(buttonPlate.body, 1.06) : Qt.darker(buttonPlate.body, 1.03) }
				GradientStop { position: 1.0; color: buttonPlate.down ? Qt.darker(buttonPlate.body, 1.10) : Qt.darker(buttonPlate.body, 1.07) }
			}
		}
	}

	// ── Radio plate ──
	// A child of a folder-owned radio group is a choice, not an app: a card
	// behind it, and an accent border plus wash when it is the selected one.
	// The parent folder owns the group and runs the apply command.
	Rectangle {
		id: radioPlate
		visible: fileSlot.isRadio
		anchors.fill: parent
		anchors.margins: Kirigami.Units.smallSpacing
		radius: Kirigami.Units.cornerRadius * 1.5
		color: mouseArea.pressed ? Qt.alpha(Kirigami.Theme.highlightColor, 0.25)
			: (mouseArea.containsMouse ? Qt.lighter(Kirigami.Theme.backgroundColor, 1.15) : Kirigami.Theme.backgroundColor)
		border.width: 1
		border.color: fileSlot.isRadioSelected ? Kirigami.Theme.highlightColor : Kirigami.Theme.disabledTextColor
		opacity: fileSlot.isRadioSelected ? 1.0 : 0.75

		// The selected choice gets an accent wash, so it reads as the current
		// item even where the plate hides the selection rectangle behind it.
		Rectangle {
			anchors.fill: parent
			radius: parent.radius
			color: Kirigami.Theme.highlightColor
			opacity: fileSlot.isRadioSelected ? 0.12 : 0.0
			Behavior on opacity { NumberAnimation { duration: fileSlot.animationDuration } }
		}

		Behavior on border.color {
			ColorAnimation { duration: fileSlot.animationDuration }
		}
		Behavior on opacity {
			NumberAnimation { duration: fileSlot.animationDuration; easing.type: fileSlot.animationEase }
		}
	}

	// ── Layout ──

	GridLayout {
		id: contentLayout
		anchors.verticalCenter: parent.verticalCenter
		x: (fileSlot.labelBesideIcon && fileSlot.showIcon && fileSlot.showLabels) ? Kirigami.Units.largeSpacing : (parent.width - width) / 2
		columns: (fileSlot.labelBesideIcon && fileSlot.showIcon && fileSlot.showLabels) ? 2 : 1

		Item {
			visible: fileSlot.showIcon
			Layout.alignment: (fileSlot.labelBesideIcon && fileSlot.showIcon) ? Qt.AlignVCenter : Qt.AlignHCenter
			Layout.preferredWidth: fileSlot.iconDisplaySize
			Layout.preferredHeight: fileSlot.iconDisplaySize

			Loader {
				anchors.fill: parent
				active: fileSlot.showIcon
				sourceComponent: (fileSlot.displayIcon.startsWith("file://") || fileSlot.displayIcon.startsWith("/")) ? thumbnailComponent : iconComponent
			}

			Component {
				id: thumbnailComponent
				Image {
					source: fileSlot.displayIcon
					asynchronous: true
					cache: false
					fillMode: Image.PreserveAspectFit
					smooth: true
					anchors.fill: parent
					clip: true
					anchors.centerIn: parent
				}
			}

			Component {
				id: iconComponent
				Kirigami.Icon {
					source: fileSlot.displayIcon
					Layout.preferredWidth: fileSlot.gridSize
					Layout.preferredHeight: fileSlot.gridSize
					Layout.fillWidth: false
					Layout.fillHeight: false
				}
			}
		}

		Label {
			id: labelItem
			visible: fileSlot.showLabels
			Layout.alignment: fileSlot.labelBesideIcon ? Qt.AlignVCenter : Qt.AlignHCenter

			text: {
				let t = fileSlot.labelText;

				let styled = t;
				const idx = t.lastIndexOf('.');
				if (idx > 0 && !(t.startsWith('.') && t.indexOf('.', 1) === -1)) {
					const name = t.substring(0, idx);
					const ext = t.substring(idx);
					styled = name + '<font color="' + Kirigami.Theme.disabledTextColor + '">' + ext + '</font>';
				}
				return t;
			}
			textFormat: Text.StyledText
			color: Kirigami.Theme.textColor
			wrapMode: Text.Wrap
			maximumLineCount: 2

			// Pin the font metrics so the italic face used for symlinks keeps
			// the same size as the surrounding text.  Left to inherit, asking
			// for italic can resolve to a fallback with a different point size
			// (the "both point size and pixel size set" warning) and the
			// symlink label renders smaller.
			// Qt resolves the italic face of the default font at a smaller
			// metric than the upright one on this device (the app font has both
			// a point and a pixel size).  Measure both at the base size and
			// scale the italic request up so the symlink label is the same
			// height as the regular one.
			readonly property real labelBasePixelSize: Qt.application.font.pixelSize

			FontMetrics {
				id: baseRegularFontMetrics
				font: Qt.font({
					family: Qt.application.font.family,
					pixelSize: labelItem.labelBasePixelSize,
					italic: false
				})
			}
			FontMetrics {
				id: baseItalicFontMetrics
				font: Qt.font({
					family: Qt.application.font.family,
					pixelSize: labelItem.labelBasePixelSize,
					italic: true
				})
			}
			readonly property real labelItalicScale: baseItalicFontMetrics.height > 0
				? baseRegularFontMetrics.height / baseItalicFontMetrics.height
				: 1.0

			font: Qt.font({
				family: Qt.application.font.family,
				pixelSize: fileSlot.is_symlink
					? Math.round(labelItem.labelBasePixelSize * labelItem.labelItalicScale)
					: labelItem.labelBasePixelSize,
				weight: Qt.application.font.weight,
				italic: fileSlot.is_symlink,
				bold: fileSlot.active
			})

			elide: fileSlot.labelBesideIcon ? Text.ElideMiddle : Text.ElideMiddle
			// A button's label is bounded by its plate; an ordinary item's by
			// the grid cell it lives in.
			Layout.maximumWidth: fileSlot.isButton
				? buttonPlate.width - Kirigami.Units.largeSpacing * 2
				: (fileSlot.isRadio
					? radioPlate.width - Kirigami.Units.largeSpacing * 2
					: (fileSlot.labelBesideIcon ? (fileSlot.fixedWidth ? fileSlot.width - fileSlot.gridSize - Kirigami.Units.gridUnit * 2 : 250) : fileSlot.gridSize + Kirigami.Units.gridUnit * 2))
			horizontalAlignment: fileSlot.labelBesideIcon ? Text.AlignLeft : Text.AlignHCenter
		}
	}

	// ── Suspended-app mark ──
	// A small accent dot under an item whose app is currently suspended, with a
	// gentle blink so it reads as "still running". `active_revision` is read only
	// to re-evaluate the binding when the set of suspended apps changes.
	Rectangle {
		id: activeDot
		width: Kirigami.Units.smallSpacing * 2
		height: width
		radius: width / 2
		color: Kirigami.Theme.highlightColor
		anchors.horizontalCenter: contentLayout.horizontalCenter
		anchors.top: contentLayout.bottom
		anchors.topMargin: Kirigami.Units.smallSpacing
		visible: {
			const fm = fileSlot.folderView ? fileSlot.folderView.focusManager : null;
			if (!fm)
				return false;
			fm.active_revision; // dependency: re-check when the set changes
			return fm.is_item_active(fileSlot.path);
		}

		SequentialAnimation on opacity {
			running: activeDot.visible
			loops: Animation.Infinite
			NumberAnimation { to: 0.2; duration: 700; easing.type: Easing.InOutQuad }
			NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutQuad }
		}
	}

	// ── Selection ──

	Rectangle {
		z: -1
		anchors.fill: parent
		anchors.margins: isSelected ? Kirigami.Units.smallSpacing : 0
		radius: Kirigami.Units.cornerRadius
		color: Kirigami.Theme.highlightColor
		opacity: (fileSlot.isSelected ? 0.25 : 0.0) || (fileSlot.active ? 0.5 : 0.0)
		Behavior on opacity {
			NumberAnimation {
				duration: fileSlot.animationDuration
				easing.type: fileSlot.animationEase
			}
		}
	}

	Rectangle {
		anchors.fill: parent
		anchors.margins: Kirigami.Units.smallSpacing
		radius: Kirigami.Units.cornerRadius
		color: "transparent"
		border.color: Kirigami.Theme.highlightColor
		border.width: 2
		opacity: fileSlot.isSelected ? 1.0 : 0.0
		Behavior on opacity {
			NumberAnimation {
				duration: fileSlot.animationDuration
				easing.type: fileSlot.animationEase
			}
		}
	}

	// ── Focus ──
	// The focus border is not drawn here: the grid owns one shared border that
	// follows the cursor (FocusBorder.qml). Drawing it per slot meant loading
	// four SVG documents for every item in the folder.

	Rectangle {
		Kirigami.Theme.colorSet: Kirigami.Theme.Selection
		Kirigami.Theme.inherit: false

		anchors.top: parent.top
		anchors.right: parent.right
		anchors.margins: Kirigami.Units.mediumSpacing
		width: Kirigami.Units.iconSizes.small
		height: Kirigami.Units.iconSizes.small
		radius: Kirigami.Units.cornerRadius
		border.width: 2
		border.color: Kirigami.Theme.backgroundColor
		color: fileSlot.isSelected ? Kirigami.Theme.backgroundColor : "transparent"
		opacity: fileSlot.isSelected ? 1.0 : 0.4
		visible: fileSlot.selectionActive
		Behavior on color {
			ColorAnimation {
				duration: fileSlot.animationDuration
				easing.type: fileSlot.animationEase
			}
		}

		Kirigami.Icon {
			anchors.fill: parent
			anchors.margins: 2
			source: "emblem-ok-symbolic"
			opacity: fileSlot.isSelected ? 1.0 : 0

			Behavior on opacity {
				NumberAnimation {
					duration: fileSlot.animationDuration
					easing.type: fileSlot.animationEase
				}
			}
		}
	}

	// ── Drop Target ───

	Rectangle {
		anchors.fill: parent
		anchors.margins: 2
		radius: Kirigami.Units.cornerRadius
		color: Kirigami.Theme.focusColor
		opacity: slotDropArea.isHovered ? 0.35 : 0.0
		border.color: Kirigami.Theme.highlightColor
		border.width: 2
		Behavior on opacity {
			NumberAnimation {
				duration: fileSlot.animationDuration
				easing.type: fileSlot.animationEase
			}
		}
	}

	DropArea {
		id: slotDropArea
		anchors.fill: parent
		enabled: fileSlot.is_dir && !fileSlot.freePlacement
		keys: ["text/uri-list", "text/plain"]

		property bool isHovered: false
		property DragDropHandler dragDropHandler: fileSlot.dragDropHandler ? fileSlot.dragDropHandler : null

		function checkValid(drag) {
			let sourcePaths = [];
			if (typeof dragDropHandler !== 'undefined' && dragDropHandler.drag_source_paths && dragDropHandler.drag_source_paths.length > 0) {
				sourcePaths = dragDropHandler.drag_source_paths;
			} else if (drag.source) {
				sourcePaths = drag.source.dragSourcePaths || (drag.source.mainPath ? [drag.source.mainPath] : []);
			} else if (drag.hasUrls) {
				sourcePaths = drag.urls;
			}

			let fView = null;
			let p = fileSlot.parent;
			while (p) {
				if (typeof p.isDropValid === 'function') {
					fView = p;
					break;
				}
				p = p.parent;
			}

			if (fView && !fView.isDropValid(fileSlot.path, sourcePaths)) {
				slotDropArea.isHovered = false;
				if (typeof dragDropHandler !== 'undefined')
					dragDropHandler.tooltip_active = false;
				drag.accepted = false;
				hoverNavTimer.stop();
				return false;
			}

			slotDropArea.isHovered = true;
			if (typeof dragDropHandler !== 'undefined') {
				dragDropHandler.tooltip_active = true;
			}
			drag.accept();
			return true;
		}

		onEntered: drag => {
			if (checkValid(drag)) {
				hoverNavTimer.restart();
			}
		}

		onPositionChanged: drag => {
			// Keep the spring-load timer alive while the folder stays hovered;
			// `onEntered` may not have fired if the drag started already inside.
			if (checkValid(drag) && !hoverNavTimer.running)
				hoverNavTimer.restart();
			// Track the cursor here too: the background drop area does not get
			// the moves while the drag is over an item, and the drag ghost and
			// tooltip follow this position.
			if (typeof dragDropHandler !== 'undefined' && dragDropHandler) {
				const pt = slotDropArea.mapToItem(null, drag.x, drag.y);
				dragDropHandler.update_cursor(pt.x, pt.y);
			}
		}

		onExited: {
			slotDropArea.isHovered = false;
			hoverNavTimer.stop();
			if (typeof dragDropHandler !== 'undefined')
				dragDropHandler.tooltip_active = false;
		}

		onDropped: drop => {
			slotDropArea.isHovered = false;
			hoverNavTimer.stop();
			if (typeof dragDropHandler !== 'undefined')
				dragDropHandler.tooltip_active = false;

			let uris = "";
			if (typeof dragDropHandler !== 'undefined' && dragDropHandler.drag_uris && dragDropHandler.drag_uris.length > 0) {
				uris = dragDropHandler.drag_uris.join("\n");
			} else if (drop.source && drop.source.dragUris) {
				uris = drop.source.dragUris.join("\n");
			} else if (drop.hasUrls) {
				uris = drop.urls.join("\n");
			} else if (drop.hasText) {
				uris = drop.text;
			}

			if (uris.length > 0 && typeof fileManager !== 'undefined' && fileManager) {
				const action = (typeof dragDropHandler !== 'undefined' && dragDropHandler.drag_action) ? dragDropHandler.drag_action : "move";
				if (fileManager.process_uris_action(fileSlot.path, uris, action)) {
					fileSlot.playSound("drag-accept");
					let p = fileSlot.parent;
					while (p) {
						if (p.directory) {
							const win = fileSlot.window;
							if (win && typeof win.requestDirectoryReload === 'function')
								win.requestDirectoryReload(p.directory);
							else
								p.directory.reload();
							break;
						}
						p = p.parent;
					}
				} else {
					fileSlot.playSound("drag-fail");
				}
				drop.accept();
			}
		}
	}

	Timer {
		id: hoverNavTimer
		interval: 600
		repeat: false
		onTriggered: {
			if (slotDropArea.isHovered && fileSlot.is_dir) {
				const targetPath = fileSlot.path;
				if (typeof fileSlot.dragDropHandler !== 'undefined')
					fileSlot.dragDropHandler.tooltip_active = false;
				Qt.callLater(function () {
					// Open it in the view that owns this slot, rather than
					// whichever pane happens to hold the cursor.
					const fView = fileSlot.folderView;
					const dir = fView ? fView.directory : null;
					if (dir) {
						fileSlot.playSound("window-new");
						dir.open_path(targetPath);
					} else if (fileSlot.actionManager && fileSlot.actionManager.openAction) {
						fileSlot.actionManager.openAction.execute(targetPath, fileSlot, false);
					}
				});
			}
		}
	}

	// ── Mouse & Drag Handling ───

	// The MouseArea's drag target. The payload is carried by the window's
	// persistent nativeDragSource (see ShellWindow), so this item never owns the
	// QDrag and can be destroyed when the view reloads.
	Item {
		id: localDragTarget
		width: fileSlot.width > 0 ? fileSlot.width : fileSlot.implicitWidth
		height: fileSlot.height > 0 ? fileSlot.height : fileSlot.implicitHeight
	}

	// Hand the in-window free-placement drag to the window's OS drag source.
	// Wrapper so FolderView can call it on the slot (see MouseArea).
	function handOffRepositionDrag(sceneX, sceneY) {
		mouseArea.handOffRepositionDrag(sceneX, sceneY);
	}

	// What a plain left click on this item does. With OpenOnClick off, a click
	// on an unfocused item only moves the cursor to it; a click on the (now
	// focused) item opens it.
	function activateOrFocus() {
		if (!fileSlot.actionManager)
			return;
		if (fileSlot.openOnClick || fileSlot.isFocused) {
			// Collapse the several activation signals one gesture produces into
			// a single open. The same item opened again a moment later is a new
			// gesture and is not affected.
			if (fileSlot.lastActivatedPath === fileSlot.path
				&& Date.now() - fileSlot.lastActivatedTime < 400)
				return;
			fileSlot.lastActivatedPath = fileSlot.path;
			fileSlot.lastActivatedTime = Date.now();
			fileSlot.actionManager.activatePath(fileSlot.path, fileSlot);
		} else if (fileSlot.folderView && typeof fileSlot.folderView.focusSlot === 'function') {
			// Do not reveal the item: scrolling it into view would move the grid
			// before a quick second tap on the same spot lands.
			fileSlot.folderView.focusSlot(fileSlot.path, false);
		}
	}

	MouseArea {
		id: mouseArea
		anchors.fill: parent
		hoverEnabled: true
		acceptedButtons: Qt.LeftButton | Qt.MiddleButton
		pressAndHoldInterval: 300
		cursorShape: Qt.PointingHandCursor

		// Touch drags scroll the view; a slot can only be dragged once it has
		// been held (which selects it). A mouse keeps the immediate-drag
		// behaviour, so touch leaves drag.target unset until the hold.
		property bool touchInput: false
		readonly property bool dragAllowed: mouseArea.touchInput ? mouseArea.isPressAndHoldActive : !mouseArea.isPressAndHoldActive
		drag.target: (mouseArea.touchInput && !mouseArea.isPressAndHoldActive) ? null : localDragTarget
		drag.axis: Drag.XAndYAxis

		property DragDropHandler dragDropHandler: fileSlot.dragDropHandler ? fileSlot.dragDropHandler : null
		property bool dragStarted: false
		property bool isPressAndHoldActive: false
		// True between press and release. The native-drag image grab is
		// asynchronous: if the finger is lifted before it finishes, starting the
		// drag then would leave a drag with no button held ("starts and
		// instantly stops"), so the callback checks this first.
		property bool pointerDown: false
		// Drag ghost grabbed while the finger is held, so a drag that starts on
		// the next move does not wait for an asynchronous render on the slow
		// software renderer (which can outlast the whole gesture).
		property string cachedDragImage: ""
		// The grab result behind cachedDragImage. The URL only stays valid while
		// the result object is alive, and a spring-load handoff can start the OS
		// drag a long time after the grab.
		property var cachedGrabResult: null

		property int startX: 0
		property int startY: 0
		// Finger position in scene coordinates and the view position at press,
		// so a canceled press can tell a tap from a scroll that moved the view.
		property real startSceneX: 0
		property real startSceneY: 0
		property real pressContentY: 0
		// The last pointer position seen while the button is down, in scene
		// coordinates. The release point of a touch is wrong on this device
		// (offset by the window width under QT_SCALE_FACTOR > 1, the same bug
		// ViewSlider works around), so release must reuse the last move point
		// instead of the release event's coordinates.
		property real lastSceneX: 0
		property real lastSceneY: 0
		property real lastLocalX: 0
		property real lastLocalY: 0
		property bool dragInitiated: false
		property bool repositionDrag: false

		Component.onDestruction: {
			mouseArea.pointerDown = false;
			if (typeof dragDropHandler !== 'undefined' && mouseArea.repositionDrag) {
				const fView = fileSlot.folderView;
				if (fView)
					fView.cancelRepositionDrag();
				mouseArea.repositionDrag = false;
			}
			if (typeof dragDropHandler !== 'undefined' && mouseArea.dragStarted) {
				localDragTarget.Drag.active = false;
				dragDropHandler.active_dragged_paths = [];
				dragDropHandler.tooltip_active = false;
				dragDropHandler.end_drag();
			}
		}

		function startNativeDrag(url, width, height, wx, wy) {
			if (typeof dragDropHandler !== 'undefined' && dragDropHandler) {
				dragDropHandler.track_mouse_shake(wx, wy);
				dragDropHandler.begin_drag(String(url), width, height);
			}

			const win = fileSlot.window;
			if (win && typeof win.startNativeDrag === 'function') {
				win.internalDragInProcess = true;
				win.startNativeDrag(String(url), width, height);
			}

			mouseArea.dragStarted = true;
			fileSlot.isDraggingThisSlot = true;
		}

		function grabAndStartNativeDrag(wx, wy) {
			const targetToGrab = contentLayout;

			// A drag ghost grabbed at press-and-hold is ready to use at once, so
			// the drag keeps up with the finger instead of waiting on a render.
			if (mouseArea.cachedDragImage !== "" && mouseArea.pointerDown && mouseArea.dragAllowed) {
				mouseArea.startNativeDrag(mouseArea.cachedDragImage, targetToGrab.width, targetToGrab.height, wx, wy);
				return;
			}

			targetToGrab.grabToImage(function (result) {
				// The grab is asynchronous; the finger may be up by now, in which
				// case starting the drag would leave it running with no button
				// held. Drop it instead.
				if (!mouseArea.pointerDown || !mouseArea.dragAllowed) {
					if (typeof dragDropHandler !== 'undefined' && dragDropHandler) {
						dragDropHandler.active_dragged_paths = [];
						dragDropHandler.tooltip_active = false;
						dragDropHandler.reposition_active = false;
					}
					localDragTarget.Drag.active = false;
					mouseArea.dragStarted = false;
					return;
				}

				mouseArea.startNativeDrag(result.url, targetToGrab.width, targetToGrab.height, wx, wy);
			});
		}

		// Turn the in-window free-placement drag into an OS drag, without
		// waiting for a release. Spring-load navigation destroys this slot, so
		// the payload has to move to the window's persistent drag source first.
		function handOffRepositionDrag(sceneX, sceneY) {
			if (!mouseArea.repositionDrag)
				return;
			mouseArea.repositionDrag = false;
			const fView = fileSlot.folderView;
			if (fView && typeof fView.cancelRepositionDrag === 'function')
				fView.cancelRepositionDrag();
			if (typeof dragDropHandler !== 'undefined' && dragDropHandler)
				dragDropHandler.reposition_active = false;
			mouseArea.grabAndStartNativeDrag(sceneX, sceneY);
		}

		function initiateDragPayload(mouse) {
			if (dragInitiated)
				return;
			dragInitiated = true;
			fileSlot.playSound("drag-start");

			const uris = [];
			const rawPaths = [];
			const mainPath = fileSlot.path;
			const mainUri = mainPath.startsWith("file://") ? mainPath : ("file://" + mainPath);

			let mgr = null;
			let p = fileSlot.parent;
			while (p) {
				if (p.selectionManager) {
					mgr = p.selectionManager;
					break;
				}
				if (p.rootWindow && p.rootWindow.selectionManager) {
					mgr = p.rootWindow.selectionManager;
					break;
				}
				p = p.parent;
			}

			let selectedMap = {};
			try {
				selectedMap = JSON.parse(mgr ? mgr.selected_paths : "{}");
			} catch (e) {}

			if (mgr && mgr.selected_count > 1 && selectedMap[mainPath]) {
				const keys = Object.keys(selectedMap);
				for (let i = 0; i < keys.length; i++) {
					const pathKey = keys[i];
					if (selectedMap[pathKey]) {
						rawPaths.push(pathKey);
						uris.push(pathKey.startsWith("file://") ? pathKey : ("file://" + pathKey));
					}
				}
			} else {
				rawPaths.push(mainPath);
				uris.push(mainUri);
			}

			fileSlot.currentDragCount = rawPaths.length;

			if (typeof dragDropHandler !== 'undefined' && dragDropHandler) {
				dragDropHandler.active_dragged_paths = rawPaths;
				dragDropHandler.set_drag_data(mainPath, uris, rawPaths, uris.length, fileSlot.title, fileSlot.icon);
			}

			const pt = mouseArea.mapToItem(null, mouse.x, mouse.y);

			// A free-placement drag of items that already live in this folder is
			// repositioned directly, without an OS drag, so the whole selection can
			// follow the cursor and the move can be animated.
			const fView = fileSlot.folderView;
			if (fView && typeof fView.beginRepositionDrag === 'function' && fView.beginRepositionDrag(mainPath, rawPaths, pt.x, pt.y, mouse.x, mouse.y)) {
				mouseArea.repositionDrag = true;
				if (typeof dragDropHandler !== 'undefined' && dragDropHandler)
					dragDropHandler.tooltip_active = true;
				return;
			}

			mouseArea.grabAndStartNativeDrag(pt.x, pt.y);
		}

		onPositionChanged: mouse => {
			// Record where the finger actually is before anything else: this is
			// the position a release or cancel has to trust.
			const scene = mouseArea.mapToItem(null, mouse.x, mouse.y);
			mouseArea.lastSceneX = scene.x;
			mouseArea.lastSceneY = scene.y;
			mouseArea.lastLocalX = mouse.x;
			mouseArea.lastLocalY = mouse.y;

			if (typeof dragDropHandler === 'undefined')
				return;

			if (mouseArea.repositionDrag) {
				const pt = mouseArea.mapToItem(null, mouse.x, mouse.y);
				const fView = fileSlot.folderView;
				if (fView) {
					if (fView.repositionCursorOutsideWindow(pt.x, pt.y)) {
						// Hand the gesture over to the OS drag once it leaves the window.
						mouseArea.repositionDrag = false;
						fView.cancelRepositionDrag();
						dragDropHandler.reposition_active = false;
						mouseArea.grabAndStartNativeDrag(pt.x, pt.y);
						return;
					}
					fView.updateRepositionDrag(pt.x, pt.y);
				}
				return;
			}

			if (!mouseArea.dragStarted && mouseArea.dragAllowed && mouseArea.drag.active) {
				const deltaX = mouse.x - mouseArea.startX;
				const deltaY = mouse.y - mouseArea.startY;
				const distance = Math.sqrt(deltaX * deltaX + deltaY * deltaY);

				if (distance > 10) {
					mouseArea.initiateDragPayload(mouse);
				}
			}

			if (mouseArea.dragStarted) {
				const pt = mouseArea.mapToItem(null, mouse.x, mouse.y);
				dragDropHandler.track_mouse_shake(pt.x, pt.y);
			}
		}

		onPressed: mouse => {
			mouseArea.touchInput = mouse.source !== Qt.MouseEventNotSynthesized;
			if (mouse.button === Qt.LeftButton)
				mouseArea.pointerDown = true;

			if (mouse.button === Qt.LeftButton && fileSlot.pressHandler)
				fileSlot.pressHandler(mouse);

			if (mouse.button === Qt.LeftButton && typeof dragDropHandler !== 'undefined') {
				mouseArea.isPressAndHoldActive = false;
				mouseArea.dragInitiated = false;
				mouseArea.repositionDrag = false;

				mouseArea.startX = mouse.x;
				mouseArea.startY = mouse.y;

				const startScene = mouseArea.mapToItem(null, mouse.x, mouse.y);
				mouseArea.startSceneX = startScene.x;
				mouseArea.startSceneY = startScene.y;
				mouseArea.lastSceneX = startScene.x;
				mouseArea.lastSceneY = startScene.y;
				mouseArea.lastLocalX = mouse.x;
				mouseArea.lastLocalY = mouse.y;
				mouseArea.pressContentY = fileSlot.folderView ? fileSlot.folderView.viewContentY : 0;
			}
		}

		onReleased: mouse => {
			mouseArea.isPressAndHoldActive = false;
			mouseArea.dragInitiated = false;
			mouseArea.pointerDown = false;

			if (mouseArea.repositionDrag) {
				// Trust the last move point, not the release event: the touch
				// release coordinate is offset on this device.
				const pt = Qt.point(mouseArea.lastSceneX, mouseArea.lastSceneY);
				const fView = fileSlot.folderView;
				if (fView)
					fView.endRepositionDrag(pt.x, pt.y);
				mouseArea.repositionDrag = false;
				if (typeof dragDropHandler !== 'undefined' && dragDropHandler) {
					dragDropHandler.active_dragged_paths = [];
					dragDropHandler.tooltip_active = false;
					dragDropHandler.reposition_active = false;
				}
				mouseArea.dragStarted = false;
				fileSlot.isDraggingThisSlot = false;
				return;
			}

			// Letting go of a drag that actually moved the item is the drop; a
			// drop onto another folder reports drag-accept itself, so only the
			// release back in place needs the sound here.
			if (mouseArea.dragStarted)
				fileSlot.playSound("drag-accept");

			if (typeof dragDropHandler !== 'undefined' && dragDropHandler) {
				dragDropHandler.active_dragged_paths = [];
				dragDropHandler.tooltip_active = false;
				dragDropHandler.end_drag();
			}
			localDragTarget.Drag.active = false;
			localDragTarget.Drag.imageSource = "";
			mouseArea.dragStarted = false;
			fileSlot.isDraggingThisSlot = false;
		}

		onCanceled: {
			mouseArea.pointerDown = false;
			// A canceled gesture must not leave a reposition drag running: the
			// preview ghost and the drop highlight would stay on screen.
			if (mouseArea.repositionDrag) {
				const fView = fileSlot.folderView;
				if (fView)
					fView.cancelRepositionDrag();
				mouseArea.repositionDrag = false;
				if (typeof dragDropHandler !== 'undefined' && dragDropHandler) {
					dragDropHandler.active_dragged_paths = [];
					dragDropHandler.tooltip_active = false;
					dragDropHandler.reposition_active = false;
				}
				localDragTarget.Drag.active = false;
				mouseArea.dragStarted = false;
				fileSlot.isDraggingThisSlot = false;
				return;
			}

			// Qt cancels the press of a rapid second tap even when the view is
			// not scrolling. Treat that as the tap it was; a real scroll either
			// moves the view or moves the finger past the tap distance.
			if (fileSlot.selectionActive || fileSlot.clickHandler)
				return;
			if (fileSlot.folderView) {
				if (fileSlot.folderView.viewMoving
					|| Math.abs(fileSlot.folderView.viewContentY - mouseArea.pressContentY) > 1)
					return;
			}
			// The release event's coordinates are wrong on this device, so use
			// the last move point (or the press point for a tap).
			if (Math.abs(mouseArea.lastSceneX - mouseArea.startSceneX) > 12
				|| Math.abs(mouseArea.lastSceneY - mouseArea.startSceneY) > 12)
				return;
			fileSlot.activateOrFocus();
		}

		onPressAndHold: {
			mouseArea.isPressAndHoldActive = true;
			fileSlot.pressHeld(fileSlot.path, fileSlot.index);
			// Grab the drag ghost now, while the finger is held, so a drag
			// starting on the next move begins immediately.
			contentLayout.grabToImage(function (result) {
				mouseArea.cachedGrabResult = result;
				mouseArea.cachedDragImage = result.url.toString();
				const win = fileSlot.window;
				if (win && typeof win.preloadDragImage === 'function')
					win.preloadDragImage(mouseArea.cachedDragImage);
			});
		}

		onClicked: mouse => {
			if (mouse.button === Qt.RightButton) {
				return;
			}
			if (mouse.button === Qt.MiddleButton) {
				if (fileSlot.actionManager)
					fileSlot.actionManager.openAction.execute(fileSlot.path, fileSlot, true);
				return;
			}

			if (fileSlot.selectionActive) {
				if (mouse.modifiers & Qt.ShiftModifier) {
					fileSlot.shiftSelected(fileSlot.index);
				} else {
					fileSlot.selectionToggled(fileSlot.path, fileSlot.index);
				}
			} else if (mouse.modifiers & Qt.ControlModifier) {
				fileSlot.selectionToggled(fileSlot.path, fileSlot.index);
			} else if (fileSlot.clickHandler) {
				fileSlot.clickHandler(mouse);
			} else {
				fileSlot.activateOrFocus();
			}
		}

		// Qt turns a quick second press into a double click and skips its
		// `clicked`, so with OpenOnClick off the second tap has to be handled
		// here: on the same item it opens, on another item it moves the cursor.
		onDoubleClicked: mouse => {
			if (mouse.button !== Qt.LeftButton || fileSlot.selectionActive
				|| (mouse.modifiers & Qt.ControlModifier))
				return;
			if (fileSlot.clickHandler) {
				fileSlot.clickHandler(mouse);
				return;
			}
			// With OpenOnClick off the first tap of the gesture only moved the
			// cursor, so this second one opens; with it on the item already
			// opened on the first click and activateOrFocus ignores the repeat.
			fileSlot.activateOrFocus();
		}
	}

	// Hovering an item reveals the text its label is not showing.
	ToolTip.visible: fileSlot.tooltipText !== "" && mouseArea.containsMouse && !fileSlot.isDraggingThisSlot && !(fileSlot.dragDropHandler && fileSlot.dragDropHandler.tooltip_active)
	ToolTip.text: fileSlot.tooltipText
	ToolTip.delay: 700
}
