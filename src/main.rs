//! The standalone hishell-qt binary.
//!
//! Everything the app *is* lives in the library ([`hishell_qt`]), so a host
//! process can load it too. This file is only the desktop/standalone wiring:
//! work out which folder to open, create the QML engine (and with it the Qt
//! application), then run the event loop.

use qmetaobject::prelude::*;

fn main() {
	let args: Vec<String> = std::env::args().collect();

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

	let initial_path = if args.len() > 1 {
		let mut arg = args[1].clone();
		if arg.starts_with("file://") {
			let rest = &arg[7..];
			let decoded = percent_decode(rest);
			arg = decoded;
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
	// Returning from a guest (or a crash, or a reboot) must reopen the folder
	// the user was in; the saved session wins over the command line.
	let initial_path = hishell_qt::session::startup_path(&initial_path);
	println!("startup initial_path={}", initial_path);

	// The engine owns the Qt application, so it must exist before anything that
	// touches a QPixmap: `setup_process` warms the action icons, and warming an
	// icon builds a QPixmap, which Qt refuses without an application ("Must
	// construct a QGuiApplication before a QPixmap").
	let mut engine = QmlEngine::new();

	hishell_qt::install();
	hishell_qt::setup_process();

	// The standalone binary owns the engine and the loop.
	hishell_qt::load(&mut engine, &initial_path);
	engine.exec();
}
