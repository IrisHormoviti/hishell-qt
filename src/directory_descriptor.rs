//! Item descriptors: a desktop entry that names a directory or file and gives
//! it a display name and icon, so it can be presented without writing a
//! `.directory` beside it.
//!
//! A directory's metadata normally lives in its own `<dir>/.directory`. That is
//! wrong for a directory someone else owns — a mounted SD card or USB stick is
//! read-only, or simply not ours to litter. A descriptor keeps the metadata
//! outside the directory and points at it:
//!
//! ```ini
//! [Desktop Entry]
//! Type=Directory
//! Path=/mnt/sdcard
//! Name=SD Card
//! Icon=media-flash-sd-mmc
//! Unmount=/usr/lib/hishell/clam-removable.sh remove /dev/sdb1
//! ```
//!
//! `Path` is the directory being described; `Name` and `Icon` are what the file
//! views use for it (and for a symlink pointing at it, like `~/sdcard`). The
//! on-disk `.directory`, when there is one, still wins: the descriptor is a
//! fallback for directories that cannot carry their own metadata.
//!
//! The same form describes a single file with `Type=File`. That is how a
//! descriptor generator attaches a title, comment and icon to a ROM without
//! writing anything beside the ROM itself (see
//! [`crate::descriptor_generator`]).
//!
//! Descriptors are read from `hishell/directories` under the XDG data dirs
//! (system and bundle), from the generated-descriptor cache, from the user's
//! own data directory, and from the runtime directory [`RUNTIME_ROOT`], which
//! `clam-removable.sh` populates for mounted removable media. Later roots
//! override earlier ones, so a generated entry beats a shipped one, a user
//! descriptor beats both, and a live mount beats all of them.

use crate::config_parser::{ConfigParser, ConfigValue};
use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{Duration, Instant};

/// Where `clam-removable.sh` writes descriptors for mounted removable media.
/// Outside the user's home: the entries are session state, not the user's files,
/// and the runtime filesystem clears them on reboot.
pub const RUNTIME_ROOT: &str = "/run/clam-removable/directories";

/// The index is rebuilt at most this often. A device plugged while the shell is
/// running has its descriptor written by the udev helper; the folder poll (and
/// the icon poll on the same timer) then sees it within a second.
const REFRESH: Duration = Duration::from_secs(1);

#[derive(Clone, Debug, Default)]
pub struct Descriptor {
	pub name: Option<String>,
	pub icon: Option<String>,
	/// An optional `Unmount=<command line>`: how to make the described thing
	/// go away.  A mounted device's link is reconciled by whoever mounted it,
	/// so trashing the link would not stick; the warning offers this instead
	/// (`docs/clam-configd.md` §5.5).
	pub unmount: Option<String>,
}

static CACHE: Lazy<Mutex<Option<(Instant, HashMap<PathBuf, Descriptor>)>>> =
	Lazy::new(|| Mutex::new(None));

/// The directories scanned for descriptors, lowest precedence first.
fn roots() -> Vec<PathBuf> {
	let mut roots = Vec::new();
	for dir in data_dirs() {
		roots.push(dir.join("hishell/directories"));
	}
	// Generated descriptors are cache, not user files: they override a shipped
	// definition but a hand-written one in the user's data directory still wins.
	roots.push(crate::descriptor_generator::cache_root());
	if let Some(dir) = dirs::data_dir() {
		roots.push(dir.join("hishell/directories"));
	}
	roots.push(PathBuf::from(RUNTIME_ROOT));
	roots
}

/// `$XDG_DATA_DIRS`, which the launcher sets to the bundle's share directory
/// ahead of `/usr/share`, so a shipped descriptor is found. The `dirs` crate
/// only exposes the singular `data_dir`, hence the manual split.
fn data_dirs() -> Vec<PathBuf> {
	let value = std::env::var("XDG_DATA_DIRS")
		.unwrap_or_else(|_| "/usr/local/share:/usr/share".to_string());
	value
		.split(':')
		.filter(|part| !part.is_empty())
		.map(PathBuf::from)
		.collect()
}

/// Read every descriptor under `root` into `map`, keyed by canonical target.
fn read_root(root: &Path, map: &mut HashMap<PathBuf, Descriptor>) {
	let Ok(entries) = std::fs::read_dir(root) else {
		return;
	};
	let mut files: Vec<PathBuf> = entries
		.flatten()
		.map(|entry| entry.path())
		.filter(|path| {
			path.extension()
				.is_some_and(|ext| ext.eq_ignore_ascii_case("desktop"))
		})
		.collect();
	files.sort();
	for file in files {
		if let Some((target, descriptor)) = read_descriptor(&file) {
			map.insert(target, descriptor);
		}
	}
}

fn build() -> HashMap<PathBuf, Descriptor> {
	let mut map = HashMap::new();
	for root in roots() {
		read_root(&root, &mut map);
	}
	map
}

fn read_descriptor(file: &Path) -> Option<(PathBuf, Descriptor)> {
	let (sections, _) = ConfigParser::parse_file(file);
	let section = sections.get("Desktop Entry")?;
	let kind = string(section, "Type")?;
	if !kind.eq_ignore_ascii_case("Directory") && !kind.eq_ignore_ascii_case("File") {
		return None;
	}
	let target = expand(&string(section, "Path")?)?;
	// A descriptor for something that is not there describes nothing; keeping it
	// out of the index also means an unplugged mount stops matching the moment
	// its descriptor would otherwise go stale.
	let target = std::fs::canonicalize(target).ok()?;
	let kind_ok = if kind.eq_ignore_ascii_case("Directory") {
		target.is_dir()
	} else {
		target.is_file()
	};
	if !kind_ok {
		return None;
	}
	let descriptor = Descriptor {
		name: string(section, "Name").filter(|name| !name.trim().is_empty()),
		icon: string(section, "Icon").filter(|icon| !icon.trim().is_empty()),
		unmount: string(section, "Unmount").filter(|command| !command.trim().is_empty()),
	};
	Some((target, descriptor))
}

fn string(section: &HashMap<String, ConfigValue>, key: &str) -> Option<String> {
	match section.get(key)? {
		ConfigValue::String(value) => Some(value.clone()),
		ConfigValue::Number(value) => Some(value.to_string()),
		_ => None,
	}
}

/// Resolve a descriptor's `Path`: `~/x` against the home directory, everything
/// else as written.
fn expand(path: &str) -> Option<PathBuf> {
	let path = path.trim();
	if path.is_empty() {
		return None;
	}
	if let Some(rest) = path.strip_prefix("~/") {
		return dirs::home_dir().map(|home| home.join(rest));
	}
	Some(PathBuf::from(path))
}

/// The descriptor describing `path`, if there is one. Symlinks are resolved, so
/// a link in the home directory is described by the mount it points at and a
/// ROM reachable through a link is described by the entry generated for the
/// file it points at.
pub fn lookup(path: &Path) -> Option<Descriptor> {
	if !path.exists() {
		return None;
	}
	let canonical = std::fs::canonicalize(path).ok()?;
	let mut cache = CACHE.lock().ok()?;
	let stale = match cache.as_ref() {
		Some((built, _)) => built.elapsed() >= REFRESH,
		None => true,
	};
	if stale {
		*cache = Some((Instant::now(), build()));
	}
	cache
		.as_ref()
		.and_then(|(_, map)| map.get(&canonical).cloned())
}

#[cfg(test)]
mod tests {
	use super::read_descriptor;
	use std::fs;

	#[test]
	fn reads_a_file_descriptor() {
		let dir = std::env::temp_dir().join(format!(
			"hishell-file-descriptor-test-{}",
			std::process::id()
		));
		fs::create_dir_all(&dir).unwrap();
		let target = dir.join("game.nds");
		fs::write(&target, b"not really a rom").unwrap();
		let descriptor = dir.join("game.desktop");
		fs::write(
			&descriptor,
			format!(
				"[Desktop Entry]\nType=File\nPath={}\nName=Test Game\nIcon=application-x-nintendo-ds-rom\n",
				target.display()
			),
		)
		.unwrap();

		let (path, entry) = read_descriptor(&descriptor).unwrap();
		assert_eq!(path, fs::canonicalize(&target).unwrap());
		assert_eq!(entry.name.as_deref(), Some("Test Game"));
		assert_eq!(entry.icon.as_deref(), Some("application-x-nintendo-ds-rom"));

		fs::remove_dir_all(dir).unwrap();
	}

	#[test]
	fn a_file_descriptor_does_not_describe_a_directory() {
		let dir = std::env::temp_dir().join(format!("hishell-kind-test-{}", std::process::id()));
		fs::create_dir_all(&dir).unwrap();
		let descriptor = dir.join("wrong.desktop");
		fs::write(
			&descriptor,
			format!(
				"[Desktop Entry]\nType=File\nPath={}\nName=Not a file\n",
				dir.display()
			),
		)
		.unwrap();

		assert!(read_descriptor(&descriptor).is_none());

		fs::remove_dir_all(dir).unwrap();
	}
}
