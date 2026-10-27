pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import org.kde.kirigami as Kirigami
import Hishell

Item {
	id: fileSlot

	required property string path

	// Untyped to avoid the ShellWindow <-> FileSlot cyclic dependency; see
	// ActionManager.qml for the explanation.
	property var window: Window.window
	// The item for the active view mode (grid content or list row). Only one
	// of the two is built per slot.
	readonly property var contentLayout: modeLoader.item
	// The layout inside the mode wrapper: the icon and label only, without the
	// wrapper's cell-sized padding. Used for the suspended-app dot and the
	// launch-animation grab.
	readonly property var contentBody: modeLoader.item && modeLoader.item.children.length > 0
		? modeLoader.item.children[0] : null
	// The icon cell inside that layout, used to place the active-app glow.
	readonly property var iconBody: fileSlot.contentBody && fileSlot.contentBody.children.length > 0
		? fileSlot.contentBody.children[0] : null

	property DragDropHandler dragDropHandler: window ? window.dragDropHandler : null
	property ActionManager actionManager: window ? window.actionManager : null
	property FileManager fileManager: window ? window.fileManager : null

	required property string icon
	required property string title
	// Secondary desktop-entry data; only the list's Comment column shows it.
	property string comment: ""
	property int gridSize: 64
	// List view: one row per item, with the name leading and the configured
	// columns to its right. The row keeps all the grid slot's interaction,
	// selection and drag behaviour; only the content layout changes.
	property bool listMode: false
	property var listColumns: []
	property int listIconSize: 24
	// Filled by the model roles of the same name (see Directory::role_names).
	// The list columns format these values.
	required property real size_bytes
	required property real modified_time
	required property real created_time
	required property real accessed_time
	property bool labelBesideIcon: gridSize < 32
	property bool showLabels: true
	// Folders (and the home icon) are recoloured to the accent by the shell
	// (Breeze draws their bodies with its ColorScheme-Accent class); anything
	// else keeps the icon its resolver chose, and an icon that cannot be
	// recoloured falls back to its plain name.
	// Themed icons are rendered once to a cached PNG and then loaded by the
	// asynchronous Image component, instead of a Kirigami.Icon (a synchronous
	// QIcon decode) in every delegate. The PNG is rendered at the physical
	// pixel size, so it stays sharp at the panel's scale.
	readonly property int iconPixelSize: Math.round(fileSlot.iconDisplaySize * (Screen.devicePixelRatio || 1))
	readonly property string displayIcon: {
		if (!fileSlot.icon || fileSlot.isToggle)
			return fileSlot.icon;
		if (fileSlot.icon.indexOf("file:") === 0 || fileSlot.icon.indexOf("/") === 0)
			return fileSlot.icon;
		// Re-resolve when an idle tick has rendered a queued icon.
		if (fileSlot.fileManager)
			fileSlot.fileManager.icon_revision;
		const recoloured = CoreTheme.accentFolderIcon(fileManager, fileSlot.icon, fileSlot.iconPixelSize);
		return recoloured.length > 0 ? recoloured : fileSlot.icon;
	}
	// Generated descriptor icons are a cartridge frame around a raster label.
	// Qt's SVG renderer smooths that raster; disabling the final image
	// smoothing keeps the label pixels crisp at the file view's icon sizes.
	readonly property bool pixelatedIcon: fileSlot.displayIcon.indexOf("/hishell/descriptors/") !== -1
	// With no label the icon takes over the whole slot, so the view reads as a gallery.
	readonly property real iconDisplaySize: fileSlot.showLabels ? fileSlot.gridSize : Math.max(fileSlot.gridSize, Math.min(fileSlot.width, fileSlot.height) - Kirigami.Units.smallSpacing * 2)
	// Whether the label shows the file name instead of the item's title.
	property bool labelShowsFilename: false
	property bool fixedWidth: true
	property bool showIcon: icon !== ""
	required property bool is_symlink
	required property int index
	// A directory's kind, control kind and control state arrive from the
	// directory model as roles. They used to be five separate Rust calls per
	// delegate (each one a stat and a path decode), on every slot in the
	// folder. Views that are not a model row (the path bar) pass the same
	// values explicitly.
	required property bool is_directory
	required property int control_kind
	required property bool toggle_on
	required property string number_value
	property bool is_dir: is_directory
	property int controlKind: control_kind
	property bool toggleOn: toggle_on
	property string numberValue: number_value

	// A `Type=Button` entry is a control, not a thing to open (docs §2 of
	// docs/settings-as-folders.md): it acts where it stands. Drawing it like the
	// files and folders around it made the two read the same, so it is drawn as
	// a button instead — a filled, rounded plate behind the icon and label,
	// which is the shape every other control on the device already has.
	readonly property bool isButton: fileSlot.controlKind === 1
	// The two settings controls.  A Toggle draws a switch as its icon; a
	// Number opens the number dialog instead of launching anything.
	readonly property bool isToggle: fileSlot.controlKind === 2
	readonly property bool isNumber: fileSlot.controlKind === 3
	readonly property bool isControl: fileSlot.controlKind !== 0
	// A toggle is a switch in its own right, drawn by the QML style, so it sits
	// on the folder background rather than on the button plate that a Button or
	// Number uses.  A switch on top of a button read as an imitation of one.
	readonly property bool hasControlPlate: fileSlot.isControl && !fileSlot.isToggle
	// The current value of a Number control belongs in the list's Comment
	// column, not in its title.  A Toggle's state is already the switch itself,
	// so it keeps the entry's descriptive comment.
	readonly property string displayComment: {
		if (fileSlot.isNumber)
			return fileSlot.numberValue !== "" ? fileSlot.numberValue : fileSlot.comment;
		return fileSlot.comment;
	}
	readonly property string displayTitle: fileSlot.title !== "" ? fileSlot.title : fileSlot.fileName

	// Detailed performance mode logs one line per delegate so a scan can be
	// attributed to file work or to building the visible items. Off in normal
	// builds (FileManager.perf_mode() returns 0).
	Component.onCompleted: {
		const manager = fileSlot.fileManager;
		if (manager && manager.perf_mode() === 2)
			console.log("hishell-perf: delegate " + Date.now() + " "
				+ (fileSlot.listMode ? "list" : "grid") + " " + fileSlot.path);
	}

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
	// Whether a drag is over this slot. The drop area only exists during a
	// drag, so this reads through its loader.
	readonly property bool dropHovered: dropAreaLoader.item ? dropAreaLoader.item.isHovered : false

	// Used for when this item is open in another view
	property bool isActive: false

	// Owner hooks for plain left clicks, used by the path bar to open the current
	// folder's menu instead of reopening it: `pressHandler` is called on press
	// and `clickHandler` replaces the default activation on click.
	property var pressHandler: null
	property var clickHandler: null

	// Focus state (independent of selection). The border itself is drawn by the
	// grid as one shared item (FocusBorder.qml), not per slot. Asking on click
	// instead of binding every delegate to the focus signal keeps a cursor move
	// from re-evaluating a binding in the whole folder.
	function cursorIsFocused() {
		const fm = fileSlot.window ? fileSlot.window.focusManager : null;
		return fm ? (fm.focus_active && String(fm.focused_path) === String(fileSlot.path)) : false;
	}

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
	// A plain binding replaces a per-slot Connections object.
	readonly property bool windowDragging: fileSlot.window ? !!fileSlot.window.internalDragInProcess : false
	onWindowDraggingChanged: {
		if (windowDragging || !fileSlot.isDraggingThisSlot)
			return;
		mouseArea.dragStarted = false;
		fileSlot.isDraggingThisSlot = false;
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

	readonly property var modeLayout: modeLoader.item
	implicitWidth: !modeLayout ? 0
		: (fileSlot.listMode
			? modeLayout.implicitWidth + Kirigami.Units.smallSpacing * 2
			: modeLayout.implicitWidth + (fileSlot.labelBesideIcon && fileSlot.showIcon && fileSlot.showLabels ? Kirigami.Units.largeSpacing * 2 : Kirigami.Units.smallSpacing * 2))
	implicitHeight: !modeLayout ? 0 : modeLayout.implicitHeight + Kirigami.Units.smallSpacing * 2
	// The on-disk name, used by the FILENAME label mode and the tooltip.
	readonly property string fileName: {
		const path = fileSlot.path;
		const slash = path.lastIndexOf("/");
		const name = slash >= 0 ? path.substring(slash + 1) : path;
		return name !== "" ? name : path;
	}

	// The text the label shows; the other one is offered as a tooltip.
	readonly property string labelText: {
		if (fileSlot.labelShowsFilename || fileSlot.title === "")
			return fileSlot.fileName;
		return fileSlot.displayTitle;
	}
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

	// ── List columns ──
	// Human-readable byte count. Folders have no meaningful size here, so the
	// list leaves that cell empty instead of claiming 4 KiB.
	function formatSize(bytes) {
		if (fileSlot.is_dir)
			return "";
		const value = Number(bytes) || 0;
		if (value < 1024)
			return value + " B";
		const units = ["KB", "MB", "GB", "TB", "PB"];
		let scaled = value / 1024;
		let unit = 0;
		while (scaled >= 1024 && unit < units.length - 1) {
			scaled /= 1024;
			unit++;
		}
		return (scaled >= 10 ? Math.round(scaled) : scaled.toFixed(1)) + " " + units[unit];
	}

	function formatDate(milliseconds) {
		const value = Number(milliseconds) || 0;
		if (value <= 0)
			return "";
		return Qt.formatDateTime(new Date(value), "yyyy-MM-dd HH:mm");
	}

	// A compact type label for the list's Type column: "Folder", the upper-case
	// extension, or "File" when there is none. Avoids a per-delegate MIME query.
	readonly property string listTypeText: {
		if (fileSlot.is_dir)
			return qsTr("Folder");
		const name = fileSlot.fileName;
		const dot = name.lastIndexOf(".");
		if (dot > 0 && dot < name.length - 1)
			return name.substring(dot + 1).toUpperCase();
		return qsTr("File");
	}

	function columnText(key) {
		switch (String(key).toUpperCase()) {
		case "TITLE":
			return fileSlot.displayTitle;
		case "FILENAME":
			return fileSlot.fileName;
		case "COMMENT":
			return fileSlot.displayComment;
		case "SIZE":
			return fileSlot.formatSize(fileSlot.size_bytes);
		case "MODIFIED":
			return fileSlot.formatDate(fileSlot.modified_time);
		case "CREATED":
			return fileSlot.formatDate(fileSlot.created_time);
		case "ACCESSED":
			return fileSlot.formatDate(fileSlot.accessed_time);
		case "TYPE":
			return fileSlot.listTypeText;
		default:
			return "";
		}
	}

	// What the drag ghost and press-and-hold grab: the visible content of the
	// slot, whichever layout is active.
	readonly property var dragGrabItem: fileSlot.contentBody ? fileSlot.contentBody : fileSlot.contentLayout
	opacity: {
		if (fileSlot.dragDropHandler && fileSlot.dragDropHandler.active_dragged_paths && fileSlot.dragDropHandler.active_dragged_paths.indexOf(fileSlot.path) !== -1)
			return 0.2;
		return fileSlot.isDotfile ? 0.5 : 1.0;
	}
	// List rows are full-width: a cell-style hover zoom would push a wide row
	// past both edges and fight the shared focus border. Keep rows in place.
	scale: fileSlot.listMode ? 1.0 : (mouseArea.pressed ? 0.9 : (mouseArea.containsMouse ? 1.05 : 1.0))

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
	//
	// Built only for a control: an ordinary item used to pay for the plate's
	// shadow repeater and two shaded rectangles (with their gradient stops)
	// even though it never showed them, which is most of a file slot's object
	// count in a folder of files.
	Loader {
		id: buttonPlateLoader
		anchors.fill: parent
		active: fileSlot.hasControlPlate || fileSlot.isRadio
		sourceComponent: fileSlot.hasControlPlate ? buttonPlateComponent : radioPlateComponent
	}

	Component {
		id: buttonPlateComponent
		Item {
		id: buttonPlate
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
				color: CoreTheme.shadowColor
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
	}

	// ── Radio plate ──
	// A child of a folder-owned radio group is a choice, not an app: a card
	// behind it, and an accent border plus wash when it is the selected one.
	// The parent folder owns the group and runs the apply command.
	Component {
		id: radioPlateComponent
		Rectangle {
		id: radioPlate
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
	}

	// ── Layout ──

	// Only the layout of the active mode is built. Both used to exist in every
	// slot: a grid item also built a whole list row (with its icon loader and
	// column labels) that it never showed, and a list row built the grid.
	Loader {
		id: modeLoader
		anchors.fill: parent
		sourceComponent: fileSlot.listMode ? listComponent : gridComponent
	}

	// List row: icon, then the configured columns. Columns are passed in
	// already normalised and ordered by the view; a name column (Title or File
	// Name) is always present, so the row always has a label.
	Component {
		id: listComponent
		Item {
			id: listContent
			implicitWidth: listLayout.implicitWidth
			implicitHeight: listLayout.implicitHeight
	RowLayout {
		id: listLayout
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.verticalCenter: parent.verticalCenter
		anchors.leftMargin: Kirigami.Units.smallSpacing * 2
		anchors.rightMargin: Kirigami.Units.smallSpacing * 2
		spacing: Kirigami.Units.mediumSpacing

		Item {
			id: listIconItem
			visible: fileSlot.showIcon
			Layout.preferredWidth: fileSlot.listIconSize
			Layout.preferredHeight: fileSlot.listIconSize

			Loader {
				anchors.fill: parent
				// Only the layout of the active view builds its icon. Both
				// loaders used to be live, so every list row decoded a second,
				// larger icon for the invisible grid and vice versa.
				active: fileSlot.listMode && fileSlot.showIcon
				sourceComponent: fileSlot.isToggle
					? listToggleComponent
					: ((fileSlot.displayIcon.startsWith("file://") || fileSlot.displayIcon.startsWith("/")) ? listThumbnailComponent : listIconComponent)
			}

			Component {
				id: listToggleComponent
				Item {
					ToggleSwitch {
						anchors.centerIn: parent
						width: parent.width
						height: parent.height
						on: fileSlot.toggleOn
					}
				}
			}

			Component {
				id: listThumbnailComponent
				Image {
					source: fileSlot.displayIcon
					asynchronous: true
					cache: !fileSlot.displayIcon.endsWith(".svg")
					fillMode: Image.PreserveAspectFit
					smooth: !fileSlot.pixelatedIcon
					anchors.fill: parent
					clip: true
				}
			}

			Component {
				id: listIconComponent
				Kirigami.Icon {
					source: fileSlot.displayIcon
					anchors.fill: parent
				}
			}
		}

		Repeater {
			model: fileSlot.listColumns

			delegate: Text {
				required property var modelData
				Layout.fillWidth: true
				Layout.preferredWidth: modelData.weight
				Layout.minimumWidth: 0
				text: fileSlot.columnText(modelData.key)
				textFormat: Text.PlainText
				color: Kirigami.Theme.textColor
				elide: Text.ElideRight
				maximumLineCount: 1
				horizontalAlignment: modelData.align
				// Name columns use the grid label's resolved face so symlinks
				// stay italic and the active/radio item stays bold. Metadata
				// stays in the normal application face.
				font: modelData.nameColumn
					? (fileSlot.is_symlink
						? (fileSlot.active ? CoreTheme.labelFontItalicBold : CoreTheme.labelFontItalic)
						: (fileSlot.active ? CoreTheme.labelFontBold : CoreTheme.labelFont))
					: Qt.application.font
				opacity: modelData.nameColumn ? 1.0 : 0.85
			}
		}
	}
		}
	}

	Component {
		id: gridComponent
		Item {
			id: gridContent
			implicitWidth: contentLayout.implicitWidth
			implicitHeight: contentLayout.implicitHeight
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
				active: !fileSlot.listMode && fileSlot.showIcon
				sourceComponent: fileSlot.isToggle
					? toggleComponent
					: ((fileSlot.displayIcon.startsWith("file://") || fileSlot.displayIcon.startsWith("/")) ? thumbnailComponent : iconComponent)
			}

			Component {
				id: toggleComponent
				Item {
					ToggleSwitch {
						anchors.centerIn: parent
						width: parent.width
						height: parent.height
						on: fileSlot.toggleOn
					}
				}
			}

			Component {
				id: thumbnailComponent
				Image {
					source: fileSlot.displayIcon
					asynchronous: true
					// Thumbnails are many and disposable, so they stay out of
					// the image cache. A descriptor icon is usually an SVG card
					// and is decoded more expensively; caching it avoids
					// re-rasterising the same file on every repaint.
					cache: !fileSlot.displayIcon.endsWith(".svg")
					fillMode: Image.PreserveAspectFit
					smooth: !fileSlot.pixelatedIcon
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

		Text {
			id: labelItem
			// The list has its own name column; the grid label must not lay
			// text out behind a list row.
			visible: fileSlot.showLabels && !fileSlot.listMode
			Layout.alignment: fileSlot.labelBesideIcon ? Qt.AlignVCenter : Qt.AlignHCenter

			// Plain text, not StyledText: a name is not markup, and the styled
			// layout builds a QTextDocument for every label in the folder. The
			// grid is scrolled by creating delegates, so that cost lands
			// straight in the frame time.
			text: fileSlot.labelText
			textFormat: Text.PlainText
			color: Kirigami.Theme.textColor
			wrapMode: Text.Wrap
			maximumLineCount: 2

			// The four faces are measured once in CoreTheme. Building a pair of
			// FontMetrics (and the QFont behind them) per delegate was paid by
			// every item in the folder for the same two sizes.
			font: fileSlot.is_symlink
				? (fileSlot.active ? CoreTheme.labelFontItalicBold : CoreTheme.labelFontItalic)
				: (fileSlot.active ? CoreTheme.labelFontBold : CoreTheme.labelFont)

			elide: fileSlot.labelBesideIcon ? Text.ElideMiddle : Text.ElideMiddle
			// A button's label is bounded by its plate; an ordinary item's by
			// the grid cell it lives in.  A toggle has no plate even though it
			// is a control, so it follows the ordinary bound.
			Layout.maximumWidth: (fileSlot.hasControlPlate || fileSlot.isRadio)
				? fileSlot.width - Kirigami.Units.smallSpacing * 2 - Kirigami.Units.largeSpacing * 2
				: (fileSlot.labelBesideIcon ? (fileSlot.fixedWidth ? fileSlot.width - fileSlot.gridSize - Kirigami.Units.gridUnit * 2 : 250) : fileSlot.gridSize + Kirigami.Units.gridUnit * 2)
			horizontalAlignment: fileSlot.labelBesideIcon ? Text.AlignLeft : Text.AlignHCenter
		}
	}
		}
	}

	// ── Suspended-app mark ──
	// A small accent dot under an item whose app is currently suspended, with a
	// gentle blink so it reads as "still running". `active_revision` is read only
	// to re-evaluate the binding when the set of suspended apps changes.
	readonly property bool hasActiveApp: {
		const fm = fileSlot.folderView ? fileSlot.folderView.focusManager : null;
		if (!fm)
			return false;
		fm.active_revision; // dependency: re-check when the set changes
		return fm.is_item_active(fileSlot.path);
	}

	// The wash behind the active/radio choice and every selected item. It sits
	// below the content, so it is loaded separately from the badges above it.
	Loader {
		id: selectionWashLoader
		z: -1
		anchors.fill: parent
		active: fileSlot.isSelected || fileSlot.active
		sourceComponent: selectionWashComponent
	}

	Component {
		id: selectionWashComponent
		Rectangle {
			anchors.fill: parent
			anchors.margins: fileSlot.isSelected ? Kirigami.Units.smallSpacing : 0
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
	}

	// ── Selection, focus and drag decorations ──
	// One loader holds the check badge and the drop highlight, both absent
	// while a folder is just being browsed. (The active-app glow lives in the
	// icon cell itself, where its anchors stay local.)
	Loader {
		id: stateDecorationLoader
		anchors.fill: parent
		active: fileSlot.selectionActive || fileSlot.hasActiveApp || fileSlot.dropHovered
		sourceComponent: stateDecorationComponent
	}

	Component {
		id: stateDecorationComponent
		Item {
			anchors.fill: parent

			Rectangle {
				visible: fileSlot.selectionActive
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
			// The focus border is not drawn here: the grid owns one shared
			// border that follows the cursor (FocusBorder.qml). Drawing it per
			// slot meant loading four SVG documents for every item in the
			// folder.
			Rectangle {
				Kirigami.Theme.colorSet: Kirigami.Theme.Selection
				Kirigami.Theme.inherit: false

				visible: fileSlot.selectionActive
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



			// Active app: a soft accent glow under the icon. It is loaded only
			// while the item is actually active, and its position is computed
			// in this item's coordinates so it can cross the layout boundary
			// without an illegal cross-parent anchor.
			Item {
				id: activeGlow
				visible: fileSlot.hasActiveApp && fileSlot.iconBody !== null
				width: fileSlot.iconBody ? Math.max(18, fileSlot.iconBody.width * 1.25) : 0
				height: 12
				readonly property point anchorPoint: fileSlot.iconBody
					? fileSlot.iconBody.mapToItem(fileSlot, fileSlot.iconBody.width / 2, fileSlot.iconBody.height)
					: Qt.point(fileSlot.width / 2, fileSlot.height / 2)
				x: anchorPoint.x - width / 2
				y: anchorPoint.y - height / 2

				Rectangle {
					anchors.fill: parent
					radius: height / 2
					color: Kirigami.Theme.highlightColor
					opacity: 0.22
				}
				Rectangle {
					anchors.horizontalCenter: parent.horizontalCenter
					anchors.verticalCenter: parent.verticalCenter
					width: parent.width * 0.7
					height: Math.max(3, parent.height * 0.28)
					radius: height / 2
					color: Kirigami.Theme.highlightColor
					opacity: 0.85
				}
				SequentialAnimation on opacity {
					running: activeGlow.visible
					loops: Animation.Infinite
					NumberAnimation { to: 0.35; duration: 800; easing.type: Easing.InOutQuad }
					NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutQuad }
				}
			}

			// Drop highlight.
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
		}
	}

	Loader {
		id: dropAreaLoader
		anchors.fill: parent
		// A drop can only arrive while the window owns a drag. Building the
		// area (and its drag handlers) for every item made a folder pay for
		// drag support it was not using.
		active: fileSlot.windowDragging
		sourceComponent: dropAreaComponent
	}

	Component {
		id: dropAreaComponent
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
	}

	Timer {
		id: hoverNavTimer
		interval: 600
		repeat: false
		onTriggered: {
			if (fileSlot.dropHovered && fileSlot.is_dir) {
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
	function handOffRepositionDrag(sceneX, sceneY, onStarted) {
		mouseArea.handOffRepositionDrag(sceneX, sceneY, onStarted);
	}

	// What a plain left click on this item does. With OpenOnClick off, a click
	// on an unfocused item only moves the cursor to it; a click on the (now
	// focused) item opens it.
	function activateOrFocus() {
		if (!fileSlot.actionManager)
			return;
		if (fileSlot.openOnClick || fileSlot.cursorIsFocused()) {
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

		function grabAndStartNativeDrag(wx, wy, onStarted) {
			// `onStarted` must run *inside* the native drag's event loop. Starting
			// an automatic drag calls QDrag::exec(), which does not return until
			// the gesture ends, so a navigation queued after it would only happen
			// after the user lets go. Queue it before `Drag.active` and the nested
			// loop runs it while the drag is still alive.
			const notify = function () {
				if (onStarted)
					Qt.callLater(onStarted);
			};
			const targetToGrab = fileSlot.dragGrabItem;
			if (!targetToGrab) {
				notify();
				return;
			}

			// A drag ghost grabbed at press-and-hold is ready to use at once, so
			// the drag keeps up with the finger instead of waiting on a render.
			if (mouseArea.cachedDragImage !== "" && mouseArea.pointerDown && mouseArea.dragAllowed) {
				notify();
				mouseArea.startNativeDrag(mouseArea.cachedDragImage, targetToGrab.width, targetToGrab.height, wx, wy);
				return;
			}

			targetToGrab.grabToImage(function (result) {
				// The grab is asynchronous; the finger may be up by now, in which
				// case starting the drag would leave it running with no button
				// held. Drop it instead, but still let the caller finish the
				// navigation that the hand-off was for.
				if (!mouseArea.pointerDown || !mouseArea.dragAllowed) {
					if (typeof dragDropHandler !== 'undefined' && dragDropHandler) {
						dragDropHandler.active_dragged_paths = [];
						dragDropHandler.tooltip_active = false;
						dragDropHandler.reposition_active = false;
					}
					localDragTarget.Drag.active = false;
					mouseArea.dragStarted = false;
					mouseArea.cachedGrabResult = result;
					mouseArea.cachedDragImage = result.url.toString();
					notify();
					return;
				}

				mouseArea.cachedGrabResult = result;
				mouseArea.cachedDragImage = result.url.toString();
				notify();
				mouseArea.startNativeDrag(result.url, targetToGrab.width, targetToGrab.height, wx, wy);
			});
		}

		// Turn the in-window free-placement drag into an OS drag, without
		// waiting for a release. Spring-load navigation destroys this slot, so
		// the payload has to move to the window's persistent drag source first.
		function handOffRepositionDrag(sceneX, sceneY, onStarted) {
			// No custom drag to hand over. The caller still needs its navigation
			// to happen, so run the continuation rather than dropping it.
			if (!mouseArea.repositionDrag) {
				if (onStarted)
					onStarted();
				return;
			}
			mouseArea.repositionDrag = false;
			const fView = fileSlot.folderView;
			if (fView && typeof fView.cancelRepositionDrag === 'function')
				fView.cancelRepositionDrag();
			if (typeof dragDropHandler !== 'undefined' && dragDropHandler)
				dragDropHandler.reposition_active = false;
			mouseArea.grabAndStartNativeDrag(sceneX, sceneY, onStarted);
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
				// A spring-load hand-off may need the OS drag image hundreds of
				// milliseconds later. Grab it now, while the source delegate is
				// still alive, so the hand-off does not wait on a render after
				// the folder has already changed.
				if (mouseArea.cachedDragImage === "" && fileSlot.dragGrabItem) {
					const grabItem = fileSlot.dragGrabItem;
					grabItem.grabToImage(function (result) {
						mouseArea.cachedGrabResult = result;
						mouseArea.cachedDragImage = result.url.toString();
						const win = fileSlot.window;
						if (win && typeof win.preloadDragImage === 'function')
							win.preloadDragImage(mouseArea.cachedDragImage);
					});
				}
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
			// starting on the next move begins immediately. An empty slot has
			// nothing to grab yet; the gesture can start once it fills.
			if (!fileSlot.dragGrabItem)
				return;
			fileSlot.dragGrabItem.grabToImage(function (result) {
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
