// Development-only frame benchmark.
//
// Loaded by ShellWindow when `FileManager.perf_mode()` is non-zero (the
// HISHELL_PERF environment variable or a /home/.config/clam/perf marker). It
// drives the view through the interactions that used to stutter — opening a
// folder of ROMs, scrolling it, the settings list, the folder menu and a
// context menu — and logs frame counts and frame-gap outliers to the shell
// log. Nothing here runs in a normal boot.

import QtQuick
import Hishell

Item {
	id: benchmark

	property var win
	property int mode: win && win.fileManager ? win.fileManager.perf_mode() : 0
	property bool collecting: false
	property int frames: 0
	property int slow20: 0
	property int slow33: 0
	property real maxGap: 0
	property real lastFrame: 0
	property real phaseStart: 0
	property string phase: ""
	property int stepIndex: 0

	function now() {
		return Date.now();
	}

	function logLine(kind, message) {
		if (benchmark.win && benchmark.win.fileManager)
			benchmark.win.fileManager.perf_log(String(kind) + " " + String(message));
	}

	Connections {
		target: benchmark.win
		function onFrameSwapped() {
			const t = benchmark.now();
			if (benchmark.collecting && benchmark.lastFrame > 0) {
				const gap = t - benchmark.lastFrame;
				if (gap > benchmark.maxGap)
					benchmark.maxGap = gap;
				if (gap > 34)
					benchmark.slow33++;
				else if (gap > 20)
					benchmark.slow20++;
			}
			benchmark.lastFrame = t;
			if (benchmark.collecting)
				benchmark.frames++;
		}
	}

	function begin(name) {
		benchmark.phase = name;
		benchmark.frames = 0;
		benchmark.slow20 = 0;
		benchmark.slow33 = 0;
		benchmark.maxGap = 0;
		benchmark.lastFrame = 0;
		benchmark.phaseStart = benchmark.now();
		benchmark.collecting = true;
		benchmark.logLine("phase-start", name);
	}

	function end() {
		if (!benchmark.collecting)
			return;
		benchmark.collecting = false;
		const ms = benchmark.now() - benchmark.phaseStart;
		const fps = ms > 0 ? benchmark.frames * 1000 / ms : 0;
		benchmark.logLine("phase", benchmark.phase
			+ " frames=" + benchmark.frames
			+ " ms=" + Math.round(ms)
			+ " fps=" + fps.toFixed(1)
			+ " slow20=" + benchmark.slow20
			+ " slow33=" + benchmark.slow33
			+ " maxgap=" + Math.round(benchmark.maxGap));
	}

	function schedule(ms) {
		stepTimer.interval = ms;
		stepTimer.restart();
	}

	function scrollView(view, toEnd, ms) {
		if (!view)
			return;
		const flick = view.flickable;
		if (!flick)
			return;
		const horizontal = view.horizontalScroll;
		scrollAnim.stop();
		scrollAnim.target = flick;
		scrollAnim.property = horizontal ? "contentX" : "contentY";
		const span = horizontal ? flick.contentWidth - flick.width : flick.contentHeight - flick.height;
		scrollAnim.from = horizontal ? flick.contentX : flick.contentY;
		scrollAnim.to = toEnd ? Math.max(0, span) : 0;
		scrollAnim.duration = ms;
		scrollAnim.easing.type = Easing.InOutQuad;
		scrollAnim.start();
	}

	function navigate(path) {
		const view = benchmark.win ? benchmark.win.primaryFolderView : null;
		if (view)
			view.directory.path = path;
	}

	function step() {
		const view = benchmark.win ? benchmark.win.primaryFolderView : null;
		switch (benchmark.stepIndex++) {
		case 0:
			benchmark.begin("idle");
			benchmark.schedule(2500);
			break;
		case 1:
			benchmark.end();
			benchmark.begin("open-big");
			benchmark.navigate("/mnt/sdcard/ROMS");
			benchmark.schedule(2500);
			break;
		case 2:
			benchmark.end();
			benchmark.begin("scroll-big-down");
			benchmark.scrollView(view, true, 3500);
			benchmark.schedule(4000);
			break;
		case 3:
			benchmark.end();
			benchmark.begin("scroll-big-up");
			benchmark.scrollView(view, false, 3500);
			benchmark.schedule(4000);
			break;
		case 4:
			benchmark.end();
			benchmark.begin("open-settings");
			benchmark.navigate("/home/settings");
			benchmark.schedule(1500);
			break;
		case 5:
			benchmark.end();
			benchmark.begin("folder-menu");
			if (view)
				view.openDirectoryMenu();
			benchmark.schedule(1500);
			break;
		case 6:
			benchmark.end();
			if (view && view.openMenu)
				view.openMenu.close();
			benchmark.schedule(600);
			break;
		case 7:
			benchmark.end();
			benchmark.begin("context-menu");
			if (view) {
				const slot = view.slotAt(0);
				if (slot)
					slot.openContextMenu();
			}
			benchmark.schedule(1500);
			break;
		case 8:
			benchmark.end();
			if (view) {
				const slot = view.slotAt(0);
				if (slot && slot.contextMenu)
					slot.contextMenu.close();
			}
			benchmark.schedule(600);
			break;
		case 9:
			benchmark.end();
			benchmark.begin("open-home");
			benchmark.navigate("/home");
			benchmark.schedule(2000);
			break;
		case 10:
			benchmark.end();
			benchmark.begin("scroll-home");
			benchmark.scrollView(view, true, 2500);
			benchmark.schedule(3000);
			break;
		default:
			benchmark.end();
			benchmark.logLine("done", "benchmark complete");
			break;
		}
	}

	NumberAnimation {
		id: scrollAnim
		target: null
		property: "contentY"
	}

	Timer {
		id: stepTimer
		interval: 2000
		repeat: false
		onTriggered: benchmark.step()
	}

	// Mode 4: render one frame to a PNG and quit. Used on the host to inspect
	// a layout without a display.
	Timer {
		id: grabTimer
		interval: 1800
		repeat: false
		onTriggered: {
			if (!benchmark.win)
				return;
			const item = benchmark.win.pageStack && benchmark.win.pageStack.currentItem
				? benchmark.win.pageStack.currentItem
				: benchmark.win.contentItem;
			item.grabToImage(function (result) {
				result.saveToFile("/tmp/hishell-grab.png");
				Qt.quit();
			});
		}
	}

	// Mode 5: open the System Info folder (six Type=Button rows) and walk the
	// cursor through it, logging the per-move GUI-thread time. Used to keep
	// focus-move cost honest without a display.
	function focusStep(direction) {
		const view = benchmark.win ? benchmark.win.primaryFolderView : null;
		const fm = view ? view.focusManager : null;
		if (!fm)
			return;
		const started = benchmark.now();
		fm.move_focus(direction);
		benchmark.logLine("focus-move", (benchmark.now() - started) + "ms "
			+ direction + " " + String(fm.focused_path));
	}

	function startInfoBench() {
		benchmark.begin("info-open");
		benchmark.navigate("/home/settings/System/Info");
		benchmark.logLine("info-path", String(benchmark.win.primaryFolderView.directory.path));
		infoStepTimer.interval = 2000;
		infoStepTimer.start();
	}

	// Wait for ShellWindow to hand the loaded window its primary view; before
	// that `navigate` has nowhere to go and the benchmark would run on /home.
	Timer {
		id: infoStartTimer
		interval: 500
		repeat: false
		onTriggered: benchmark.startInfoBench()
	}

	Timer {
		id: infoStepTimer
		repeat: false
		property int moves: 0
		property bool walking: false
		onTriggered: {
			const view = benchmark.win ? benchmark.win.primaryFolderView : null;
			if (!view)
				return;
			if (!benchmark.focusWalking) {
				// The folder has opened. Park the cursor on a known item and
				// start walking.
				benchmark.end();
				const fm = view.focusManager;
				const started = benchmark.now();
				fm.focus_first();
				benchmark.logLine("focus-first", (benchmark.now() - started) + "ms");
				benchmark.begin("info-focus");
				benchmark.focusWalking = true;
				infoStepTimer.moves = 0;
				infoStepTimer.interval = 150;
				infoStepTimer.start();
				return;
			}
			benchmark.focusStep(infoStepTimer.moves % 2 === 0 ? "right" : "left");
			infoStepTimer.moves++;
			if (infoStepTimer.moves >= 8) {
				benchmark.focusWalking = false;
				benchmark.end();
				benchmark.logLine("done", "info focus benchmark complete");
				return;
			}
			infoStepTimer.start();
		}
	}

	property bool focusWalking: false

	// Mode 6: the animated navigation the user actually performs. Opening a
	// folder at the top of the filesystem is compared with opening folders
	// under /home, with the frame gaps of each motion logged alongside the
	// step timings FolderView writes.
	property var navPlan: []
	property int navPlanIndex: 0
	property var navEntry: null
	property string navLabel: ""
	property double navStarted: 0

	// Diagnostic for the launch transition: it grabs the focused slot's
	// contentBody. Log what a launch would grab so the path can be checked
	// without controller input.
	function checkLaunchGrab() {
		const view = benchmark.win ? benchmark.win.primaryFolderView : null;
		if (!view) {
			navStartTimer.restart();
			return;
		}
		const slot = view.slotAt(0);
		const body = slot ? slot.contentBody : null;
		benchmark.logLine("grab", "slot=" + (slot ? "yes" : "no")
			+ " ready=" + (slot ? String(slot.populateReady) : "-")
			+ " body=" + (body ? Math.round(body.width) + "x" + Math.round(body.height) : "null"));
		if (body)
			body.grabToImage(result => benchmark.logLine("grab",
				"url=" + (result && result.url ? "ok" : "null")));
	}

	function startNavBench() {
		benchmark.navPlan = [
			{ from: "/", to: "/usr", label: "open-usr" },
			{ from: "/usr", to: "/", label: "close-usr" },
			{ from: "/", to: "/etc", label: "open-etc" },
			{ from: "/etc", to: "/", label: "close-etc" },
			{ from: "/", to: "/home", label: "open-home" },
			{ from: "/home", to: "/", label: "close-home" },
			{ from: "/home", to: "/home/Games", label: "open-games" },
			{ from: "/home/Games", to: "/home", label: "close-games" },
			{ from: "/home", to: "/home/sdcard", label: "open-sdcard" },
			{ from: "/home/sdcard", to: "/home", label: "close-sdcard" },
			{ from: "/home", to: "/home/save", label: "open-save" },
			{ from: "/home/save", to: "/home", label: "close-save" }
		];
		benchmark.navPlanIndex = 0;
		navGrabTimer.start();
	}

	function runNavPlan() {
		if (benchmark.navPlanIndex >= benchmark.navPlan.length) {
			benchmark.logLine("nav", "bench complete");
			return;
		}
		const view = benchmark.win ? benchmark.win.primaryFolderView : null;
		if (!view) {
			navStartTimer.restart();
			return;
		}
		benchmark.navEntry = benchmark.navPlan[benchmark.navPlanIndex++];
		view.directory.path = benchmark.navEntry.from;
		navSettleTimer.restart();
	}

	Timer {
		id: navStartTimer
		interval: 500
		repeat: false
		onTriggered: benchmark.runNavPlan()
	}

	Timer {
		id: navGrabTimer
		interval: 1200
		repeat: false
		onTriggered: {
			benchmark.checkLaunchGrab();
			benchmark.runNavPlan();
		}
	}

	Timer {
		id: navSettleTimer
		interval: 900
		repeat: false
		onTriggered: {
			const view = benchmark.win ? benchmark.win.primaryFolderView : null;
			if (!view || !benchmark.navEntry)
				return;
			benchmark.navLabel = benchmark.navEntry.label;
			benchmark.navStarted = benchmark.now();
			benchmark.begin(benchmark.navLabel);
			view.navigateToPath(benchmark.navEntry.to, null, false);
			navPollTimer.start();
		}
	}

	Timer {
		id: navPollTimer
		interval: 20
		repeat: true
		onTriggered: {
			const view = benchmark.win ? benchmark.win.primaryFolderView : null;
			if (view && view.navigationBusy)
				return;
			navPollTimer.stop();
			benchmark.logLine("nav", benchmark.navLabel + " visible "
				+ (benchmark.now() - benchmark.navStarted) + "ms");
			benchmark.end();
			navNextTimer.restart();
		}
	}

	Timer {
		id: navNextTimer
		interval: 300
		repeat: false
		onTriggered: benchmark.runNavPlan()
	}

	// Mode 8: trigger the real launch transition on the first file in the
	// current folder and capture the window while the ghost is on screen, so
	// the animation can be checked without controller input.
	property bool animTried: false

	function startAnimTest() {
		const view = benchmark.win ? benchmark.win.primaryFolderView : null;
		const am = benchmark.win ? benchmark.win.actionManager : null;
		if (!view || !am) {
			animStartTimer.restart();
			return;
		}
		if (benchmark.animTried) {
			benchmark.logLine("anim", "done");
			return;
		}
		benchmark.animTried = true;
		let index = -1;
		const paths = view.directory ? view.directory.get_all_paths() : [];
		for (let i = 0; i < paths.length; i++) {
			const slot = view.slotAt(i);
			if (slot && !slot.is_dir) {
				index = i;
				break;
			}
		}
		if (index < 0) {
			benchmark.logLine("anim", "no file in " + String(view.directory ? view.directory.path : ""));
			return;
		}
		view.focusSlot(String(view.slotAt(index).path), true);
		const slot = view.slotAt(index);
		benchmark.logLine("anim", "launch " + String(slot.path));
		am.activatePath(String(slot.path), slot);
		animGrab1.start();
		animGrab2.start();
	}

	Timer {
		id: animStartTimer
		interval: 2500
		repeat: false
		onTriggered: benchmark.startAnimTest()
	}

	Timer {
		id: animGrab1
		interval: 60
		repeat: false
		onTriggered: benchmark.capture("1")
	}

	Timer {
		id: animGrab2
		interval: 170
		repeat: false
		onTriggered: benchmark.capture("2")
	}

	function capture(tag) {
		if (!benchmark.win)
			return;
		// The launch ghost is parented to the window content with a very high z.
		// Read its state instead of grabbing the contentItem (C++-owned, so
		// grabToImage refuses it).
		const content = benchmark.win.contentItem;
		let ghost = null;
		for (let i = 0; i < content.children.length; i++) {
			const child = content.children[i];
			if (child && child.z >= 100000) {
				ghost = child;
				break;
			}
		}
		if (!ghost) {
			benchmark.logLine("anim", "ghost " + tag + " missing");
			return;
		}
		benchmark.logLine("anim", "ghost " + tag + " visible=" + ghost.visible
			+ " size=" + Math.round(ghost.width) + "x" + Math.round(ghost.height)
			+ " scale=" + ghost.scale.toFixed(2)
			+ " opacity=" + ghost.opacity.toFixed(2)
			+ " z=" + ghost.z);
	}

	function beginBench() {
		if (benchmark.mode === 4) {
			grabTimer.start();
			return;
		}
		if (benchmark.mode === 5) {
			infoStartTimer.start();
			return;
		}
		if (benchmark.mode === 6) {
			benchmark.startNavBench();
			return;
		}
		if (benchmark.mode === 7) {
			benchmark.startConfigProbe();
			return;
		}
		if (benchmark.mode === 8) {
			animStartTimer.start();
			return;
		}
		benchmark.schedule(2000);
	}

	// Mode 7: the cost of one view-config change with a folder on screen. A
	// folder whose view settings differ from the previous one made every live
	// delegate re-evaluate (and re-render its icon) when the new config was
	// announced; this isolates which setting is responsible. Runs in a folder
	// without its own .directory so the global config applies, and writes the
	// global file (removed again after the run).
	property int configProbeIndex: 0
	property var configProbes: [
		["ShowLabels", "false"], ["ShowLabels", "true"],
		["ScrollDirection", "HORIZONTAL"], ["ScrollDirection", "VERTICAL"],
		["Sort", "FREE"], ["Sort", "ALPHABETICAL"],
		["Group", "DATE"], ["Group", "NONE"],
		["Lines", "2"], ["Lines", "4"],
		["GridSize", "40"], ["GridSize", "72"],
		["StashDotFiles", "true"], ["StashDotFiles", "false"],
		["ShowStash", "true"], ["ShowStash", "false"],
		["GridVerticalAlign", "FILL"], ["GridVerticalAlign", "CENTER"],
		["GridLabelsBesidesIcons", "true"], ["GridLabelsBesidesIcons", "false"]
	]

	function startConfigProbe() {
		const view = benchmark.win ? benchmark.win.primaryFolderView : null;
		if (!view) {
			configStartTimer.restart();
			return;
		}
		view.directory.path = "/home/save";
		benchmark.configProbeIndex = 0;
		configProbeTimer.interval = 800;
		configProbeTimer.start();
	}

	Timer {
		id: configStartTimer
		interval: 500
		repeat: false
		onTriggered: benchmark.startConfigProbe()
	}

	Timer {
		id: configProbeTimer
		repeat: false
		onTriggered: {
			const view = benchmark.win ? benchmark.win.primaryFolderView : null;
			if (!view)
				return;
			if (benchmark.configProbeIndex >= benchmark.configProbes.length) {
				benchmark.logLine("probe", "done");
				return;
			}
			const probe = benchmark.configProbes[benchmark.configProbeIndex++];
			const started = benchmark.now();
			view.directory.set_config("Folder View", probe[0], probe[1], false);
			benchmark.logLine("probe", probe[0] + "=" + probe[1] + " "
				+ (benchmark.now() - started) + "ms");
			configProbeTimer.restart();
		}
	}
}
