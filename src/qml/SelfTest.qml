import QtQuick
import hishell_qt

Item {
	id: test

	required property var leftDirectory
	required property var rightDirectory
	required property var testBridge

	property int step: 0
	property bool done: false
	property string gamepadBefore: ""
	property string root: testBridge.root
	property string dir: test.root + "/dir"
	property string child: test.dir + "/child"

	Main {
		id: main
		leftDirectory: test.leftDirectory
		rightDirectory: test.rightDirectory
	}

	Timer {
		interval: 450
		repeat: true
		running: !test.done
		onTriggered: test.next()
	}

	function check(name, ok, message) {
		if (ok)
			test.testBridge.pass(name)
		else
			test.testBridge.fail(name, message || "failed")
	}

	function pane() {
		return main ? main.leftPane : null
	}

	function next() {
		try {
			test.runStep()
		} catch (error) {
			test.testBridge.fail("step " + test.step, String(error))
		}
		test.step += 1
	}

	function runStep() {
		switch (test.step) {
		case 0:
			test.check("initial items", test.leftDirectory.item_count() >= 4,
				"expected at least four items")
			test.leftDirectory.focus_path(test.dir + "/a.txt")
			test.leftDirectory.invoke("rename")
			break
		case 1: {
			const left = test.pane()
			test.check("rename dialog", left ? left.renameDialogOpen : false)
			if (left)
				left.closeDialogs()
			test.check("rename submitted", test.leftDirectory.rename(test.dir + "/a.txt", "renamed.txt"))
			break
		}
		case 2:
			test.check("rename applied", test.testBridge.exists(test.dir + "/renamed.txt"))
			test.leftDirectory.focus_path(test.dir + "/renamed.txt")
			test.leftDirectory.invoke("trash")
			break
		case 3: {
			const left = test.pane()
			test.check("trash dialog", left ? left.trashDialogOpen : false)
			if (left)
				left.closeDialogs()
			test.check("trash submitted",
				test.leftDirectory.trash(JSON.stringify([test.dir + "/renamed.txt"]), false))
			break
		}
		case 4:
			test.check("trash applied", !test.testBridge.exists(test.dir + "/renamed.txt"))
			test.leftDirectory.focus_path(test.dir + "/keep.txt")
			test.leftDirectory.invoke("open-with")
			break
		case 5: {
			const left = test.pane()
			test.check("open-with dialog", left ? left.openWithDialogOpen : false)
			if (left)
				left.closeDialogs()
			test.check("drop submitted",
				test.leftDirectory.drop("file://" + test.dir + "/keep.txt", test.child, "copy"))
			break
		}
		case 6:
			test.check("drop applied", test.testBridge.exists(test.child + "/keep.txt"))
			main.testMiddleLayout = '["./", "./"]'
			break
		case 7:
			test.check("two panes", main.panes.length === 2)
			main.activePane = main.leftPane
			main.switchPane("right")
			break
		case 8:
			test.check("pane hand-off", main.activePane === main.rightPane)
			main.activePane = main.leftPane
			test.check("navigate submitted", test.leftDirectory.navigate(test.child))
			break
		case 9:
			test.check("transition rendered", main.leftPane.transitionDirection.length > 0)
			test.check("navigate applied", test.leftDirectory.path === test.child)
			test.leftDirectory.go_up()
			break
		case 10:
			test.check("go up applied", test.leftDirectory.path === test.dir)
			test.leftDirectory.focus_first()
			test.gamepadBefore = test.leftDirectory.focused_path
			main.leftPane.handleGamepad("right")
			break
		case 11:
			test.check("gamepad moved focus",
				test.leftDirectory.focused_path !== test.gamepadBefore)
			test.leftDirectory.select(test.dir + "/b.txt")
			break
		case 12:
			test.check("click selects one", test.leftDirectory.selectedCount === 1
				&& test.leftDirectory.is_selected(test.dir + "/b.txt"))
			test.leftDirectory.toggle_select(test.dir + "/c.txt")
			break
		case 13:
			test.check("ctrl-click adds", test.leftDirectory.selectedCount === 2)
			test.leftDirectory.clear_selection()
			break
		case 14:
			test.check("clear selection", test.leftDirectory.selectedCount === 0)
			test.done = true
			Qt.quit()
			break
		}
	}
}
