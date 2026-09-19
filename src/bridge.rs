pub use crate::config::ConfigRust;
pub use crate::directory::DirectoryRust;
pub use crate::dragdrop_handler::DragDropHandlerRust;
pub use crate::drop_validator::DropValidatorRust;
pub use crate::file_manager::FileManagerRust;
pub use crate::path_utils::PathUtilsRust;
pub use crate::selection_manager::SelectionManagerRust;

#[cxx_qt::bridge]
pub mod ffi {
	unsafe extern "C++Qt" {
		include!(<QtCore/QAbstractListModel>);
		#[qobject]
		type QAbstractListModel;
	}

	unsafe extern "C++" {
		include!("cxx-qt-lib/qhash.h");
		type QHash_i32_QByteArray = cxx_qt_lib::QHash<cxx_qt_lib::QHashPair_i32_QByteArray>;

		include!("cxx-qt-lib/qvariant.h");
		type QVariant = cxx_qt_lib::QVariant;

		include!("cxx-qt-lib/qmodelindex.h");
		type QModelIndex = cxx_qt_lib::QModelIndex;

		include!("cxx-qt-lib/qstring.h");
		type QString = cxx_qt_lib::QString;

		include!("cxx-qt-lib/qstringlist.h");
		type QStringList = cxx_qt_lib::QStringList;

		include!("cxx-qt-lib/qurl.h");
		type QUrl = cxx_qt_lib::QUrl;

		include!("cxx-qt-lib/qqmlapplicationengine.h");
		type QQmlApplicationEngine = cxx_qt_lib::QQmlApplicationEngine;
	}

	extern "RustQt" {
		#[qobject]
		#[qml_element]
		#[qproperty(QString, title)]
		#[qproperty(QString, icon)]
		#[qproperty(QString, wallpaper)]
		#[qproperty(QString, top_layout)]
		#[qproperty(QString, middle_layout)]
		#[qproperty(QString, bottom_layout)]
		#[qproperty(QString, header_layout)]
		#[qproperty(u16, grid_size)]
		#[qproperty(bool, show_labels)]
		#[qproperty(u8, view_mode)]
		#[qproperty(u8, sort)]
		#[qproperty(u8, sort_date_mode)]
		#[qproperty(u8, sort_alpha_mode)]
		#[qproperty(bool, stash_shown)]
		#[qproperty(bool, stash_dotfiles)]
		#[qproperty(bool, arbitrary_placement)]
		#[qproperty(QString, arbitrary_positions)]
		type Config = super::ConfigRust;

		#[qsignal]
		#[cxx_name = "configChanged"]
		fn config_changed(self: Pin<&mut Config>);

		#[qinvokable]
		fn load(self: Pin<&mut Config>, path: &QString);

		#[qinvokable]
		fn set(
			self: Pin<&mut Config>,
			path: &QString,
			section: &QString,
			key: &QString,
			value: &QString,
			local: bool,
		);
	}

	extern "RustQt" {
		#[qobject]
		#[base = QAbstractListModel]
		#[qml_element]
		#[qproperty(*mut Config, config)]
		#[qproperty(QString, title)]
		#[qproperty(QString, icon)]
		#[qproperty(bool, has_meta)]
		#[qproperty(QString, path)]
		type Directory = super::DirectoryRust;

		#[qsignal]
		#[cxx_name = "requestExecutePrompt"]
		fn request_execute_prompt(self: Pin<&mut Directory>, path: &QString);

		#[inherit]
		#[cxx_name = "beginResetModel"]
		unsafe fn begin_reset_model(self: Pin<&mut Directory>);

		#[inherit]
		#[cxx_name = "endResetModel"]
		unsafe fn end_reset_model(self: Pin<&mut Directory>);

		#[qinvokable]
		#[cxx_override]
		#[cxx_name = "roleNames"]
		fn role_names(self: &Directory) -> QHash_i32_QByteArray;

		#[qinvokable]
		#[cxx_override]
		#[cxx_name = "rowCount"]
		fn row_count(self: &Directory, _parent: &QModelIndex) -> i32;

		#[qinvokable]
		#[cxx_override]
		fn data(self: &Directory, index: &QModelIndex, role: i32) -> QVariant;

		#[qinvokable]
		fn execute_file(self: &Directory, path: &QString);

		#[qinvokable]
		fn open_path(self: Pin<&mut Directory>, path: &QString);

		#[qinvokable]
		fn open_in_new_window(self: &Directory, path: &QString);

		#[qinvokable]
		fn poll_thumbnails(self: Pin<&mut Directory>);

		#[qinvokable]
		#[cxx_name = "setConfigValue"]
		fn set_config_value(
			self: Pin<&mut Directory>,
			section: &QString,
			key: &QString,
			value: &QString,
			local: bool,
		);

		#[qinvokable]
		fn reload(self: Pin<&mut Directory>);

		#[qinvokable]
		fn get_all_paths(self: &Directory) -> QStringList;

		#[qinvokable]
		fn load_directory(self: Pin<&mut Directory>, path: &QString, include_hidden: bool);
	}

	extern "RustQt" {
		#[qobject]
		#[qml_element]
		type FileManager = super::FileManagerRust;

		#[qinvokable]
		fn copy_file(self: &FileManager, source: &QString, dest: &QString) -> bool;

		#[qinvokable]
		fn duplicate_file(self: &FileManager, source: &QString) -> bool;

		#[qinvokable]
		fn new_folder(self: &FileManager, parent: &QString) -> bool;

		#[qinvokable]
		fn new_text_file(self: &FileManager, parent: &QString) -> bool;

		#[qinvokable]
		fn create_link(self: &FileManager, source: &QString, dest: &QString) -> bool;

		#[qinvokable]
		fn trash_file(self: &FileManager, path: &QString) -> bool;

		#[qinvokable]
		fn delete_file(self: &FileManager, path: &QString) -> bool;

		#[qinvokable]
		fn rename_file(self: &FileManager, path: &QString, new_name: &QString) -> bool;

		#[qinvokable]
		fn copy_paths_to_clipboard(self: &FileManager, paths_newline: &QString) -> bool;

		#[qinvokable]
		fn cut_paths_to_clipboard(self: &FileManager, paths_newline: &QString) -> bool;

		#[qinvokable]
		fn paste_from_clipboard(self: &FileManager, dest_dir: &QString) -> bool;

		#[qinvokable]
		fn get_mime_type(self: &FileManager, path: &QString) -> QString;

		#[qinvokable]
		fn get_text_content(self: &FileManager, path: &QString) -> QString;

		#[qinvokable]
		fn process_uris_action(
			self: &FileManager,
			dest_dir: &QString,
			uris_newline: &QString,
			action: &QString,
		) -> bool;

		#[qinvokable]
		fn open_file(self: &FileManager, path: &QString) -> bool;

		#[qinvokable]
		fn get_icon(self: &FileManager, path: &QString) -> QString;

		#[qinvokable]
		fn open_file_with_dialog(self: &FileManager, path: &QString) -> bool;

		#[qinvokable]
		fn rotate_image(self: &FileManager, path: &QString, degrees: i32) -> bool;

		#[qinvokable]
		fn is_image_file(self: &FileManager, path: &QString) -> bool;

		#[qinvokable]
		fn is_directory(self: &FileManager, path: &QString) -> bool;
	}

	extern "RustQt" {
		#[qobject]
		#[qml_element]
		#[qproperty(QString, drag_action)]
		#[qproperty(f64, drag_cursor_x)]
		#[qproperty(f64, drag_cursor_y)]
		#[qproperty(bool, tooltip_active)]
		#[qproperty(QStringList, active_dragged_paths)]
		#[qproperty(f64, drag_icon_width)]
		#[qproperty(f64, drag_icon_height)]
		#[qproperty(QStringList, drag_uris)]
		#[qproperty(QStringList, drag_source_paths)]
		#[qproperty(i32, item_count)]
		#[qproperty(QString, file_title)]
		#[qproperty(QString, file_icon)]
		#[qproperty(QVariant, dragged_slot)]
		#[qproperty(QString, shake_history_json)]
		#[qproperty(QVariant, window)]
		type DragDropHandler = super::DragDropHandlerRust;

		#[qsignal]
		#[cxx_name = "dragCursorChanged"]
		fn drag_cursor_changed(self: Pin<&mut DragDropHandler>);

		#[qinvokable]
		fn track_mouse_shake(self: Pin<&mut DragDropHandler>, x: f64, y: f64);

		#[qinvokable]
		fn cycle_drag_action(self: Pin<&mut DragDropHandler>);

		#[qinvokable]
		fn reset(self: Pin<&mut DragDropHandler>);

		#[qinvokable]
		fn set_drag_data(
			self: Pin<&mut DragDropHandler>,
			main_path: &QString,
			uris: &QStringList,
			source_paths: &QStringList,
			item_count: i32,
			file_title: &QString,
			file_icon: &QString,
		);

		#[qinvokable]
		fn begin_drag(
			self: Pin<&mut DragDropHandler>,
			image_url: &QString,
			width: f64,
			height: f64,
		);

		#[qinvokable]
		fn end_drag(self: Pin<&mut DragDropHandler>);
	}

	extern "RustQt" {
		#[qobject]
		#[qml_element]
		#[qproperty(QVariant, window)]
		type DropValidator = super::DropValidatorRust;

		#[qinvokable]
		fn is_drop_valid(
			self: &DropValidator,
			target_path: &QString,
			source_paths: &QStringList,
		) -> bool;
	}

	extern "RustQt" {
		#[qobject]
		#[qml_element]
		#[qproperty(QVariant, window)]
		type PathUtils = super::PathUtilsRust;

		#[qinvokable]
		fn get_segments(self: &PathUtils, path: &QString) -> QString;

		#[qinvokable]
		fn path_for_index(self: &PathUtils, current_path: &QString, idx: i32) -> QString;

		#[qinvokable]
		fn folder_name(self: &PathUtils, path: &QString) -> QString;

		#[qinvokable]
		fn normalize_path(self: &PathUtils, path: &QString) -> QString;

		#[qinvokable]
		fn parent_path(self: &PathUtils, path: &QString) -> QString;
	}

	extern "RustQt" {
		#[qobject]
		#[qml_element]
		#[qproperty(bool, selection_active)]
		#[qproperty(QString, selected_paths)]
		#[qproperty(i32, selected_count)]
		#[qproperty(i32, last_selected_index)]
		#[qproperty(QString, selection_status)]
		#[qproperty(QVariant, window)]
		type SelectionManager = super::SelectionManagerRust;

		#[qsignal]
		#[cxx_name = "selectionChanged"]
		fn selection_changed(self: Pin<&mut SelectionManager>);

		#[qinvokable]
		fn enter_selection_mode(self: Pin<&mut SelectionManager>);

		#[qinvokable]
		fn exit_selection_mode(self: Pin<&mut SelectionManager>);

		#[qinvokable]
		fn toggle_selection(self: Pin<&mut SelectionManager>, path: &QString, idx: i32);

		#[qinvokable]
		fn range_select(self: Pin<&mut SelectionManager>, from_idx: i32, to_idx: i32);

		#[qinvokable]
		fn select_all(self: Pin<&mut SelectionManager>, paths: &QStringList);

		#[qinvokable]
		fn deselect_all(self: Pin<&mut SelectionManager>);

		#[qinvokable]
		fn get_selected_path_list(self: &SelectionManager) -> QStringList;

		#[qinvokable]
		fn clear(self: Pin<&mut SelectionManager>);
	}
}

use cxx_qt::impl_transitive_cast;
use ffi::{Directory, QAbstractListModel, QObject};

impl_transitive_cast!(Directory, QAbstractListModel, QObject);