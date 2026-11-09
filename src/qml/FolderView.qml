import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import hishell_qt
import org.kde.kirigami as Kirigami
import NativeDrag 1.0
import "toolkit"

Kirigami.Page {
	id: pane

	property bool active: false
	property var window: null
	Layout.fillWidth: true
	Layout.fillHeight: true
	padding: 0
	background: Rectangle { color: Kirigami.Theme.backgroundColor }

	signal activated()
	signal focusEdge(string direction)

	property var directory: null

	property string contextTarget: "location"
	property bool suppressFocusSound: false
	property string dropNoticeText: ""

	Timer {
		id: dropNoticeTimer
		interval: 6000
		onTriggered: pane.dropNoticeText = ""
	}

	function dropInto(uris, target, action) {
		if (!pane.directory)
			return false
		const accepted = pane.directory.drop(uris, target, action)
		pane.directory.play_sound(accepted ? "drag-accept" : "drag-fail")
		if (!accepted) {
			const names = String(uris).split("\n")
				.map(uri => String(uri).replace(/^file:\/\//, ""))
				.map(uri => uri.split("/").pop())
				.filter(name => name.length > 0)
			pane.dropNoticeText = names.length === 1
				? "This folder did not keep “" + names[0]
					+ "”. Your original is unchanged."
				: names.length > 1
					? "This folder did not keep " + names.length
						+ " dropped items. Your originals are unchanged."
					: "The drop was not accepted."
			dropNoticeTimer.restart()
		}
		return accepted
	}

	function springEnter(path) {
		DragHelper.setSpringTarget(path)
	}

	function springLeave() {
		DragHelper.clearSpringTarget()
	}

	Connections {
		target: DragHelper
		function onSpringRequested(path) {
			pane.navigateTo(path)
		}
	}
	property string transitionDirection: ""

	// The old panel transition: the folder wallpaper and grid are a panel that
	// grows out of the folder icon (open) or whose snapshot shrinks into the
	// parent's icon (close). Timers and transforms stay in QML; the core only
	// supplies the lexical plan.
	readonly property int openDuration: 260
	readonly property int closeDuration: 200
	property bool transitionAnimating: false
	property string transitionSnapshot: ""
	property var transitionSnapshotResult: null
	property bool transitionClosing: false
	property real transitionPanelOpacity: 1
	property real transitionPanelScale: 1
	property real transitionPanelShiftY: 0
	property real transitionOriginX: width / 2
	property real transitionOriginY: height / 2
	property real transitionTargetX: 0
	property real transitionTargetY: 0
	property real transitionTargetWidth: 0
	property real transitionTargetHeight: 0
	property var pendingNavigation: null
	property string pendingSnapshot: ""
	property bool pendingOriginValid: false
	property real pendingOriginX: 0
	property real pendingOriginY: 0

	readonly property bool animatedNavigation: pane.directory
		? pane.directory.config.smoothScrolling : false

	// One navigation can be several lexical steps: close the current chain
	// back to the common ancestor, then open the destination chain one level
	// at a time. Each step gets its own panel snapshot and animation.
	property bool navigationBusy: false
	property var navigationSteps: []
	property int navigationCloseCount: 0
	property int navigationIndex: 0
	property string navigationTarget: ""

	PathBridge { id: transitionPaths }

	function navigateTo(path) {
		if (!pane.directory || pane.navigationBusy || pane.transitionAnimating)
			return false
		if (String(path) === String(pane.directory.path))
			return true
		if (!pane.animatedNavigation)
			return pane.directory.navigate(path)
		let plan = {}
		try {
			plan = JSON.parse(transitionPaths.navigation_plan(
				String(pane.directory.path), String(path)))
		} catch (error) {
			plan = {}
		}
		const close = plan.close || []
		const open = plan.open || []
		const steps = close.concat(open)
		if (steps.length === 0)
			return pane.directory.navigate(path)
		pane.navigationSteps = steps
		pane.navigationCloseCount = close.length
		pane.navigationIndex = 0
		pane.navigationTarget = String(path)
		pane.navigationBusy = true
		pane.runNavigationStep()
		return true
	}

	function goUp() {
		if (!pane.directory || pane.navigationBusy || pane.transitionAnimating)
			return false
		return pane.navigateTo(transitionPaths.parent_path(String(pane.directory.path)))
	}

	function runNavigationStep() {
		if (!pane.navigationBusy || !pane.directory)
			return
		if (pane.navigationIndex >= pane.navigationSteps.length) {
			pane.finishNavigation()
			return
		}
		const path = String(pane.navigationSteps[pane.navigationIndex])
		if (pane.navigationIndex < pane.navigationCloseCount) {
			// Close the current folder into its parent. The snapshot shrinks
			// into the folder icon that the parent view shows.
			const parent = transitionPaths.parent_path(String(pane.directory.path))
			pane.pendingOriginValid = false
			const record = pane.navigationIndex === pane.navigationSteps.length - 1
			pane.beginTransition(function () {
				return pane.directory.navigate_step(parent, record)
			})
			return
		}
		// Open one level, growing out of that folder's icon in the parent.
		const icon = folderGrid.itemIconViewRect(path)
		pane.pendingOriginValid = icon !== null
		pane.pendingOriginX = icon ? icon.x + icon.width / 2 : 0
		pane.pendingOriginY = icon ? icon.y + icon.height / 2 : 0
		const record = pane.navigationIndex === pane.navigationSteps.length - 1
		if (record)
			pane.directory.play_sound("window-new")
		pane.beginTransition(function () {
			return pane.directory.navigate_step(path, record)
		})
	}

	function advanceNavigation() {
		pane.navigationIndex += 1
		pane.runNavigationStep()
	}

	function finishNavigation() {
		pane.navigationBusy = false
		pane.navigationSteps = []
		pane.navigationCloseCount = 0
		pane.navigationIndex = 0
		pane.navigationTarget = ""
	}

	function beginTransition(action) {
		if (!pane.animatedNavigation) {
			if (!action())
				return false
			return true
		}
		pane.transitionAnimating = true
		pane.pendingNavigation = action
		pane.pendingSnapshot = ""
		grabWatchdog.restart()
		if (!folderPanel || folderPanel.width <= 0 || folderPanel.height <= 0) {
			pane.completeTransitionGrab(null)
			return true
		}
		folderPanel.grabToImage(function (result) {
			pane.completeTransitionGrab(result)
		}, Qt.size(
			Math.max(1, Math.round(folderPanel.width * 0.7)),
			Math.max(1, Math.round(folderPanel.height * 0.7))))
		return true
	}

	// The grab is asynchronous, so the path change waits for it; the watchdog
	// keeps a lost grab from stranding the navigation.
	function completeTransitionGrab(result) {
		grabWatchdog.stop()
		const action = pane.pendingNavigation
		pane.pendingNavigation = null
		if (!action)
			return
		pane.transitionSnapshotResult = result && result.url ? result : null
		pane.pendingSnapshot = result && result.url ? String(result.url) : ""
		if (!action()) {
			pane.navigationBusy = false
			pane.finishTransition()
		}
	}

	Timer {
		id: grabWatchdog
		interval: 150
		repeat: false
		onTriggered: pane.completeTransitionGrab(null)
	}

	function relationName(relation) {
		if (!relation)
			return ""
		if (typeof relation === "string")
			return relation
		if (typeof relation === "object") {
			for (const key in relation)
				return String(key)
		}
		return ""
	}

	function startTransition(plan) {
		const closing = pane.relationName(plan.relation) === "Parent"
		pane.transitionClosing = closing
		pane.transitionSnapshot = pane.pendingSnapshot
		if (pane.transitionSnapshot === "") {
			pane.finishTransition()
			return
		}
		transitionBackdrop.snapshotResult = pane.transitionSnapshotResult
		transitionBackdrop.source = pane.transitionSnapshot
		transitionBackdrop.visible = true
		transitionBackdrop.x = 0
		transitionBackdrop.y = 0
		transitionBackdrop.width = pane.width
		transitionBackdrop.height = pane.height
		transitionBackdrop.opacity = 1
		transitionDim.opacity = 0.45
		transitionBackdrop.z = closing ? 50 : -2
		transitionDim.z = closing ? 49 : -1
		if (closing) {
			const icon = folderGrid.itemIconViewRect(String(plan.from || ""))
			if (!icon) {
				pane.finishTransition()
				return
			}
			pane.transitionTargetX = icon.x
			pane.transitionTargetY = icon.y
			pane.transitionTargetWidth = icon.width
			pane.transitionTargetHeight = icon.height
			closeTransitionAnimation.restart()
			return
		}
		if (!pane.pendingOriginValid) {
			pane.finishTransition()
			return
		}
		pane.transitionOriginX = pane.pendingOriginX
		pane.transitionOriginY = pane.pendingOriginY
		pane.transitionPanelOpacity = 0
		pane.transitionPanelScale = 0.35
		pane.transitionPanelShiftY = Math.max(20, pane.height * 0.16)
		openTransitionAnimation.restart()
	}

	function finishTransition() {
		pane.transitionAnimating = false
		pane.pendingNavigation = null
		pane.pendingSnapshot = ""
		pane.transitionSnapshot = ""
		pane.transitionSnapshotResult = null
		transitionBackdrop.visible = false
		transitionBackdrop.source = ""
		transitionBackdrop.snapshotResult = null
		transitionBackdrop.opacity = 1
		transitionDim.opacity = 0
		pane.transitionPanelOpacity = 1
		pane.transitionPanelScale = 1
		pane.transitionPanelShiftY = 0
		if (pane.navigationBusy)
			Qt.callLater(function () { pane.advanceNavigation() })
	}

	readonly property alias renameDialogOpen: renameDialog.visible
	readonly property alias trashDialogOpen: trashDialog.visible
	readonly property alias openWithDialogOpen: openWithDialog.visible

	function openContextMenu() {
		contextMenu.popup()
	}

	function openLocationMenuAt(anchor) {
		if (!pane.directory || !anchor)
			return
		pane.contextTarget = "location"
		const position = anchor.mapToItem(pane, 0, anchor.height)
		contextMenu.popup(pane, position.x, position.y)
	}

	// Context menu for the focused item, shared by the Menu key, Shift+F10,
	// and the gamepad menu button. An empty slot is background, so it opens
	// the folder menu.
	function openFocusedMenu() {
		if (!pane.active || !pane.directory)
			return
		if (pane.directory.focusOnEmpty) {
			pane.contextTarget = "location"
			contextMenu.popup()
			return
		}
		if (pane.directory.focused_path.length > 0) {
			pane.contextTarget = "focus"
			contextMenu.popup()
		}
	}

	function closeDialogs() {
		renameDialog.close()
		trashDialog.close()
		openWithDialog.close()
	}

	onActiveChanged: if (active)
		folderGrid.focusView()

	function focusView() {
		folderGrid.focusView()
	}

	function focusFirst() {
		pane.directory.focus_first()
	}

	function focusLast() {
		pane.directory.focus_last()
	}

	function handleGamepad(action) {
		if (action === "up" || action === "down" || action === "left" || action === "right") {
			if (!pane.directory.move_focus(action) && (action === "left" || action === "right"))
				pane.focusEdge(action)
		} else if (action === "accept") {
			if (pane.directory.focused_path.length > 0) {
				if (pane.directory.is_directory(pane.directory.focused_path))
					pane.navigateTo(pane.directory.focused_path)
				else
					pane.directory.open(pane.directory.focused_path)
			}
		} else if (action === "cancel") {
			// South is Back; with nothing behind it, it is silent.
			if (pane.directory.can_go_back())
				pane.directory.back()
		} else if (action === "menu") {
			pane.openFocusedMenu()
		} else if (action === "select") {
			if (pane.directory.focused_path.length > 0)
				pane.directory.toggle_select(pane.directory.focused_path)
		} else if (action === "directory") {
			pane.contextTarget = "location"
			contextMenu.popup()
		}
	}

	// Drops copy by default; Shift moves and Ctrl+Shift links. Qt's proposed
	// action defaults to move, which used to destroy a file dropped back into
	// its own folder.
	function dropAction(drop) {
		if (drop.proposedAction === Qt.MoveAction)
			return "move"
		if (drop.proposedAction === Qt.LinkAction)
			return "link"
		return "copy"
	}

	// Buttons, toggles and numbers act where they stand instead of opening.
	function activatePath(path) {
		const directory = pane.directory
		if (!directory)
			return
		if (directory.is_rename_only(path)) {
			directory.invoke("rename")
			return
		}
		if (directory.is_radio_member(path)) {
			directory.play_sound("item-selected")
			directory.invoke("radio")
			return
		}
		const kind = directory.control_kind(path)
		if (kind === 2 || kind === 3) {
			directory.play_sound(kind === 3
				? "button-toggle-off" : "button-toggle-on")
			directory.invoke("toggle")
			return
		}
		if (kind === 4) {
			directory.invoke("number")
			return
		}
		if (directory.is_directory(path))
			pane.navigateTo(path)
		else
			directory.open(path)
	}

	function baseName(path) {
		const parts = String(path).split("/").filter(part => part.length > 0)
		return parts.length > 0 ? parts[parts.length - 1] : String(path)
	}

	function dragUrl(path) {
		return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
	}

	function clickTarget(path, modifiers) {
		const directory = pane.directory
		if (!directory)
			return
		pane.activated()
		pane.focusView()
		pane.suppressFocusSound = true
		directory.focus_path(path)
		directory.play_sound("item-selected")
		Qt.callLater(function () { pane.suppressFocusSound = false })
		if (directory.selectionActive) {
			if (modifiers & Qt.ShiftModifier)
				directory.select_range(path)
			else
				directory.toggle_select(path)
		} else if (modifiers & Qt.ControlModifier) {
			directory.toggle_select(path)
		} else if (modifiers & Qt.ShiftModifier) {
			directory.select_range(path)
		} else if (directory.config.open_on_click) {
			pane.activatePath(path)
		} else {
			directory.select(path)
		}
	}

	function middleTarget(path) {
		if (pane.directory)
			pane.directory.open_in_new_window(path)
	}

	function holdTarget(path) {
		const directory = pane.directory
		if (!directory)
			return
		pane.activated()
		pane.focusView()
		directory.focus_path(path)
		directory.select(path)
	}

	function doubleTarget(path) {
		const directory = pane.directory
		if (directory && !directory.config.open_on_click)
			pane.activatePath(path)
	}

	// Shift extends the selection with the item the cursor lands on; that
	// gesture owns its sound, so the focus move stays quiet.
	function moveFocus(direction, modifiers) {
		const extend = (modifiers & Qt.ShiftModifier) !== 0
		pane.suppressFocusSound = extend
		const moved = pane.directory.move_focus(direction)
		pane.suppressFocusSound = false
		if (!moved) {
			pane.focusEdge(direction)
			return
		}
		if (extend && pane.directory.focused_path.length > 0) {
			pane.directory.play_sound("item-selected")
			pane.directory.toggle_select(pane.directory.focused_path)
		}
	}

	function handleFilterKey(event) {
		const directory = pane.directory
		if (!directory)
			return false
		const active = String(directory.filter).length > 0
		const control = (event.modifiers
			& (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) !== 0

		if (event.key === Qt.Key_Escape) {
			if (!active)
				return false
			directory.clear_filter()
			return true
		}
		if (event.key === Qt.Key_Backspace) {
			if (!active)
				return false
			directory.backspace_filter()
			return true
		}
		if (event.key === Qt.Key_Space && !active)
			return false
		if (control || event.text.length === 0)
			return false
		for (let i = 0; i < event.text.length; i++) {
			const code = event.text.charCodeAt(i)
			if (code < 0x20 || code === 0x7f)
				return false
		}
		directory.append_filter(event.text)
		return true
	}

	function handleKey(event) {
		if (pane.handleFilterKey(event)) {
			event.accepted = true
			return
		}
		if (event.key === Qt.Key_Left
				&& (event.modifiers & Qt.AltModifier)) {
			pane.directory.back()
			event.accepted = true
		} else if (event.key === Qt.Key_Right
				&& (event.modifiers & Qt.AltModifier)) {
			pane.directory.forward()
			event.accepted = true
		} else if (event.key === Qt.Key_Left) {
			pane.moveFocus("left", event.modifiers)
			event.accepted = true
		} else if (event.key === Qt.Key_Right) {
			pane.moveFocus("right", event.modifiers)
			event.accepted = true
		} else if (event.key === Qt.Key_Up) {
			if (event.modifiers & Qt.AltModifier) {
				pane.goUp()
			} else {
				pane.moveFocus("up", event.modifiers)
			}
			event.accepted = true
		} else if (event.key === Qt.Key_Down) {
			pane.moveFocus("down", event.modifiers)
			event.accepted = true
		} else if (event.key === Qt.Key_Home) {
			pane.directory.focus_first()
			event.accepted = true
		} else if (event.key === Qt.Key_End) {
			pane.directory.focus_last()
			event.accepted = true
		} else if (event.key === Qt.Key_A
				&& (event.modifiers & Qt.ControlModifier)) {
			pane.directory.select_all()
			event.accepted = true
		} else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
			pane.directory.play_sound("return")
			if (pane.directory.focused_path.length > 0)
				pane.activatePath(pane.directory.focused_path)
			event.accepted = true
		} else if (event.key === Qt.Key_Menu
				|| (event.key === Qt.Key_F10
					&& (event.modifiers & Qt.ShiftModifier))) {
			pane.openFocusedMenu()
			event.accepted = true
		} else if (event.key === Qt.Key_Escape) {
			if (pane.directory.selection_active)
				pane.directory.clear_selection()
			pane.directory.focus_path("")
			event.accepted = true
		} else if (event.key === Qt.Key_Space) {
			if (pane.directory.focused_path.length > 0)
				pane.directory.toggle_select(pane.directory.focused_path)
			event.accepted = true
		} else if (event.key === Qt.Key_Backspace) {
			pane.goUp()
			event.accepted = true
		}
	}

	Component.onCompleted: if (pane.directory)
		pane.directory.focus_first()


	Connections {
		target: pane.directory
		function onRename_requested(path, suggested) {
			renameDialog.targetPath = path
			renameDialog.originalName = suggested
			renameDialog.open()
		}
		function onTrash_requested(pathsJson, permanent) {
			trashDialog.pathsJson = pathsJson
			trashDialog.permanent = permanent
			trashDialog.open()
		}
		function onProperties_requested(path) {
			propertiesDialog.rows = JSON.parse(pane.directory.properties_json(path))
			propertiesDialog.open()
		}
		function onOpen_with_requested(path) {
			openWithDialog.targetPath = path
			openWithDialog.open()
		}
		function onNumber_requested(path) {
			numberDialog.openFor(path)
		}
		function onLaunch_confirm_requested(launchId, blockedItem, launchItem) {
			launchConfirmDialog.openFor(launchId, blockedItem, launchItem)
		}
		function onLaunch_failed(reason) {
			pane.dropNoticeText = reason
			dropNoticeTimer.restart()
			pane.directory.play_sound("dialog-error")
		}
		function onFocus_changed() {
			if (pane.navigationBusy || pane.transitionAnimating
					|| pane.suppressFocusSound || !pane.directory)
				return
			if (pane.directory.focused_path.length > 0)
				pane.directory.play_sound("item-focus")
		}
		function onTransition_requested(planJson) {
			let plan = {}
			try {
				plan = JSON.parse(planJson)
			} catch (e) {
				plan = {}
			}
			pane.transitionDirection = pane.relationName(plan.relation) === "Parent"
				? "out" : "in"
			if (pane.transitionAnimating)
				pane.startTransition(plan)
		}
	}

	ParallelAnimation {
		id: openTransitionAnimation
		NumberAnimation {
			target: pane
			property: "transitionPanelScale"
			to: 1
			duration: pane.openDuration
			easing.type: Easing.OutCubic
		}
		NumberAnimation {
			target: pane
			property: "transitionPanelShiftY"
			to: 0
			duration: pane.openDuration
			easing.type: Easing.OutCubic
		}
		NumberAnimation {
			target: pane
			property: "transitionPanelOpacity"
			to: 1
			duration: pane.openDuration
			easing.type: Easing.OutCubic
		}
		onFinished: pane.finishTransition()
	}

	ParallelAnimation {
		id: closeTransitionAnimation
		NumberAnimation {
			target: transitionBackdrop
			property: "x"
			to: pane.transitionTargetX
			duration: pane.closeDuration
			easing.type: Easing.OutCubic
		}
		NumberAnimation {
			target: transitionBackdrop
			property: "y"
			to: pane.transitionTargetY
			duration: pane.closeDuration
			easing.type: Easing.OutCubic
		}
		NumberAnimation {
			target: transitionBackdrop
			property: "width"
			to: pane.transitionTargetWidth
			duration: pane.closeDuration
			easing.type: Easing.OutCubic
		}
		NumberAnimation {
			target: transitionBackdrop
			property: "height"
			to: pane.transitionTargetHeight
			duration: pane.closeDuration
			easing.type: Easing.OutCubic
		}
		SequentialAnimation {
			PauseAnimation {
				duration: pane.closeDuration * 0.75
			}
			NumberAnimation {
				target: transitionBackdrop
				property: "opacity"
				to: 0
				duration: pane.closeDuration * 0.25
			}
		}
		NumberAnimation {
			target: transitionDim
			property: "opacity"
			to: 0
			duration: pane.closeDuration
		}
		onFinished: pane.finishTransition()
	}

	Dialog {
		id: renameDialog
		property string targetPath: ""
		property string originalName: ""
		property string errorText: ""
		modal: true
		title: "Rename"
		standardButtons: Dialog.NoButton
		onOpened: {
			renameDialog.errorText = ""
			renameField.text = originalName
			Qt.callLater(function () {
				renameField.forceActiveFocus()
				renameField.selectAll()
			})
		}

		function apply() {
			if (renameDialog.targetPath.length === 0)
				return
			if (renameField.text.length === 0
					|| renameField.text === renameDialog.originalName) {
				renameDialog.close()
				return
			}
			let result = { "ok": false, "error": "" }
			try {
				result = JSON.parse(String(pane.directory.rename_result(
					renameDialog.targetPath, renameField.text)))
			} catch (error) {
				result = { "ok": false, "error": "Rename failed." }
			}
			if (result.ok) {
				pane.directory.play_sound("dialog-ok")
				renameDialog.close()
			} else {
				renameDialog.errorText = result.error || "Rename failed."
				pane.directory.play_sound("dialog-error")
				renameField.forceActiveFocus()
			}
		}

		ColumnLayout {
			anchors.fill: parent
			TextField {
				id: renameField
				Layout.fillWidth: true
				onAccepted: renameDialog.apply()
			}
			Label {
				Layout.fillWidth: true
				visible: renameDialog.errorText.length > 0
				text: renameDialog.errorText
				color: Kirigami.Theme.negativeTextColor
				wrapMode: Text.WordWrap
			}
			RowLayout {
				Layout.alignment: Qt.AlignRight
				Button {
					text: "Rename"
					icon.name: "dialog-ok"
					onClicked: renameDialog.apply()
				}
				Button {
					text: "Cancel"
					icon.name: "dialog-cancel"
					onClicked: renameDialog.close()
				}
			}
		}
	}

	Dialog {
		id: trashDialog
		property string pathsJson: "[]"
		property bool permanent: false
		property var queue: []
		property var ordinary: []
		property bool batchPending: false
		property string targetPath: ""
		property var options: ({})
		property bool didSomething: false
		modal: true
		title: trashDialog.options.unmount
			? "Unmount device?" : (trashDialog.options.reset
				? "Remove or reset?" : (trashDialog.permanent
					? "Delete permanently?" : "Move to Trash?"))
		standardButtons: Dialog.NoButton

		function readOptions(path) {
			try {
				return JSON.parse(String(pane.directory.destroy_options(path)))
			} catch (error) {
				return {}
			}
		}

		function advance() {
			if (trashDialog.queue.length === 0) {
				trashDialog.close()
				return
			}
			trashDialog.targetPath = String(trashDialog.queue.shift())
			trashDialog.options = trashDialog.readOptions(
				trashDialog.targetPath)
		}

		function choose(action) {
			let changed = false
			if (action === "destroy") {
				changed = pane.directory.destroy_paths(
					trashDialog.batchPending
						? JSON.stringify(trashDialog.ordinary)
						: JSON.stringify([trashDialog.targetPath]),
					trashDialog.permanent)
				if (trashDialog.batchPending) {
					trashDialog.ordinary = []
					trashDialog.batchPending = false
				}
			} else if (action === "reset") {
				changed = pane.directory.reset_path(trashDialog.targetPath)
			} else if (action === "unmount") {
				changed = pane.directory.unmount_path(trashDialog.targetPath)
			}
			if (changed)
				trashDialog.didSomething = true
			trashDialog.advance()
		}

		onOpened: {
			let paths = []
			try {
				paths = JSON.parse(String(trashDialog.pathsJson))
			} catch (error) {
				paths = []
			}
			trashDialog.queue = []
			trashDialog.ordinary = []
			trashDialog.didSomething = false
			for (let i = 0; i < paths.length; i++) {
				const path = String(paths[i])
				const info = trashDialog.readOptions(path)
				// Ordinary content shares one confirmation. Sections and
				// system-owned entries need a choice, one item at a time.
				if (info.unmount === true || info.section === true
						|| info.destroy !== true)
					trashDialog.queue.push(path)
				else
					trashDialog.ordinary.push(path)
			}
			trashDialog.batchPending = trashDialog.ordinary.length > 0
			if (trashDialog.batchPending) {
				trashDialog.targetPath = ""
				trashDialog.options = ({
					"destroy": true,
					"reset": false,
					"unmount": false,
					"section": false
				})
			} else {
				trashDialog.advance()
			}
		}
		onClosed: {
			if (trashDialog.didSomething) {
				pane.directory.play_sound("item-deleted")
				pane.directory.clear_selection()
				pane.directory.refresh()
			}
			trashDialog.queue = []
			trashDialog.ordinary = []
			trashDialog.batchPending = false
			trashDialog.didSomething = false
		}

		ColumnLayout {
			Label {
				Layout.fillWidth: true
				wrapMode: Text.WordWrap
				text: {
					if (trashDialog.options.unmount)
						return "This is a mounted device. Unmount it to make it go away."
					if (trashDialog.options.reset
							&& !trashDialog.options.destroy)
						return "This item belongs to the system. Reset its settings instead?"
					if (trashDialog.options.reset)
						return "Remove this item, or reset its settings?"
					if (!trashDialog.options.destroy)
						return "This item belongs to the system and cannot be deleted."
					return trashDialog.permanent
						? "This cannot be undone."
						: "The items can be restored from the trash."
				}
			}
			RowLayout {
				Layout.alignment: Qt.AlignRight
				Button {
					visible: trashDialog.options.unmount === true
					text: "Unmount"
					icon.name: "media-eject"
					onClicked: trashDialog.choose("unmount")
				}
				Button {
					visible: trashDialog.options.reset === true
					text: "Reset Settings"
					icon.name: "edit-reset"
					onClicked: trashDialog.choose("reset")
				}
				Button {
					visible: trashDialog.options.destroy === true
					text: trashDialog.permanent ? "Delete" : "Remove"
					icon.name: trashDialog.permanent
						? "edit-delete" : "user-trash"
					onClicked: trashDialog.choose("destroy")
				}
				Button {
					text: "Cancel"
					icon.name: "dialog-cancel"
					onClicked: {
						trashDialog.queue = []
						trashDialog.ordinary = []
						trashDialog.batchPending = false
						trashDialog.close()
					}
				}
			}
		}
	}

	Dialog {
		id: openWithDialog
		property string targetPath: ""
		property var apps: []
		modal: true
		title: "Open With"
		standardButtons: Dialog.Cancel
		onOpened: apps = JSON.parse(pane.directory.apps_json(targetPath))

		ColumnLayout {
			Repeater {
				model: openWithDialog.apps
				Button {
					required property var modelData
					Layout.fillWidth: true
					text: modelData.name
					onClicked: {
						pane.directory.open_with(openWithDialog.targetPath, modelData.id)
						openWithDialog.close()
					}
				}
			}
		}
	}

	Dialog {
		id: numberDialog
		property string targetPath: ""
		property var fields: []
		property var values: []
		modal: true
		title: "Set values"
		standardButtons: Dialog.Ok | Dialog.Cancel
		onAccepted: {
			if (targetPath.length === 0 || values.length === 0) {
				return
			}
			pane.directory.run_number(targetPath, values.join(","))
			pane.directory.play_sound("button-released")
			numberReload.restart()
		}
		onRejected: if (visible)
			pane.directory.play_sound("dialog-cancel")

		function openFor(path) {
			numberDialog.targetPath = path
			let spec = { "ok": false, "fields": [] }
			try {
				spec = JSON.parse(String(pane.directory.number_spec(path)))
			} catch (error) {
				spec = { "ok": false, "fields": [] }
			}
			numberDialog.fields = spec.fields || []
			numberDialog.values = numberDialog.fields.map(field => Number(field.value))
			if (spec.ok) {
				pane.directory.play_sound("dialog-open")
				numberDialog.open()
			}
		}

		Timer {
			id: numberReload
			interval: 350
			onTriggered: if (pane.directory)
				pane.directory.refresh()
		}

		ColumnLayout {
			Repeater {
				model: numberDialog.fields

				ColumnLayout {
					required property var modelData
					required property int index
					Label {
						text: modelData.label
						font.bold: true
					}
					SpinBox {
						from: modelData.min
						to: modelData.max
						value: Math.max(modelData.min, Math.min(modelData.max,
							Number(numberDialog.values[index] ?? modelData.value)))
						editable: true
						onValueModified: {
							const next = numberDialog.values.slice()
							next[index] = value
							numberDialog.values = next
						}
					}
				}
			}
		}
	}

	Dialog {
		id: launchConfirmDialog
		property int launchId: -1
		property string blockedItem: ""
		property string launchItem: ""
		property bool confirmed: false
		modal: true
		title: "Launch"
		standardButtons: Dialog.NoButton
		onOpened: pane.directory.play_sound("dialog-open")
		onClosed: {
			if (!launchConfirmDialog.confirmed
					&& launchConfirmDialog.launchId >= 0)
				pane.directory.cancel_launch(launchConfirmDialog.launchId)
			launchConfirmDialog.launchId = -1
		}

		function openFor(id, blocked, launch) {
			launchConfirmDialog.launchId = id
			launchConfirmDialog.blockedItem = String(blocked)
			launchConfirmDialog.launchItem = String(launch)
			launchConfirmDialog.confirmed = false
			launchConfirmDialog.open()
		}

		ColumnLayout {
			Label {
				Layout.fillWidth: true
				wrapMode: Text.WordWrap
				text: "Close the suspended app “"
					+ pane.baseName(launchConfirmDialog.blockedItem)
					+ "” and launch “"
					+ pane.baseName(launchConfirmDialog.launchItem) + "”?"
			}
			Label {
				Layout.fillWidth: true
				wrapMode: Text.WordWrap
				text: "Any unsaved data will be lost."
			}
			RowLayout {
				Layout.alignment: Qt.AlignRight
				Button {
					text: "Close and Launch"
					icon.name: "system-run"
					onClicked: {
						launchConfirmDialog.confirmed = true
						pane.directory.confirm_launch(
							launchConfirmDialog.launchId)
						pane.directory.play_sound("dialog-ok")
						launchConfirmDialog.close()
					}
				}
				Button {
					text: "Cancel"
					icon.name: "dialog-cancel"
					onClicked: launchConfirmDialog.close()
				}
			}
		}
	}

	Dialog {
		id: propertiesDialog
		property var rows: []
		modal: true
		title: "Properties"
		standardButtons: Dialog.Close

		ColumnLayout {
			anchors.fill: parent
			RowLayout {
				Layout.fillWidth: true
				Label { text: "Name"; Layout.preferredWidth: 90; font.bold: true }
				Label { text: propertiesDialog.rows.name || ""; Layout.fillWidth: true; elide: Text.ElideMiddle }
			}
			RowLayout {
				Layout.fillWidth: true
				Label { text: "Path"; Layout.preferredWidth: 90; font.bold: true }
				Label { text: propertiesDialog.rows.path || ""; Layout.fillWidth: true; elide: Text.ElideMiddle }
			}
			RowLayout {
				Layout.fillWidth: true
				Label { text: "Type"; Layout.preferredWidth: 90; font.bold: true }
				Label { text: propertiesDialog.rows.type || ""; Layout.fillWidth: true }
			}
			RowLayout {
				Layout.fillWidth: true
				Label { text: "Size"; Layout.preferredWidth: 90; font.bold: true }
				Label { text: pane.formatSize(propertiesDialog.rows.size || 0); Layout.fillWidth: true }
			}
			RowLayout {
				Layout.fillWidth: true
				Label { text: "Modified"; Layout.preferredWidth: 90; font.bold: true }
				Label { text: pane.formatTime(propertiesDialog.rows.modified || 0); Layout.fillWidth: true }
			}
			RowLayout {
				Layout.fillWidth: true
				Label { text: "MIME"; Layout.preferredWidth: 90; font.bold: true }
				Label { text: propertiesDialog.rows.mime || ""; Layout.fillWidth: true }
			}
		}
	}

	ShellContextMenu {
		id: contextMenu
		directory: pane.directory
		window: pane.window
		targetIsBackground: pane.contextTarget === "location"
		targetIsDir: pane.directory ? pane.directory.focusIsDirectory : false
		targetIsImage: pane.directory ? pane.directory.focusIsImage : false
	}

	function formatSize(bytes) {
		if (!(bytes > 0))
			return ""
		const units = ["B", "kB", "MB", "GB", "TB"]
		let value = Number(bytes)
		let unit = 0
		while (value >= 1024 && unit < units.length - 1) {
			value /= 1024
			unit += 1
		}
		return unit === 0 ? value + " " + units[unit]
			: value.toFixed(value >= 10 ? 0 : 1) + " " + units[unit]
	}

	function formatTime(milliseconds) {
		if (!(milliseconds > 0))
			return ""
		return Qt.formatDateTime(new Date(Number(milliseconds)), "yyyy-MM-dd HH:mm")
	}

	// The folder being left, shown behind the opening panel (open) or over the
	// parent while shrinking into its icon (close).
	Image {
		id: transitionBackdrop
		property var snapshotResult: null
		x: 0
		y: 0
		width: pane.width
		height: pane.height
		z: -2
		visible: false
		fillMode: Image.Stretch
		smooth: true
		cache: false
		asynchronous: false
		opacity: 1
	}

	Rectangle {
		id: transitionDim
		anchors.fill: parent
		z: -1
		color: "black"
		opacity: 0
	}

	Item {
		id: folderPanel
		anchors.fill: parent
		opacity: pane.transitionPanelOpacity
		transform: [
			Translate {
				y: pane.transitionPanelShiftY
			},
			Scale {
				origin.x: pane.transitionOriginX
				origin.y: pane.transitionOriginY
				xScale: pane.transitionPanelScale
				yScale: pane.transitionPanelScale
			}
		]

		// The folder panel is opaque: during an open it carries the window
		// background out of the source folder icon instead of letting the old
		// snapshot show through the new grid.
		Rectangle {
			anchors.fill: parent
			color: Kirigami.Theme.backgroundColor
		}

		FolderGrid {
			id: folderGrid
			anchors.fill: parent
			pane: pane
			filterHeight: filterBar.height
		}
	}

	// Swallow presses while a close/open step is running, like the old
	// transition overlay, so a second tap cannot navigate through it.
	MouseArea {
		anchors.fill: parent
		z: 60
		enabled: pane.transitionAnimating
		acceptedButtons: Qt.AllButtons
	}

	FolderFilterBar {
		id: filterBar
		directory: pane.directory
		matchCount: pane.directory ? pane.directory.matchCount : 0
		filterActive: folderGrid.filterActive
		window: pane.window
		onFocusRequested: folderGrid.focusView()
		onClearRequested: {
			if (pane.directory)
				pane.directory.clear_filter()
			folderGrid.focusView()
		}
	}

	FolderSelectionBar {
		directory: pane.directory
		window: pane.window
	}
	Rectangle {
		id: dropNoticeBanner
		visible: pane.dropNoticeText.length > 0
		anchors.top: parent.top
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.margins: Kirigami.Units.mediumSpacing
		height: dropNoticeRow.implicitHeight + Kirigami.Units.largeSpacing * 2
		z: 4
		radius: Kirigami.Units.cornerRadius
		color: Kirigami.Theme.neutralBackgroundColor

		RowLayout {
			id: dropNoticeRow
			anchors.horizontalCenter: parent.horizontalCenter
			anchors.verticalCenter: parent.verticalCenter
			width: parent.width - Kirigami.Units.largeSpacing * 2
			spacing: Kirigami.Units.largeSpacing

			Label {
				id: dropNoticeLabel
				Layout.fillWidth: true
				text: pane.dropNoticeText
				color: Kirigami.Theme.neutralTextColor
				wrapMode: Text.WordWrap
			}

			ToolButton {
				icon.name: "dialog-close"
				onClicked: {
					pane.dropNoticeText = ""
					dropNoticeTimer.stop()
				}
			}
		}
	}

}
