//! hishell-qt as a library, so a host process can load the file manager into a
//! process it owns.
//!
//! The standalone binary ([`src/main.rs`]) and a host both call [`install`],
//! [`setup_process`] and [`load`]; the difference is only who creates the QML
//! engine and calls `exec()`. Nothing here knows about the host, or about the
//! device it runs on: the app is handed an engine and a path, and that is all.

pub mod appimage;
pub mod config;
pub mod config_parser;
pub mod descriptor_generator;
pub mod desktop_entry;
pub mod destroy;
pub mod directory;
pub mod directory_descriptor;
pub mod dragdrop_handler;
pub mod drop_validator;
pub mod file_manager;
pub mod focus_manager;
pub mod gamepad;
pub mod image_utils;
pub mod kde_bridge;
pub mod launch;
pub mod path_utils;
pub mod selection_manager;
pub mod session;
pub mod sound;
pub mod squashfs;
pub mod thumbnailer;

use qmetaobject::prelude::*;
use std::ffi::CStr;

use crate::config::Config;
use crate::directory::Directory;
use crate::dragdrop_handler::DragDropHandler;
use crate::drop_validator::DropValidator;
use crate::file_manager::FileManager;
use crate::focus_manager::FocusManager;
use crate::path_utils::PathUtils;
use crate::selection_manager::SelectionManager;

/// The QML root that draws the file manager.
pub const ROOT_QML: &str = "qrc:///Hishell/ShellWindow.qml";

/// The QML root that draws the crash-recovery prompt.
pub const RECOVERY_QML: &str = "qrc:///Hishell/Recovery.qml";

/// The QML import path the app's resources live under.
pub const IMPORT_PATH: &str = "qrc:///";

/// Register the app's QObject types and its QML resources.
///
/// Call once per process, before [`load`]. A host that installs several apps
/// into one engine calls this for each of them before creating any window.
pub fn install() {
	// Make sure Qt's messages (QML load errors included) reach stderr, so a
	// failed view is visible in the host's log.
	kde_bridge::install_message_handler();

	static IMPORT_NAME: &CStr = unsafe { CStr::from_bytes_with_nul_unchecked(b"Hishell\0") };
	static CONFIG_STR: &CStr = unsafe { CStr::from_bytes_with_nul_unchecked(b"Config\0") };
	static DIRECTORY_STR: &CStr = unsafe { CStr::from_bytes_with_nul_unchecked(b"Directory\0") };
	static FILEMANAGER_STR: &CStr =
		unsafe { CStr::from_bytes_with_nul_unchecked(b"FileManager\0") };
	static DRAGDROPHANDLER_STR: &CStr =
		unsafe { CStr::from_bytes_with_nul_unchecked(b"DragDropHandler\0") };
	static DROPVALIDATOR_STR: &CStr =
		unsafe { CStr::from_bytes_with_nul_unchecked(b"DropValidator\0") };
	static PATHUTILS_STR: &CStr = unsafe { CStr::from_bytes_with_nul_unchecked(b"PathUtils\0") };
	static SELECTIONMANAGER_STR: &CStr =
		unsafe { CStr::from_bytes_with_nul_unchecked(b"SelectionManager\0") };
	static FOCUSMANAGER_STR: &CStr =
		unsafe { CStr::from_bytes_with_nul_unchecked(b"FocusManager\0") };
	static SOUND_STR: &CStr = unsafe { CStr::from_bytes_with_nul_unchecked(b"Sound\0") };

	qmetaobject::qml_register_type::<Config>(IMPORT_NAME, 1, 0, CONFIG_STR);
	qmetaobject::qml_register_type::<Directory>(IMPORT_NAME, 1, 0, DIRECTORY_STR);
	qmetaobject::qml_register_type::<FileManager>(IMPORT_NAME, 1, 0, FILEMANAGER_STR);
	qmetaobject::qml_register_type::<DragDropHandler>(IMPORT_NAME, 1, 0, DRAGDROPHANDLER_STR);
	qmetaobject::qml_register_type::<DropValidator>(IMPORT_NAME, 1, 0, DROPVALIDATOR_STR);
	qmetaobject::qml_register_type::<PathUtils>(IMPORT_NAME, 1, 0, PATHUTILS_STR);
	qmetaobject::qml_register_type::<SelectionManager>(IMPORT_NAME, 1, 0, SELECTIONMANAGER_STR);
	qmetaobject::qml_register_type::<FocusManager>(IMPORT_NAME, 1, 0, FOCUSMANAGER_STR);
	qmetaobject::qml_register_type::<sound::Sound>(IMPORT_NAME, 1, 0, SOUND_STR);

	qmetaobject::qrc!(load_qml_resources,
		"Hishell" as "Hishell" {
			"qmldir",
			"plugins.qmltypes",
			"ActionGroupMenu.qml",
			"ActionManager.qml",
			"CoreTheme.qml",
			"DragTooltip.qml",
			"DragPreview.qml",
			"DestroyConfirmDialog.qml",
			"ExecuteDialog.qml",
			"FileSlot.qml",
			"FocusBorder.qml",
			"FolderFilterBar.qml",
			"FolderGrid.qml",
			"FolderSelectionBar.qml",
			"FolderView.qml",
			"LayoutEngine.qml",
			"LaunchConfirmDialog.qml",
			"OpenWithDialog.qml",
			"Recovery.qml",
			"ShellContextMenu.qml",
			"ShellWindow.qml",
			"StyleThemeBridge.qml",
			"WindowOverlay.qml",
			"toolkit/qmldir" as "toolkit/qmldir",
			"toolkit/MenuBar.qml" as "toolkit/MenuBar.qml",
			"toolkit/PathBar.qml" as "toolkit/PathBar.qml",
			"toolkit/Spacer.qml" as "toolkit/Spacer.qml",
			"toolkit/ViewActions.qml" as "toolkit/ViewActions.qml",
			"toolkit/ViewButton.qml" as "toolkit/ViewButton.qml",
			"toolkit/ViewDialog.qml" as "toolkit/ViewDialog.qml",
			"toolkit/ViewMenu.qml" as "toolkit/ViewMenu.qml",
			"toolkit/ViewSlider.qml" as "toolkit/ViewSlider.qml",
			"toolkit/WindowControl.qml" as "toolkit/WindowControl.qml",
		}
	);

	load_qml_resources();
}

/// One-time process wiring the app needs before its window exists: the menu-key
/// hook, touch-hover suppression, the icon warm-up and the gamepad.
///
/// Separate from [`install`] so a host can install every app's types first and
/// do this once, when the process is otherwise ready. Must run *after* the QML
/// engine (and with it the Qt application) exists: warming the action icons
/// builds `QPixmap`s, which Qt refuses before an application is up.
pub fn setup_process() {
	kde_bridge::hook_menu_key();
	kde_bridge::suppress_touch_hover();
	kde_bridge::warm_icons();
	gamepad::init();
}

/// Point the engine at the app's QML and give it the folder to open.
pub fn load(engine: &mut QmlEngine, initial_path: &str) {
	engine.set_property(
		"initialPath".into(),
		QVariant::from(QString::from(initial_path)),
	);
	engine.add_import_path(IMPORT_PATH.into());
	engine.load_file(ROOT_QML.into());
}

/// Load the crash-recovery prompt instead of the file manager.
///
/// Shares the QML import path with [`load`] but nothing else: the prompt does
/// not touch the file manager's objects, so it survives whatever state the
/// crashed process left behind.
pub fn load_recovery(engine: &mut QmlEngine) {
	engine.add_import_path(IMPORT_PATH.into());
	engine.load_file(RECOVERY_QML.into());
}
