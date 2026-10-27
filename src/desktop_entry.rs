use crate::config_parser::ConfigValue;
use std::collections::HashMap;
use std::path::Path;
use std::process::Command;

/// One integer field of a `Type=Number` control.  The entry carries the
/// current value and the range the dialog may move it within.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct NumberField {
	pub label: String,
	pub value: i64,
	pub min: i64,
	pub max: i64,
	pub default: i64,
}

#[derive(Debug, Default, Clone)]
pub struct DesktopEntry {
	pub name: Option<String>,
	pub icon: Option<String>,
	pub entry_type: Option<String>,
	pub exec: Option<String>,
	pub url: Option<String>,
	/// `Type=Toggle`: the current state of a provider's switch.
	pub toggle: Option<bool>,
	/// `Type=Number`: the labelled integers the number dialog edits.
	pub number: Vec<NumberField>,
	/// `LaunchAnimation=white|black`: the wash the compositor plays while this
	/// app starts. Absent means no animation (the app just appears).
	pub launch_animation: Option<String>,
	#[allow(dead_code)]
	pub terminal: bool,
	#[allow(dead_code)]
	pub comment: Option<String>,
	#[allow(dead_code)]
	pub no_display: bool,
	/// `Generated=true`: written by a provider daemon into a folder it owns,
	/// rather than a file the user made (docs `settings-as-folders.md` §4.4).
	pub generated: bool,
	/// `Destroy=<command line>`: what destroying this entry means. Only a
	/// provider-written entry the user actually owns carries one; without it a
	/// generated entry must not be trashed or cut, because deleting the file
	/// would just make the daemon write it back (§6.3).
	pub destroy: Option<String>,
	/// `Reset=<command line>` on a section's `.directory`: what "reset this
	/// section" means (docs `clam-configd.md` §5.2).  It is deliberately separate
	/// from `Destroy=`, because a reset keeps the section's handle.
	pub reset: Option<String>,
	/// `Rename=<command line>`: how the provider lets this entry's display
	/// label change.  A generated entry has no file to rename, so its only
	/// honest rename is the provider's own action; `%v` is the new name.  The
	/// key is omitted for everything that must not be renamed at all.
	pub rename: Option<String>,
	/// `Group=<label>`: the custom group this item belongs to.  Only read in
	/// `Group=CUSTOM` folders; a folder-level `Groups` list can also assign
	/// files by name when the entry has no key of its own.
	pub group: Option<String>,
}

impl DesktopEntry {
	pub fn is_application(&self) -> bool {
		self.entry_type.as_deref() == Some("Application")
	}

	pub fn is_link(&self) -> bool {
		self.entry_type.as_deref() == Some("Link")
	}

	/// A `Type=Button` entry (a ClamOS extension) is a control, not an app: it is
	/// selectable and launchable, but runs its `Exec` without the execution
	/// wrapper (see [`launch`]).
	pub fn is_button(&self) -> bool {
		self.entry_type.as_deref() == Some("Button")
	}

	/// A `Type=Toggle` control: a switch whose `Exec` receives the new state
	/// through `%v`.
	pub fn is_toggle(&self) -> bool {
		self.entry_type.as_deref() == Some("Toggle")
	}

	/// A `Type=Number` control: one or more integer fields edited in the
	/// number dialog, passed to `Exec` as `%1`, `%2`, ...
	pub fn is_number(&self) -> bool {
		self.entry_type.as_deref() == Some("Number")
	}

	/// Toggles and numbers are controls too, even though only `Type=Button`
	/// is the generic control type.
	pub fn is_control(&self) -> bool {
		self.is_button() || self.is_toggle() || self.is_number()
	}

	#[allow(dead_code)]
	pub fn is_directory(&self) -> bool {
		self.entry_type.as_deref() == Some("Directory")
	}

	pub fn is_action_entry(&self) -> bool {
		self.is_application()
			|| self.is_link()
			|| self.is_button()
			|| self.is_toggle()
			|| self.is_number()
	}

	/// The state of a `Type=Toggle`, when the entry is one.
	pub fn toggle_state(&self) -> Option<bool> {
		self.toggle
	}

	/// The fields of a `Type=Number`, when the entry is one.
	pub fn number_fields(&self) -> &[NumberField] {
		&self.number
	}

	/// A generated control whose only action is to change its own label.
	///
	/// The settings profile's user-name row is one: it is a `Type=Button`
	/// with a `Rename=` command and no `Exec=`, so activating it should begin
	/// the rename flow instead of running an empty command. Bluetooth
	/// devices also carry `Rename=`, but they have an `Exec=` (connect), so
	/// they keep launching.
	pub fn is_rename_only(&self) -> bool {
		self.generated
			&& self.is_button()
			&& self.rename_command().is_some()
			&& self
				.exec
				.as_deref()
				.is_none_or(|exec| exec.trim().is_empty())
	}

	/// The command that destroys this entry, when the provider that wrote it
	/// lets the folder do that at all (docs §6.3).
	pub fn destroy_command(&self) -> Option<&str> {
		self.destroy.as_deref()
	}

	/// The command that resets a section whose `.directory` this entry describes
	/// (docs `clam-configd.md` §5.2).
	pub fn reset_command(&self) -> Option<&str> {
		self.reset.as_deref()
	}

	/// The command that changes this entry's display label, when the provider
	/// allows it (docs `clam-configd.md` §5.7).
	pub fn rename_command(&self) -> Option<&str> {
		self.rename.as_deref()
	}

	/// Whether this item is the user's to destroy.
	///
	/// A generated entry belongs to the daemon that wrote it: trashing the file
	/// would only make the provider put it straight back, so it can be destroyed
	/// only through its own `Destroy=` command. Everything else is an ordinary
	/// file.  This also decides the copy/move downgrade; Cut itself is always
	/// offered and says the same thing as Trash once the paste happens.
	pub fn is_destroyable(&self) -> bool {
		self.destroy_command().is_some() || !self.generated
	}
}

pub fn read(path: &Path) -> DesktopEntry {
	from_values(&crate::config::load_entry(path))
}

/// Parses desktop entry content that does not live in a file on disk, such as
/// the entry embedded in an AppImage.
pub fn parse(content: &str) -> DesktopEntry {
	let (mut sections, _) =
		crate::config_parser::ConfigParser::parse_str(content, "<desktop entry>");
	let values = sections.remove("Desktop Entry").unwrap_or_default();
	from_values(&values)
}

fn from_values(values: &HashMap<String, ConfigValue>) -> DesktopEntry {
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
		toggle: values
			.get("Toggle")
			.and_then(crate::config::string_value)
			.map(|value| {
				matches!(
					value.trim().to_ascii_lowercase().as_str(),
					"1" | "true" | "yes" | "on"
				)
			}),
		number: parse_number_fields(values),
		launch_animation: crate::config::entry_string(&values, "LaunchAnimation")
			.filter(|value| !value.trim().is_empty()),
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
		generated: entry_boolean(values, "Generated"),
		destroy: crate::config::entry_string(&values, "Destroy")
			.filter(|command| !command.trim().is_empty()),
		reset: crate::config::entry_string(&values, "Reset")
			.filter(|command| !command.trim().is_empty()),
		rename: crate::config::entry_string(&values, "Rename")
			.filter(|command| !command.trim().is_empty()),
		group: crate::config::entry_string(&values, "Group")
			.map(|group| group.trim().to_string())
			.filter(|group| !group.is_empty()),
	}
}

/// Read the `NumberNLabel`, `NumberNValue`, `NumberNMin`, `NumberNMax` and
/// `NumberNDefault` keys a `Type=Number` provider writes.
fn parse_number_fields(values: &HashMap<String, ConfigValue>) -> Vec<NumberField> {
	let count = crate::config::entry_string(values, "NumberCount")
		.and_then(|value| value.trim().parse::<usize>().ok())
		.unwrap_or(0)
		.min(16);
	(1..=count)
		.filter_map(|index| {
			let label = crate::config::entry_string(values, &format!("Number{index}Label"))?;
			let value = entry_integer(values, &format!("Number{index}Value"))?;
			let default = entry_integer(values, &format!("Number{index}Default")).unwrap_or(value);
			let min = entry_integer(values, &format!("Number{index}Min")).unwrap_or(value);
			let max = entry_integer(values, &format!("Number{index}Max")).unwrap_or(value);
			Some(NumberField {
				label,
				value: value.clamp(min, max),
				min,
				max,
				default,
			})
		})
		.collect()
}

fn entry_integer(values: &HashMap<String, ConfigValue>, key: &str) -> Option<i64> {
	match values.get(key) {
		Some(ConfigValue::Number(value)) => Some(*value as i64),
		Some(ConfigValue::String(value)) => value.trim().parse::<i64>().ok(),
		Some(ConfigValue::Boolean(value)) => Some(if *value { 1 } else { 0 }),
		_ => None,
	}
}

/// Reads a boolean desktop-entry key, tolerating both the parsed boolean and the
/// plain string a provider may have written.
fn entry_boolean(values: &HashMap<String, ConfigValue>, key: &str) -> bool {
	match values.get(key) {
		Some(ConfigValue::Boolean(value)) => *value,
		Some(ConfigValue::String(value)) => value.eq_ignore_ascii_case("true"),
		_ => false,
	}
}

/// Launch the entry. Returns a message when the host's execution wrapper wants
/// the user to confirm first (empty otherwise).
pub fn launch(path: &Path) -> String {
	let entry = read(path);
	match entry.entry_type.as_deref() {
		Some("Application") => launch_application(path, &entry),
		Some("Button") => launch_button(path, &entry),
		Some("Link") => {
			launch_link(path, &entry);
			String::new()
		}
		// The shell draws and drives these controls; the entry's Exec is run
		// by `run_toggle`/`run_number` with the value the user chose.
		Some("Toggle") | Some("Number") => String::new(),
		_ => String::new(),
	}
}

/// Flip a `Type=Toggle` and run its `Exec` with `%v` replaced by the new state.
pub fn run_toggle(path: &Path) -> bool {
	let entry = read(path);
	let Some(state) = entry.toggle_state() else {
		return false;
	};
	let Some(exec) = entry.exec.as_deref().filter(|exec| !exec.trim().is_empty()) else {
		eprintln!("{} has no Exec value", path.display());
		return false;
	};
	let value = if state { "off" } else { "on" };
	let expanded = exec.replace("%v", value);
	spawn_control(path, &entry, &expanded)
}

/// Run a `Type=Number`'s `Exec` with `%1`, `%2`, … replaced by the dialog's
/// values.
pub fn run_number(path: &Path, values: &[i64]) -> bool {
	let entry = read(path);
	if !entry.is_number() {
		return false;
	}
	let Some(exec) = entry.exec.as_deref().filter(|exec| !exec.trim().is_empty()) else {
		eprintln!("{} has no Exec value", path.display());
		return false;
	};
	let mut expanded = exec.to_string();
	for (index, value) in values.iter().enumerate() {
		expanded = expanded.replace(&format!("%{}", index + 1), &value.to_string());
	}
	spawn_control(path, &entry, &expanded)
}

fn spawn_control(path: &Path, entry: &DesktopEntry, command: &str) -> bool {
	let args = match parse_exec(command, entry, path, None) {
		Ok(args) if !args.is_empty() => args,
		Ok(_) => {
			eprintln!("{} has an empty control command", path.display());
			return false;
		}
		Err(error) => {
			eprintln!("{}: {error}", path.display());
			return false;
		}
	};
	let entry_path = path.to_string_lossy();
	let name = entry.name.clone().unwrap_or_default();
	match crate::launch::spawn_direct(
		&args[0],
		&args[1..],
		&entry_path,
		&name,
		Some(crate::config::base_dir(path)),
	) {
		Ok(_) => true,
		Err(error) => {
			eprintln!("could not run control {}: {error}", path.display());
			false
		}
	}
}

/// Launch an application from a raw Exec line and its desktop-entry path, used
/// when the entry was resolved outside the filesystem (e.g. by KService for
/// "open with"). `file` is the file the entry is launched for, if any; it fills
/// the `%f`/`%u` field codes and is the item the wrapper receives. Returns a
/// confirmation message when the wrapper asks for one.
pub fn launch_command(exec: &str, entry_path: &str, file: Option<&str>) -> String {
	let path = Path::new(entry_path);
	let entry = if entry_path.is_empty() {
		DesktopEntry::default()
	} else {
		read(path)
	};
	let args = match parse_exec(exec, &entry, path, file) {
		Ok(args) if !args.is_empty() => args,
		Ok(_) => {
			eprintln!("empty Exec command for {entry_path}");
			return String::new();
		}
		Err(error) => {
			eprintln!("{entry_path}: {error}");
			return String::new();
		}
	};
	let item = file.unwrap_or(entry_path);
	let name = entry.name.clone().unwrap_or_default();
	let current_dir = (!entry_path.is_empty()).then(|| crate::config::base_dir(path));
	crate::launch::result(crate::launch::request(
		&args[0],
		&args[1..],
		item,
		&name,
		entry.launch_animation.as_deref().unwrap_or_default(),
		current_dir,
	))
}

fn launch_application(path: &Path, entry: &DesktopEntry) -> String {
	let exec = match entry.exec.as_deref() {
		Some(exec) if !exec.trim().is_empty() => exec,
		_ => {
			eprintln!("{} has no Exec value", path.display());
			return String::new();
		}
	};
	let args = match parse_exec(exec, entry, path, None) {
		Ok(args) if !args.is_empty() => args,
		Ok(_) => {
			eprintln!("{} has an empty Exec command", path.display());
			return String::new();
		}
		Err(error) => {
			eprintln!("{}: {error}", path.display());
			return String::new();
		}
	};

	let entry_path = path.to_string_lossy();
	let name = entry.name.clone().unwrap_or_default();
	let current_dir = crate::config::base_dir(path);
	crate::launch::result(crate::launch::request(
		&args[0],
		&args[1..],
		&entry_path,
		&name,
		entry.launch_animation.as_deref().unwrap_or_default(),
		Some(current_dir),
	))
}

/// A `Button` is a control, not an app, so it is run directly: no execution
/// wrapper, and therefore no preflight and no guest-app lifecycle.
fn launch_button(path: &Path, entry: &DesktopEntry) -> String {
	let exec = match entry.exec.as_deref() {
		Some(exec) if !exec.trim().is_empty() => exec,
		_ => {
			eprintln!("{} has no Exec value", path.display());
			return String::new();
		}
	};
	let args = match parse_exec(exec, entry, path, None) {
		Ok(args) if !args.is_empty() => args,
		Ok(_) => {
			eprintln!("{} has an empty Exec command", path.display());
			return String::new();
		}
		Err(error) => {
			eprintln!("{}: {error}", path.display());
			return String::new();
		}
	};

	let entry_path = path.to_string_lossy();
	let name = entry.name.clone().unwrap_or_default();
	let current_dir = crate::config::base_dir(path);
	if let Err(error) =
		crate::launch::spawn_direct(&args[0], &args[1..], &entry_path, &name, Some(current_dir))
	{
		eprintln!("could not launch: {error}");
	}
	String::new()
}

/// Run an entry's `Destroy=` command: that, rather than moving the file, is how a
/// generated entry the provider lets the user own is destroyed (docs §6.3).
/// Returns whether it started.
pub fn run_destroy(path: &Path, entry: &DesktopEntry, command: &str) -> bool {
	let args = match parse_exec(command, entry, path, None) {
		Ok(args) if !args.is_empty() => args,
		Ok(_) => {
			eprintln!("{} has an empty Destroy command", path.display());
			return false;
		}
		Err(error) => {
			eprintln!("{}: {error}", path.display());
			return false;
		}
	};

	let entry_path = path.to_string_lossy();
	let name = entry.name.clone().unwrap_or_default();
	let current_dir = crate::config::base_dir(path);
	// Direct spawn, like a `Type=Button`: destroying a control is not a guest
	// app launch, and the entry path still travels as `HISHELL_APP_ITEM`.
	match crate::launch::spawn_direct(&args[0], &args[1..], &entry_path, &name, Some(current_dir)) {
		Ok(_) => true,
		Err(error) => {
			eprintln!("could not destroy {}: {error}", path.display());
			false
		}
	}
}

/// Run a folder's own `Refresh=<command line>` (a ClamOS extension, docs §4.7):
/// how a folder asks its provider for fresh contents when the user refreshes
/// it. A control rather than an app launch, so it is spawned directly — no
/// execution wrapper, and therefore no guest-app lifecycle.
pub fn run_refresh(directory: &Path, command: &str) -> bool {
	let entry_path = directory.join(".directory");
	let entry = read(&entry_path);
	let args = match parse_exec(command, &entry, &entry_path, None) {
		Ok(args) if !args.is_empty() => args,
		Ok(_) => {
			eprintln!("{} has an empty Refresh command", entry_path.display());
			return false;
		}
		Err(error) => {
			eprintln!("{}: {error}", entry_path.display());
			return false;
		}
	};

	let name = entry.name.clone().unwrap_or_default();
	match crate::launch::spawn_direct(
		&args[0],
		&args[1..],
		&entry_path.to_string_lossy(),
		&name,
		Some(directory),
	) {
		Ok(_) => true,
		Err(error) => {
			eprintln!("could not refresh {}: {error}", directory.display());
			false
		}
	}
}

/// Run a section's `Reset=<command line>`: clear its provider state while
/// keeping its handle (docs `clam-configd.md` §5.2).  Like `Refresh=` and
/// `Destroy=`, this is a control action, not a guest app launch.
pub fn run_reset(directory: &Path, command: &str) -> bool {
	let entry_path = directory.join(".directory");
	let entry = read(&entry_path);
	let args = match parse_exec(command, &entry, &entry_path, None) {
		Ok(args) if !args.is_empty() => args,
		Ok(_) => {
			eprintln!("{} has an empty Reset command", entry_path.display());
			return false;
		}
		Err(error) => {
			eprintln!("{}: {error}", entry_path.display());
			return false;
		}
	};
	let name = entry.name.clone().unwrap_or_default();
	match crate::launch::spawn_direct(
		&args[0],
		&args[1..],
		&entry_path.to_string_lossy(),
		&name,
		Some(directory),
	) {
		Ok(_) => true,
		Err(error) => {
			eprintln!("could not reset {}: {error}", directory.display());
			false
		}
	}
}

/// Run an entry's `Rename=<command line>`: how a provider changes a generated
/// entry's display label (docs `clam-configd.md` §5.7).  Unlike the other
/// hooks this one is waited on, so a provider that refuses ("only a paired
/// device", "no longer in range") can report its answer through the rename
/// flow.
pub fn run_rename(
	path: &Path,
	entry: &DesktopEntry,
	command: &str,
	new_name: &str,
) -> Result<(), String> {
	let args = rename_args(command, entry, path, new_name)?;
	if args.is_empty() {
		return Err("The Rename command is empty.".to_string());
	}
	let output = Command::new(&args[0])
		.args(&args[1..])
		.current_dir(crate::config::base_dir(path))
		.env(crate::launch::ITEM_ENV, path)
		.env(
			crate::launch::NAME_ENV,
			entry.name.as_deref().unwrap_or_default(),
		)
		.output()
		.map_err(|error| format!("Could not run Rename: {error}"))?;
	if output.status.success() {
		return Ok(());
	}
	let stderr = String::from_utf8_lossy(&output.stderr);
	let message = stderr.trim();
	if message.is_empty() {
		Err("Rename failed.".to_string())
	} else {
		Err(message.to_string())
	}
}

/// Run a command line supplied by a directory descriptor (`Unmount=`), with
/// the described path as the action's item.  Descriptors already describe
/// directories whose metadata lives outside them; the same mechanism gives the
/// shell the only honest action for a mounted device (docs §5.5).
pub fn run_hook(command: &str, item: &Path, name: &str) -> bool {
	let entry = DesktopEntry::default();
	let args = match parse_exec(command, &entry, item, None) {
		Ok(args) if !args.is_empty() => args,
		Ok(_) => return false,
		Err(error) => {
			eprintln!("{}: {error}", item.display());
			return false;
		}
	};
	match crate::launch::spawn_direct(
		&args[0],
		&args[1..],
		&item.to_string_lossy(),
		name,
		item.parent(),
	) {
		Ok(_) => true,
		Err(error) => {
			eprintln!("could not run hook for {}: {error}", item.display());
			false
		}
	}
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

pub fn is_button(path: &Path) -> bool {
	read(path).is_button()
}

pub fn is_control(path: &Path) -> bool {
	read(path).is_control()
}

pub fn is_toggle(path: &Path) -> bool {
	read(path).is_toggle()
}

pub fn is_number(path: &Path) -> bool {
	read(path).is_number()
}

pub fn toggle_state(path: &Path) -> Option<bool> {
	read(path).toggle_state()
}

pub fn number_fields(path: &Path) -> Vec<NumberField> {
	read(path).number_fields().to_vec()
}

pub fn is_rename_only(path: &Path) -> bool {
	read(path).is_rename_only()
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

/// Expand a `Rename=` command: `%v` is the new label, `%n` the old display
/// name, `%p` the entry path.  Tokenising happens before substitution, so a
/// label with spaces still arrives as one argument.
fn rename_args(
	command: &str,
	entry: &DesktopEntry,
	path: &Path,
	new_name: &str,
) -> Result<Vec<String>, String> {
	let tokens = tokenize_exec(command)?;
	let mut args = Vec::new();
	for token in tokens {
		let mut expanded = String::new();
		let mut chars = token.chars();
		while let Some(ch) = chars.next() {
			if ch != '%' {
				expanded.push(ch);
				continue;
			}
			match chars.next() {
				Some('%') => expanded.push('%'),
				Some('v') => expanded.push_str(new_name),
				Some('n') => expanded.push_str(entry.name.as_deref().unwrap_or_default()),
				Some('p') => expanded.push_str(&path.to_string_lossy()),
				Some(other) => {
					return Err(format!("unsupported field code %{other} in Rename"));
				}
				None => return Err("Rename ends with an incomplete field code".to_string()),
			}
		}
		if !expanded.is_empty() {
			args.push(expanded);
		}
	}
	Ok(args)
}

fn parse_exec(
	exec: &str,
	entry: &DesktopEntry,
	path: &Path,
	file: Option<&str>,
) -> Result<Vec<String>, String> {
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
				// A file argument: the file the entry was launched for.
				Some('f' | 'F' | 'u' | 'U') => {
					if let Some(file) = file {
						expanded.push_str(file);
					}
				}
				Some('d' | 'D' | 'n' | 'N' | 'v' | 'm' | 'i') => {}
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
	use super::{DesktopEntry, parse, parse_exec, read, rename_args, tokenize_exec};
	use std::fs;
	use std::path::{Path, PathBuf};

	/// A unique scratch file for one test.
	fn scratch(name: &str) -> PathBuf {
		std::env::temp_dir().join(format!("{name}-{}.desktop", std::process::id()))
	}

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
				Path::new("/apps/example.desktop"),
				None
			)
			.unwrap(),
			["example --open"]
		);
	}

	#[test]
	fn recognizes_button_entries() {
		let path = std::env::temp_dir().join(format!(
			"hishell-button-test-{}.desktop",
			std::process::id()
		));
		// A provider-written entry: Type=Button, framework keys, and a
		// section-specific group Hishell must ignore.
		fs::write(
			&path,
			"[Desktop Entry]\nType=Button\nName=Wi-Fi\nComment=On\nIcon=network-wireless\n\
			 Exec=clam-connect wifi --radio off\nGenerated=true\nProvider=wifi\n\n\
			 [Connection]\nAction=radio\nEnabled=true\n",
		)
		.unwrap();
		let entry = read(&path);
		fs::remove_file(path).unwrap();

		assert!(entry.is_button());
		assert!(entry.is_action_entry(), "Buttons are selectable/launchable");
		assert_eq!(entry.name.as_deref(), Some("Wi-Fi"));
		assert_eq!(entry.exec.as_deref(), Some("clam-connect wifi --radio off"));
		assert!(entry.generated);
		assert_eq!(entry.destroy_command(), None);
		assert_eq!(entry.rename_command(), None);
		assert!(
			!entry.is_destroyable(),
			"a provider's control row is not the user's to trash"
		);
	}

	#[test]
	fn expands_a_rename_command_without_splitting_the_label() {
		let path = scratch("hishell-rename-test");
		fs::write(
			&path,
			"[Desktop Entry]\nType=Button\nName=Old label\nGenerated=true\n\
			 Rename=clam-connect bt --rename AA:BB:CC:DD:EE:FF %v\n",
		)
		.unwrap();
		let entry = read(&path);
		fs::remove_file(path).unwrap();

		assert_eq!(
			entry.rename_command(),
			Some("clam-connect bt --rename AA:BB:CC:DD:EE:FF %v")
		);
		assert_eq!(
			rename_args(
				entry.rename_command().unwrap(),
				&entry,
				Path::new("/sections/Bluetooth/AA:BB.desktop"),
				"New label"
			)
			.unwrap(),
			[
				"clam-connect",
				"bt",
				"--rename",
				"AA:BB:CC:DD:EE:FF",
				"New label"
			]
		);
	}

	#[test]
	fn a_label_only_control_renames_when_activated() {
		let path = scratch("hishell-rename-only-test");
		fs::write(
			&path,
			"[Desktop Entry]\nType=Button\nName=Player\nGenerated=true\nExec=\n\
			 Rename=clam-configd profile set-name %v\n",
		)
		.unwrap();
		let entry = read(&path);
		fs::remove_file(path).unwrap();

		assert!(entry.is_rename_only());
	}

	#[test]
	fn a_renameable_entry_with_a_command_still_launches() {
		let path = scratch("hishell-rename-exec-test");
		fs::write(
			&path,
			"[Desktop Entry]\nType=Button\nName=Headphones\nGenerated=true\n\
			 Exec=clam-connect bt AA:BB:CC:DD:EE:FF\n\
			 Rename=clam-connect bt --rename AA:BB:CC:DD:EE:FF %v\n",
		)
		.unwrap();
		let entry = read(&path);
		fs::remove_file(path).unwrap();

		assert!(!entry.is_rename_only());
	}

	#[test]
	fn a_generated_entry_that_names_its_destroy_command_can_be_destroyed() {
		let path = scratch("hishell-destroy-test");
		fs::write(
			&path,
			"[Desktop Entry]\nType=Button\nName=Home\nComment=Saved · WPA2\n\
			 Icon=network-wireless-60-locked\nExec=clam-connect wifi wpa:abc\n\
			 Destroy=clam-connect wifi --forget wpa:abc\nGenerated=true\nProvider=wifi\n\n\
			 [Connection]\nId=wpa:abc\nSecurity=WPA-PSK\nSaved=true\n",
		)
		.unwrap();
		let entry = read(&path);
		fs::remove_file(path).unwrap();

		assert!(entry.is_button());
		assert_eq!(
			entry.destroy_command(),
			Some("clam-connect wifi --forget wpa:abc")
		);
		assert!(entry.is_destroyable());
	}

	#[test]
	fn a_visible_network_cannot_be_destroyed() {
		let path = scratch("hishell-visible-test");
		fs::write(
			&path,
			"[Desktop Entry]\nType=Button\nName=Neighbour\nExec=clam-connect wifi b3f1c0a2e4\n\
			 Generated=true\nProvider=wifi\n\n\
			 [Connection]\nId=b3f1c0a2e4\nSecurity=WPA-PSK\nSaved=false\n",
		)
		.unwrap();
		let entry = read(&path);
		fs::remove_file(path).unwrap();

		assert_eq!(entry.destroy_command(), None);
		assert!(
			!entry.is_destroyable(),
			"a merely detected network cannot be trashed or cut"
		);
	}

	#[test]
	fn ordinary_files_are_still_destroyable() {
		let path = scratch("hishell-plain-test");
		fs::write(&path, "just some notes\n").unwrap();
		let entry = read(&path);
		fs::remove_file(path).unwrap();

		assert!(!entry.generated);
		assert_eq!(entry.destroy_command(), None);
		assert!(entry.is_destroyable());
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
				Path::new("/apps/example.desktop"),
				None
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
		// With a file, %f fills in the launched item.
		assert_eq!(
			parse_exec(
				r#"emu %f %k"#,
				&entry,
				Path::new("/apps/emu.desktop"),
				Some("/roms/game.nds")
			)
			.unwrap(),
			["emu", "/roms/game.nds", "/apps/emu.desktop"]
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
	fn reads_a_toggle_control() {
		let entry = parse(
			"[Desktop Entry]\nType=Toggle\nName=Use 24-hour time\nToggle=on\n\
			 Exec=clam-configd settings set clock-24h %v\nGenerated=true\n",
		);
		assert!(entry.is_toggle());
		assert!(entry.is_control());
		assert!(entry.is_action_entry());
		assert_eq!(entry.toggle_state(), Some(true));
	}

	#[test]
	fn reads_number_fields_and_their_ranges() {
		let entry = parse(
			"[Desktop Entry]\nType=Number\nName=Set date\nNumberCount=2\n\
			 Number1Label=Year\nNumber1Value=2026\nNumber1Min=1970\nNumber1Max=2100\nNumber1Default=2026\n\
			 Number2Label=Month\nNumber2Value=10\nNumber2Min=1\nNumber2Max=12\nNumber2Default=1\n\
			 Exec=clam-configd settings set datetime %1 %2\nGenerated=true\n",
		);
		assert!(entry.is_number());
		let fields = entry.number_fields();
		assert_eq!(fields.len(), 2);
		assert_eq!(fields[0].label, "Year");
		assert_eq!((fields[0].min, fields[0].max), (1970, 2100));
		assert_eq!(fields[1].value, 10);
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
