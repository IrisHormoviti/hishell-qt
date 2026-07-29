use std::fs;
use std::path::Path;


pub fn get_icon(path: &Path) -> Option<String> {
	let content = fs::read_to_string(path).ok()?;
	let mut in_desktop_entry = false;

	for line in content.lines() {
		let line = line.trim();

		if line.starts_with('[') && line.ends_with(']') {
			in_desktop_entry = line == "[Desktop Entry]";
			continue;
		}

		if in_desktop_entry && line.starts_with("Icon=") {
			let icon = line["Icon=".len()..].trim();
			if !icon.is_empty() {
				return Some(icon.to_string());
			}
		}
	}

	None
}
