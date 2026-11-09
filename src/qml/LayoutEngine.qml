import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "toolkit"

RowLayout {
	id: engine

	property string layoutString: "[]"
	property var window: null
	property string role: "middle"

	property var created: []
	property var pathBarItem: null

	Component { id: paneComponent; FolderPane {} }
	Component { id: pathBarComponent; PathBar {} }
	Component { id: menuBarComponent; MenuBar {} }
	Component { id: spacerComponent; Spacer {} }
	Component { id: windowControlComponent; WindowControl {} }

	Component.onCompleted: rebuild()
	onLayoutStringChanged: rebuild()

	function clear() {
		for (let i = 0; i < engine.created.length; i++)
			engine.created[i].destroy()
		engine.created = []
	}

	function add(entry, paneIndex) {
		let item = null
		if (entry === "." || entry === "./") {
			item = paneComponent.createObject(engine, {
				"window": engine.window,
				"directory": engine.window.paneDirectory(paneIndex)
			})
			if (item) {
				const pane = item
				item.active = Qt.binding(function () {
					return engine.window.activePane === pane
				})
				item.activated.connect(function () {
					engine.window.activePane = pane
				})
				item.focusEdge.connect(function (direction) {
					engine.window.switchPane(direction)
				})
				engine.window.registerPane(item)
			}
		} else if (entry === "toolkit/PathBar") {
			item = pathBarComponent.createObject(engine, { "window": engine.window })
			engine.pathBarItem = item
		} else if (entry === "toolkit/MenuBar") {
			item = menuBarComponent.createObject(engine, { "window": engine.window })
		} else if (entry === "toolkit/Spacer") {
			item = spacerComponent.createObject(engine, {})
		} else if (entry === "toolkit/WindowControl") {
			item = windowControlComponent.createObject(engine, { "window": engine.window })
		}
		if (item)
			engine.created.push(item)
	}

	function rebuild() {
		engine.clear()
		if (engine.role === "middle" && engine.window)
			engine.window.clearPanes()

		let entries = []
		try {
			const parsed = JSON.parse(engine.layoutString)
			if (Array.isArray(parsed))
				entries = parsed
		} catch (error) {
			entries = []
		}

		let paneIndex = 0
		for (let i = 0; i < entries.length; i++) {
			const entry = String(entries[i])
			engine.add(entry, paneIndex)
			if (entry === "." || entry === "./")
				paneIndex += 1
		}
		if (engine.role === "middle" && engine.window) {
			if (!engine.window.activePane && engine.window.panes.length > 0)
				engine.window.activePane = engine.window.panes[0]
			if (engine.window.activePane)
				engine.window.activePane.focusFirst()
		}
	}
}
