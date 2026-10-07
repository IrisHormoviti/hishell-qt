use std::path::Path;
use std::process::Command;

#[derive(Debug, Default)]
pub struct DesktopEntry {
	pub name: Option<String>,
	pub icon: Option<String>,
	pub entry_type: Option<String>,
	pub exec: Option<String>,
}

impl DesktopEntry {
	pub fn is_application(&self) -> bool {
		self.entry_type.as_deref() == Some("Application")
	}
}

pub fn read(path: &Path) -> DesktopEntry {
	let values = crate::config::load_entry(path);
	DesktopEntry {
		name: crate::config::entry_string(&values, "Name").map(|name| unescape_value(&name)),
		icon: crate::config::entry_string(&values, "Icon"),
		entry_type: crate::config::entry_string(&values, "Type"),
		exec: crate::config::entry_string(&values, "Exec"),
	}
}

pub fn launch(path: &Path) -> Option<Result<(), String>> {
	let entry = read(path);
	if !entry.is_application() {
		return None;
	}

	let exec = match entry.exec.as_deref() {
		Some(exec) if !exec.trim().is_empty() => exec,
		_ => return Some(Err(format!("{} has no Exec value", path.display()))),
	};
	let args = match parse_exec(exec, &entry, path) {
		Ok(args) if !args.is_empty() => args,
		Ok(_) => return Some(Err(format!("{} has an empty Exec command", path.display()))),
		Err(error) => return Some(Err(format!("{}: {error}", path.display()))),
	};

	let mut command = Command::new(&args[0]);
	command.args(&args[1..]);
	if let Some(parent) = path.parent() {
		command.current_dir(parent);
	}

	Some(
		command
			.spawn()
			.map(|_| ())
			.map_err(|error| format!("could not launch {}: {error}", path.display())),
	)
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
		assert!(entry.is_application());
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
}
