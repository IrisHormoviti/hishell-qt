mod config_parser;
mod file_manager;
mod directory;
mod config;
mod desktop_entry;
mod thumbnailer;

use crate::file_manager::FileManager;
use crate::directory::Directory;
use crate::config::Config;
use qmetaobject::prelude::*;
use std::ffi::CStr;

fn main() {
	static IMPORT_NAME: &CStr = unsafe { CStr::from_bytes_with_nul_unchecked(b"Hishell\0") };
	static CONFIG_STR: &CStr = unsafe { CStr::from_bytes_with_nul_unchecked(b"Config\0") };
	static DIRECTORY_STR: &CStr = unsafe { CStr::from_bytes_with_nul_unchecked(b"Directory\0") };
	static FILEMANAGER_STR: &CStr = unsafe { CStr::from_bytes_with_nul_unchecked(b"FileManager\0") };

	let args: Vec<String> = std::env::args().collect();
	fn percent_decode(input: &str) -> String {
		let mut out = String::with_capacity(input.len());
		let bytes = input.as_bytes();
		let mut i = 0;
		while i < bytes.len() {
			if bytes[i] == b'%' && i + 2 < bytes.len() {
				if let (Some(h), Some(l)) = (hex_char(bytes[i+1]), hex_char(bytes[i+2])) {
					out.push((h*16 + l) as char);
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

	let initial_path = if args.len() > 1 {
		let mut arg = args[1].clone();
		// handle file:// URIs
		if arg.starts_with("file://") {
			let rest = &arg[7..];
			let decoded = percent_decode(rest);
			arg = decoded;
		}
		// Resolve to absolute path
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

	qmetaobject::qml_register_type::<Config>(IMPORT_NAME, 1, 0, CONFIG_STR);
	qmetaobject::qml_register_type::<Directory>(IMPORT_NAME, 1, 0, DIRECTORY_STR);
	qmetaobject::qml_register_type::<FileManager>(IMPORT_NAME, 1, 0, FILEMANAGER_STR);

	let mut engine = QmlEngine::new();
	engine.set_property(
		"initialPath".into(),
		QVariant::from(QString::from(initial_path.as_str())),
	);
	// locate QML entry file from several candidate locations so the app
	// works regardless of the current working directory.
	fn find_qml() -> Option<std::path::PathBuf> {
		// search strategy:
		// 1) cwd/qml/main.qml
		// 2) walk up from the executable directory checking ancestor/qml/main.qml
		// 3) some common install locations
		let cwd = std::env::current_dir().ok();
		if let Some(c) = cwd {
			let p = c.join("qml/main.qml");
			if p.exists() { return Some(std::fs::canonicalize(&p).unwrap_or_else(|_| p.clone())); }
		}

		if let Ok(mut dir) = std::env::current_exe().and_then(|e| e.parent().map(|p| p.to_path_buf()).ok_or(std::io::Error::new(std::io::ErrorKind::Other, "no parent"))) {
			// check this dir and up to 5 parents
			for _ in 0..6 {
				let candidate = dir.join("qml/main.qml");
				if candidate.exists() { return Some(std::fs::canonicalize(candidate).unwrap_or_else(|_| dir.join("qml/main.qml"))); }
				if let Some(p) = dir.parent() { dir = p.to_path_buf(); } else { break; }
			}
		}

		let sys_candidates = [
			std::path::PathBuf::from("/usr/share/hishell-qt/qml/main.qml"),
			std::path::PathBuf::from("/usr/share/hishell-qt/main.qml"),
			std::path::PathBuf::from("/usr/share/qml/hishell-qt/main.qml"),
		];
		for c in sys_candidates.iter() {
			if c.exists() { return Some(std::fs::canonicalize(c).unwrap_or_else(|_| c.clone())); }
		}

		None
	}

	if let Some(qml_path) = find_qml() {
		println!("loading QML from {}", qml_path.display());
		engine.load_file(qml_path.to_string_lossy().to_string().into());
	} else {
		// fallback to packaged relative path; this will likely fail but keeps previous behavior
		engine.load_file("qml/main.qml".into());
	}
	engine.exec();
}
