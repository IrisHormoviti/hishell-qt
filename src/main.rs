mod bridge;
mod config;
mod config_parser;
mod desktop_entry;
mod directory;
mod dragdrop_handler;
mod drop_validator;
mod file_manager;
mod image_utils;
mod path_utils;
mod portal;
mod selection_manager;
mod thumbnailer;

pub use config::ConfigRust;
pub use directory::DirectoryRust;
pub use dragdrop_handler::DragDropHandlerRust;
pub use drop_validator::DropValidatorRust;
pub use file_manager::FileManagerRust;
pub use path_utils::PathUtils;
pub use selection_manager::SelectionManagerRust;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QString, QUrl};

fn percent_decode(input: &str) -> String {
	let mut out = String::with_capacity(input.len());
	let bytes = input.as_bytes();
	let mut i = 0;
	while i < bytes.len() {
		if bytes[i] == b'%' && i + 2 < bytes.len() {
			if let (Some(h), Some(l)) = (hex_char(bytes[i + 1]), hex_char(bytes[i + 2])) {
				out.push((h * 16 + l) as char);
				i += 3;
				continue;
			}
		}
		out.push(bytes[i] as char);
		i += 1;
	}
	out
}

fn hex_char(b: u8) -> Option<u8> {
	match b {
		b'0'..=b'9' => Some(b - b'0'),
		b'a'..=b'f' => Some(b - b'a' + 10),
		b'A'..=b'F' => Some(b - b'A' + 10),
		_ => None,
	}
}

fn main() {
	let args: Vec<String> = std::env::args().collect();

	let initial_path = if args.len() > 1 {
		let mut arg = args[1].clone();
		if arg.starts_with("file://") {
			arg = percent_decode(&arg[7..]);
		}
		if arg == "~" || arg.starts_with("~/") {
			if let Ok(home) = std::env::var("HOME") {
				if arg == "~" {
					arg = home;
				} else {
					arg = format!("{}{}", home, &arg[1..]);
				}
			}
		}
		let p = std::path::Path::new(&arg);
		if p.is_absolute() {
			arg
		} else {
			std::env::current_dir()
				.map(|cwd| cwd.join(p).to_string_lossy().to_string())
				.unwrap_or_else(|_| arg)
		}
	} else {
		std::env::current_dir()
			.map(|cwd| cwd.to_string_lossy().to_string())
			.unwrap_or_else(|_| ".".to_string())
	};

	println!("startup initial_path={}", initial_path);

	let mut app = QGuiApplication::new();
	let mut engine = QQmlApplicationEngine::new();

	// Expose initial path to QML via context property
	let name = QString::from("initialPath");
	let value = QString::from(initial_path.as_str());
	if let Some(engine_pin) = engine.as_mut() {
		bridge::ffi::set_context_property(engine_pin, &name, &value);
	}

	// Load QML entry point
	let main_qml = "Hishell/ShellWindow.qml";
	let qml_path = std::path::Path::new(main_qml);
	let url = if qml_path.exists() {
		let abs = std::fs::canonicalize(qml_path).unwrap_or_else(|_| qml_path.to_path_buf());
		format!("file://{}", abs.display())
	} else {
		format!("file://{}/{}", std::env::current_dir().unwrap_or_default().display(), main_qml)
	};

	if let Some(engine_pin) = engine.as_mut() {
		engine_pin.load(&QUrl::from(url.as_str()));
	}

	if let Some(app_pin) = app.as_mut() {
		app_pin.exec();
	}
}
