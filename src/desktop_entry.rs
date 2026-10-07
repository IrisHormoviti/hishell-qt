use std::path::Path;
use std::process::Command;

#[derive(Debug, Default, Clone)]
pub struct DesktopEntry {
	pub name: Option<String>,
	pub icon: Option<String>,
	pub entry_type: Option<String>,
	pub exec: Option<String>,
	pub url: Option<String>,
	#[allow(dead_code)]
	pub terminal: bool,
	#[allow(dead_code)]
	pub comment: Option<String>,
	#[allow(dead_code)]
	pub no_display: bool,
}

impl DesktopEntry {
	pub fn is_application(&self) -> bool {
		self.entry_type.as_deref() == Some("Application")
	}

	pub fn is_link(&self) -> bool {
		self.entry_type.as_deref() == Some("Link")
	}

	#[allow(dead_code)]
	pub fn is_directory(&self) -> bool {
		self.entry_type.as_deref() == Some("Directory")
	}

	pub fn is_action_entry(&self) -> bool {
		self.is_application() || self.is_link()
	}
}

pub fn read(path: &Path) -> DesktopEntry {
	let values = crate::config::load_entry(path);
	let url = values
		.iter()
		.filter(|(key, _)| key.as_str() == "URL" || key.starts_with("URL["))
		.filter_map(|(_, value)| crate::config::string_value(value))
		.find(|v| !v.trim().is_empty())
		.or_else(|| values.get("URL").and_then(crate::config::string_value));

	DesktopEntry {
		name: crate::config::entry_string(&values, "Name").map(|name| unescape_value(&name)),
		icon: crate::config::entry_string(&values, "Icon"),
		entry_type: crate::config::entry_string(&values, "Type"),
		exec: crate::config::entry_string(&values, "Exec"),
		url,
		terminal: values
			.get("Terminal")
			.and_then(|v| match v {
				crate::config_parser::ConfigValue::Boolean(b) => Some(*b),
				_ => None,
			})
			.unwrap_or(false),
		comment: crate::config::entry_string(&values, "Comment").map(|c| unescape_value(&c)),
		no_display: values
			.get("NoDisplay")
			.and_then(|v| match v {
				crate::config_parser::ConfigValue::Boolean(b) => Some(*b),
				_ => None,
			})
			.unwrap_or(false),
	}
}

pub fn launch(path: &Path) -> Option<Result<(), String>> {
	let entry = read(path);
	match entry.entry_type.as_deref() {
		Some("Application") => launch_application(path, &entry),
		Some("Link") => launch_link(path, &entry),
		_ => None,
	}
}

fn launch_application(path: &Path, entry: &DesktopEntry) -> Option<Result<(), String>> {
	let exec = match entry.exec.as_deref() {
		Some(exec) if !exec.trim().is_empty() => exec,
		_ => return Some(Err(format!("{} has no Exec value", path.display()))),
	};
	let args = match parse_exec(exec, entry, path) {
		Ok(args) if !args.is_empty() => args,
		Ok(_) => return Some(Err(format!("{} has an empty Exec command", path.display()))),
		Err(error) => return Some(Err(format!("{}: {error}", path.display()))),
	};

	let mut command = Command::new(&args[0]);
	command.args(&args[1..]);
	command.current_dir(crate::config::base_dir(path));

	Some(
		command
			.spawn()
			.map(|_| ())
			.map_err(|error| format!("could not launch {}: {error}", path.display())),
	)
}

fn launch_link(path: &Path, entry: &DesktopEntry) -> Option<Result<(), String>> {
	let url = match entry.url.as_deref() {
		Some(url) if !url.trim().is_empty() => url,
		_ => return Some(Err(format!("{} has no URL value", path.display()))),
	};

	let expanded = expand_url(url);

	Some(
		Command::new("xdg-open")
			.arg(expanded)
			.spawn()
			.map(|_| ())
			.map_err(|error| format!("could not open link from {}: {error}", path.display())),
	)
}

pub fn expand_url(url: &str) -> String {
	let mut expanded = url.to_string();
	if expanded == "~" || expanded.starts_with("~/") {
		if let Ok(home) = std::env::var("HOME") {
			expanded = format!("{}{}", home, &expanded[1..]);
		}
	}
	if expanded.contains('$') {
		let mut result = String::new();
		let mut chars = expanded.chars().peekable();
		while let Some(ch) = chars.next() {
			if ch == '$' {
				let mut var_name = String::new();
				if chars.peek() == Some(&'{') {
					chars.next();
					while let Some(&c) = chars.peek() {
						if c == '}' {
							chars.next();
							break;
						}
						var_name.push(c);
						chars.next();
					}
				} else {
					while let Some(&c) = chars.peek() {
						if c.is_alphanumeric() || c == '_' {
							var_name.push(c);
							chars.next();
						} else {
							break;
						}
					}
				}
				if let Ok(val) = std::env::var(&var_name) {
					result.push_str(&val);
				} else {
					result.push('$');
					result.push_str(&var_name);
				}
			} else {
				result.push(ch);
			}
		}
		expanded = result;
	}
	expanded
}

pub fn is_action_entry(path: &Path) -> bool {
	read(path).is_action_entry()
}

pub fn is_link(path: &Path) -> bool {
	read(path).is_link()
}

#[allow(dead_code)]
pub fn is_application(path: &Path) -> bool {
	read(path).is_application()
}

fn unescape_value(value: &str) -> String {
	let mut result = String::new();
	let mut chars = value.chars();
	while let Some(ch) = chars.next() {
		if ch == '\\' {
			match chars.next() {
				Some('s') => result.push(' '),
				Some('n') => result.push('\n'),
				Some('t') => result.push('\t'),
				Some('r') => result.push('\r'),
				Some('\\') => result.push('\\'),
				Some(other) => {
					result.push('\\');
					result.push(other);
				}
				None => result.push('\\'),
			}
		} else {
			result.push(ch);
		}
	}
	result
}

fn parse_exec(exec: &str, entry: &DesktopEntry, path: &Path) -> Result<Vec<String>, String> {
	let tokens = tokenize_exec(exec)?;
	let mut args = Vec::new();

	for token in tokens {
		if token == "%i" {
			if let Some(icon) = &entry.icon {
				args.push("--icon".to_string());
				args.push(icon.clone());
			}
			continue;
		}

		let mut expanded = String::new();
		let mut chars = token.chars();
		while let Some(ch) = chars.next() {
			if ch != '%' {
				expanded.push(ch);
				continue;
			}

			match chars.next() {
				Some('%') => expanded.push('%'),
				Some('c') => {
					if let Some(name) = &entry.name {
						expanded.push_str(name);
					}
				}
				Some('k') => expanded.push_str(&path.to_string_lossy()),
				Some('f' | 'F' | 'u' | 'U' | 'd' | 'D' | 'n' | 'N' | 'v' | 'm' | 'i') => {}
				Some(other) => {
					return Err(format!("unsupported field code %{other} in Exec"));
				}
				None => return Err("Exec ends with an incomplete field code".to_string()),
			}
		}

		if !expanded.is_empty() {
			args.push(expanded);
		}
	}

	Ok(args)
}

fn tokenize_exec(exec: &str) -> Result<Vec<String>, String> {
	let mut args = Vec::new();
	let mut token = String::new();
	let mut chars = exec.chars().peekable();
	let mut quote = None;
	let mut token_started = false;

	while let Some(ch) = chars.next() {
		match ch {
			'\\' => {
				let escaped = chars
					.next()
					.ok_or_else(|| "Exec ends with an incomplete escape".to_string())?;
				token.push(escaped);
				token_started = true;
			}
			'"' | '\'' if quote == Some(ch) => quote = None,
			'"' | '\'' if quote.is_none() => {
				quote = Some(ch);
				token_started = true;
			}
			ch if ch.is_whitespace() && quote.is_none() => {
				if token_started {
					args.push(std::mem::take(&mut token));
					token_started = false;
				}
			}
			_ => {
				token.push(ch);
				token_started = true;
			}
		}
	}

	if quote.is_some() {
		return Err("Exec contains an unterminated quote".to_string());
	}
	if token_started {
		args.push(token);
	}
	Ok(args)
}

#[cfg(test)]
mod tests {
	use super::{DesktopEntry, parse_exec, read, tokenize_exec};
	use std::fs;
	use std::path::Path;

	#[test]
	fn parses_desktop_entry_metadata() {
		let path = std::env::temp_dir().join(format!(
			"hishell-desktop-entry-test-{}.desktop",
			std::process::id()
		));
		fs::write(
			&path,
			"[Other]\nName=Ignored\n[Desktop Entry]\nName=Example\\sApp\nIcon=example\nType=Application\nExec=\"example --open\"\n",
		)
		.unwrap();
		let entry = read(&path);
		fs::remove_file(path).unwrap();

		assert_eq!(entry.name.as_deref(), Some("Example App"));
		assert_eq!(entry.icon.as_deref(), Some("example"));
		assert!(entry.is_action_entry());
		assert_eq!(entry.exec.as_deref(), Some("\"example --open\""));
		assert_eq!(
			parse_exec(
				entry.exec.as_deref().unwrap(),
				&entry,
				Path::new("/apps/example.desktop")
			)
			.unwrap(),
			["example --open"]
		);
	}

	#[test]
	fn recognizes_link_entries_with_encoded_url_keys() {
		let path = std::env::temp_dir().join(format!(
			"hishell-desktop-link-test-{}.desktop",
			std::process::id()
		));
		fs::write(
			&path,
			"[Desktop Entry]\nType=Link\nURL[$e]=https://bsky.app\n",
		)
		.unwrap();
		let entry = read(&path);
		fs::remove_file(path).unwrap();

		assert!(entry.is_action_entry());
		assert_eq!(entry.url.as_deref(), Some("https://bsky.app"));
	}

	#[test]
	fn tokenizes_quoted_exec_arguments() {
		assert_eq!(
			tokenize_exec(r#"app --name "two words" 'single quoted'"#).unwrap(),
			["app", "--name", "two words", "single quoted"]
		);
	}

	#[test]
	fn expands_desktop_entry_field_codes() {
		let entry = DesktopEntry {
			name: Some("Example App".to_string()),
			icon: Some("example-icon".to_string()),
			..DesktopEntry::default()
		};
		assert_eq!(
			parse_exec(
				r#"app "%c" %% %i %f %k"#,
				&entry,
				Path::new("/apps/example.desktop")
			)
			.unwrap(),
			[
				"app",
				"Example App",
				"%",
				"--icon",
				"example-icon",
				"/apps/example.desktop"
			]
		);
	}

	#[test]
	fn reads_desktop_entry_from_directory() {
		let dir =
			std::env::temp_dir().join(format!("hishell-dir-link-test-{}", std::process::id()));
		fs::create_dir_all(&dir).unwrap();
		fs::write(
			dir.join(".directory"),
			"[Desktop Entry]\nType=Link\nName=Search\\sEngine\nURL=https://duckduckgo.com\n",
		)
		.unwrap();

		let entry = read(&dir);
		assert!(entry.is_link());
		assert!(entry.is_action_entry());
		assert_eq!(entry.name.as_deref(), Some("Search Engine"));
		assert_eq!(entry.url.as_deref(), Some("https://duckduckgo.com"));

		fs::remove_dir_all(dir).unwrap();
	}

	#[test]
	fn expands_url_environment_variables() {
		use super::expand_url;
		unsafe { std::env::set_var("HISHELL_TEST_DOMAIN", "example.org") };
		assert_eq!(
			expand_url("https://${HISHELL_TEST_DOMAIN}/path"),
			"https://example.org/path"
		);
		assert_eq!(
			expand_url("https://$HISHELL_TEST_DOMAIN/path"),
			"https://example.org/path"
		);
	}

	#[test]
	fn recognizes_desktop_entry_without_desktop_extension() {
		let path =
			std::env::temp_dir().join(format!("hishell-custom-ext-test-{}", std::process::id()));
		fs::write(
			&path,
			"[Desktop Entry]\nType=Link\nName=Bluesky\nURL=https://bsky.app\nIcon=/icons/bsky.png\n",
		)
		.unwrap();

		let entry = read(&path);
		assert!(entry.is_link());
		assert!(entry.is_action_entry());
		assert_eq!(entry.name.as_deref(), Some("Bluesky"));
		assert_eq!(entry.url.as_deref(), Some("https://bsky.app"));
		assert_eq!(entry.icon.as_deref(), Some("/icons/bsky.png"));

		fs::remove_file(path).unwrap();
	}

	#[test]
	fn directory_resolves_icons_for_nonstandard_desktop_files() {
		let path = Path::new("/home/iris/Desktop/bsky.app");
		if path.exists() {
			let title = crate::directory::get_item_title(path);
			let icon = crate::directory::get_icon(&path.to_string_lossy());
			assert_eq!(title, "https:⁄⁄bsky.app");
			assert_eq!(icon, "file:///home/iris/Applications/.icons/bsky.png");
			assert!(crate::directory::is_execute_target(path));
			assert!(crate::desktop_entry::is_link(path));
		}
	}
}
