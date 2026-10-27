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

	function beginBench() {
		if (benchmark.mode === 4) {
			grabTimer.start();
			return;
		}
		if (benchmark.mode === 5) {
			infoStartTimer.start();
			return;
		}
		benchmark.schedule(2000);
	}
}
