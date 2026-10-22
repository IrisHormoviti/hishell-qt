//! What deleting a path means.
//!
//! Hishell already has one gate for "is this the user's to remove":
//! [`desktop_entry::DesktopEntry::is_destroyable`].  This module turns that gate
//! into the choices the delete warning offers — trash, reset, unmount — and
//! performs the non-trash ones.  Nothing here knows that ClamOS exists: a
//! section is just a generated `.directory`, and a mounted device is just a
//! directory descriptor with an `Unmount=` command.
//!
//! See `docs/clam-configd.md` §5 and §7.2.

use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};

use crate::desktop_entry;
use crate::directory_descriptor;

/// The choices the warning can offer for one path.  Serialized for QML.
#[derive(Clone, Debug, Default, Serialize)]
pub struct Options {
	/// Ordinary Trash is possible (running `Destroy=` first when there is one).
	pub destroy: bool,
	/// The section has a `Reset=` command; reset keeps the handle.
	pub reset: bool,
	/// A descriptor gives an `Unmount=` command for this path.
	pub unmount: bool,
	/// The path is a settings section (or the user's symlink to one).  Its
	/// delete action is a choice even when the handle itself can be trashed:
	/// removing the link and resetting the section are different wants.
	pub section: bool,
	pub title: String,
	pub path: String,
}

/// Classify `path` for the Trash action and the drag downgrade.
pub fn options(path: &Path) -> Options {
	let descriptor = directory_descriptor::lookup(path);
	let unmount = descriptor
		.as_ref()
		.and_then(|descriptor| descriptor.unmount.as_deref())
		.map(str::to_string);
	let entry = desktop_entry::read(path);
	// A symlink is the user's handle, not the thing it names.  Trashing it
	// removes the handle and leaves the section, profile or device alone; a
	// managed device link is still special because its mounter would recreate
	// it, so that one offers unmount instead (docs §5.2, §5.5).
	let link = is_symlink(path);
	let destroy = (link || entry.is_destroyable()) && unmount.is_none();
	// A mounted device's warning offers unmount, not reset: whatever the
	// filesystem on the card happens to contain, the device is not a section.
	let reset = unmount.is_none() && reset_command(path).is_some();
	// `read` follows a symlink, so a handle to a generated section counts as
	// one: the warning must still offer both removing the handle and resetting
	// the section behind it (docs §5.2).
	let section = path.is_dir() && desktop_entry::read(path).generated;
	Options {
		destroy,
		reset,
		unmount: unmount.is_some(),
		section,
		title: crate::directory::get_item_title(path),
		path: path.to_string_lossy().into_owned(),
	}
}

/// The single question the drag path asks: may this source be copied or moved,
/// or must it degrade to a link?
pub fn can_destroy(path: &Path) -> bool {
	options(path).destroy
}

/// Whether `path` itself is a symbolic link (without following it).
fn is_symlink(path: &Path) -> bool {
	fs::symlink_metadata(path)
		.map(|metadata| metadata.file_type().is_symlink())
		.unwrap_or(false)
}

/// The `Reset=` command belonging to `path`: the section's own `.directory` for
/// a folder, or the containing section's for an entry inside it.
pub fn reset_command(path: &Path) -> Option<String> {
	let config = if path.is_dir() {
		path.join(".directory")
	} else {
		path.parent()?.join(".directory")
	};
	crate::config::get_entry_string(&config, "Reset")
		.map(|command| command.trim().to_string())
		.filter(|command| !command.is_empty())
}

/// Reset a section, keeping its handle: run the generated `Reset=` command.
pub fn reset(path: &Path) -> bool {
	let Some(command) = reset_command(path) else {
		return false;
	};
	let directory = if path.is_dir() {
		path.to_path_buf()
	} else {
		match path.parent() {
			Some(parent) => parent.to_path_buf(),
			None => return false,
		}
	};
	desktop_entry::run_reset(&directory, &command)
}

/// Unmount a described device: run its descriptor's `Unmount=` command.
pub fn unmount(path: &Path) -> bool {
	let Some(descriptor) = directory_descriptor::lookup(path) else {
		return false;
	};
	let Some(command) = descriptor.unmount else {
		return false;
	};
	let name = descriptor.name.unwrap_or_else(|| {
		path.file_name()
			.map(|name| name.to_string_lossy().into_owned())
			.unwrap_or_default()
	});
	desktop_entry::run_hook(&command, path, &name)
}

/// The section whose `.directory` an entry belongs to, for tests and callers
/// that need the containing folder rather than the entry's path.
#[allow(dead_code)]
pub fn section_of(path: &Path) -> Option<PathBuf> {
	if path.is_dir() {
		Some(path.to_path_buf())
	} else {
		path.parent().map(Path::to_path_buf)
	}
}

#[cfg(test)]
mod tests {
	use super::{options, reset_command};
	use std::fs;
	use std::os::unix::fs::symlink;
	use std::path::PathBuf;

	fn scratch(name: &str) -> PathBuf {
		let dir = std::env::temp_dir().join(format!("{name}-{}", std::process::id()));
		fs::remove_dir_all(&dir).ok();
		fs::create_dir_all(&dir).unwrap();
		dir
	}

	#[test]
	fn a_generated_section_offers_reset_and_its_handle_belongs_to_the_user() {
		let dir = scratch("hishell-destroy-section");
		let section = dir.join("Themes");
		fs::create_dir(&section).unwrap();
		fs::write(
			section.join(".directory"),
			"[Desktop Entry]\nType=Directory\nGenerated=true\nName=Themes\nReset=/bin/true\n",
		)
		.unwrap();
		let handle = dir.join("themes-link");
		symlink(&section, &handle).unwrap();

		let plain = options(&section);
		assert!(!plain.destroy);
		assert!(plain.reset);
		assert!(plain.section);

		let linked = options(&handle);
		assert!(
			linked.destroy,
			"the handle is the user's, even though its target is generated"
		);
		assert!(linked.reset);
		assert!(
			linked.section,
			"a settings handle still warns about removing it or resetting it"
		);
		assert_eq!(linked.title, "Themes");

		assert_eq!(reset_command(&handle).as_deref(), Some("/bin/true"));
		fs::remove_dir_all(&dir).ok();
	}

	#[test]
	fn an_ordinary_file_is_still_destroyable() {
		let dir = scratch("hishell-destroy-file");
		let file = dir.join("notes.txt");
		fs::write(&file, "hello\n").unwrap();
		let options = options(&file);
		assert!(options.destroy);
		assert!(!options.reset);
		assert!(!options.unmount);
		assert!(!options.section);
		fs::remove_dir_all(&dir).ok();
	}

	#[test]
	fn a_generated_entry_with_no_destroy_offers_its_section_reset() {
		let dir = scratch("hishell-destroy-entry");
		let section = dir.join("Wi-Fi");
		fs::create_dir(&section).unwrap();
		fs::write(
			section.join(".directory"),
			"[Desktop Entry]\nType=Directory\nGenerated=true\nReset=clam-connect wifi --reset\n",
		)
		.unwrap();
		let entry = section.join("network.desktop");
		fs::write(
			&entry,
			"[Desktop Entry]\nType=Button\nGenerated=true\nName=Visible network\n",
		)
		.unwrap();

		let options = options(&entry);
		assert!(!options.destroy);
		assert!(options.reset);
		fs::remove_dir_all(&dir).ok();
	}
}
