mod config_parser;
mod file_manager;
mod directory;
mod config;
mod desktop_entry;

use crate::file_manager::FileManager;
use crate::directory::Directory;
use crate::config::Config;
use qmetaobject::prelude::*;

fn main() {
	const IMPORT_NAME: &'static core::ffi::CStr = c"Hishell";

	// Accept an optional path argument
	let args: Vec<String> = std::env::args().collect();
	let initial_path = if args.len() > 1 {
		// Resolve to absolute path
		let p = std::path::Path::new(&args[1]);
		if p.is_absolute() {
			args[1].clone()
		} else {
			std::env::current_dir()
				.map(|cwd| cwd.join(p).to_string_lossy().to_string())
				.unwrap_or_else(|_| args[1].clone())
		}
	} else {
		std::env::current_dir()
			.map(|cwd| cwd.to_string_lossy().to_string())
			.unwrap_or_else(|_| ".".to_string())
	};

	qmetaobject::qml_register_type::<Config>(IMPORT_NAME, 1, 0, c"Config");
	qmetaobject::qml_register_type::<Directory>(IMPORT_NAME, 1, 0, c"Directory");
	qmetaobject::qml_register_type::<FileManager>(IMPORT_NAME, 1, 0, c"FileManager");

	let mut engine = QmlEngine::new();
	engine.set_property(
		"initialPath".into(),
		QVariant::from(QString::from(initial_path.as_str())),
	);
	engine.load_file("qml/main.qml".into());
	engine.exec();
}
