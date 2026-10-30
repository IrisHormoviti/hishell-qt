use once_cell::sync::Lazy;
use qmetaobject::prelude::*;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};
use trash;

static INTERNAL_CLIPBOARD: Lazy<Mutex<Option<(Vec<String>, bool)>>> =
	Lazy::new(|| Mutex::new(None));

/// Non-zero when the shell should run its frame/scan instrumentation. Set
/// `HISHELL_PERF=1` in the environment, or create `/run/clam/perf`, which is
/// handy on a running device (it is a tmpfs marker, gone after a reboot).
pub fn perf_mode() -> i32 {
	static MODE: OnceLock<i32> = OnceLock::new();
	*MODE.get_or_init(|| {
		if let Ok(value) = std::env::var("HISHELL_PERF")
			&& let Ok(mode) = value.trim().parse::<i32>()
			&& mode > 0
		{
			return mode;
		}
		if Path::new("/run/clam/perf-detailed").exists() {
			return 2;
		}
		if let Some(config) = dirs::config_dir() {
			// Persistent markers for a device under test: they live with the
			// rest of the user configuration and survive an A/B update of the
			// rootfs. Mode 2 adds a line per delegate creation, so it is only
			// for diagnosing where a scan's time goes.
			if config.join("clam/perf-detailed").exists() {
				return 2;
			}
			if config.join("clam/perf-focus").exists() {
				return 5;
			}
			// Animated navigation comparison: top-level folders against the
			// folders under /home (see PerfBench.qml, mode 6).
			if config.join("clam/perf-nav").exists() {
				return 6;
			}
			// Per-setting cost of a view-config change (PerfBench.qml, mode 7).
			if config.join("clam/perf-cfg").exists() {
				return 7;
			}
			// Launch-transition screenshot test (PerfBench.qml, mode 8).
			if config.join("clam/perf-anim").exists() {
				return 8;
			}
			if config.join("clam/perf-grab").exists() {
				return 4;
			}
			if config.join("clam/perf").exists() {
				return 1;
			}
		}
		if Path::new("/run/clam/perf").exists() {
			return 1;
		}
		0
	})
}

/// How long a virtual folder gets to consume an accepted drop before the shell
/// calls the name it left behind ignored.  A Wi-Fi install removes its staged
/// keyfile as soon as the copy is written, so this is normally only paid by a
/// drop the provider declines.
const DROP_SETTLE: Duration = Duration::from_millis(1500);

fn rename_status(ok: bool, error: &str) -> String {
	serde_json::json!({ "ok": ok, "error": error }).to_string()
}

fn clean_path(s: &str) -> String {
	let trimmed = s.trim();
	let raw = trimmed.strip_prefix("file://").unwrap_or(trimmed);
	let raw = raw.strip_prefix("localhost").unwrap_or(raw);
	let decoded = percent_decode(raw);
	if decoded.len() > 1 && decoded.ends_with('/') {
		decoded.trim_end_matches('/').to_string()
	} else {
		decoded
	}
}

fn unique_path(parent: &Path, base_name: &str, suffix: &str) -> PathBuf {
	let path = Path::new(base_name);
	let stem = path
		.file_stem()
		.and_then(|s| s.to_str())
		.unwrap_or(base_name);
	let ext = path
		.extension()
		.and_then(|e| e.to_str())
		.map(|e| format!(".{}", e))
		.unwrap_or_default();

	let candidate = parent.join(format!("{}{}{}", stem, suffix, ext));
	if !candidate.exists() {
		return candidate;
	}

	for idx in 2..1000 {
		let candidate = parent.join(format!("{}{} {}{}", stem, suffix, idx, ext));
		if !candidate.exists() {
			return candidate;
		}
	}
	parent.join(format!("{}{}_{}{}", stem, suffix, std::process::id(), ext))
}

/// Whether `path` itself is a symlink, without following it.  A handle is
/// copied, moved and trashed as a link, never as the settings or device it
/// names (docs §5.4, §7.2).
fn is_symlink(path: &Path) -> bool {
	fs::symlink_metadata(path)
		.map(|metadata| metadata.file_type().is_symlink())
		.unwrap_or(false)
}

/// Whether `path` is a provider-owned virtual folder.  Its contents are a view
/// of machine state, and a write is a request the provider may ignore rather
/// than storage, so a move into it must not remove the source.
fn is_virtual_folder(path: &Path) -> bool {
	if !path.is_dir() {
		return false;
	}
	crate::desktop_entry::read(&path.join(".directory")).generated
}

/// Whether a provider entry changes its display label rather than its file
/// name.  A symlink is always the user's handle, even when it points at such an
/// entry: renaming it renames the link.
fn rename_is_label_only(path: &Path) -> bool {
	if is_symlink(path) || path.is_dir() {
		return false;
	}
	let entry = crate::desktop_entry::read(path);
	entry.generated && entry.rename_command().is_some()
}

/// Whether Rename may be offered for `path`.
///
/// Ordinary files and folders are the user's to rename, and so is a symlink
/// handle.  Anything the provider owns is a view of machine state: it may be
/// renamed only when the provider writes a `Rename=` command, which today means
/// a paired Bluetooth device changing its label (docs `clam-configd.md` §5.7).
fn can_rename(path: &Path) -> bool {
	// The mounter owns a mounted device's link (§5.5): renaming it would only
	// leave a stray handle for `clam-removable.sh` to reconcile.  It has an
	// honest delete action (unmount), but no honest rename.
	if crate::directory_descriptor::lookup(path)
		.and_then(|descriptor| descriptor.unmount)
		.is_some()
	{
		return false;
	}
	if is_symlink(path) {
		return true;
	}
	if rename_is_label_only(path) {
		return true;
	}
	let entry = crate::desktop_entry::read(path);
	if entry.generated || is_virtual_folder(path) {
		return false;
	}
	!path.parent().is_some_and(is_virtual_folder)
}

/// Copy a source without ever following a symlink into its target.
fn copy_for_user(src: &Path, dst: &Path) -> bool {
	if is_symlink(src) {
		return link_item(src, dst);
	}
	if src.is_dir() {
		copy_dir_recursive(src, dst)
	} else {
		fs::copy(src, dst).is_ok()
	}
}

/// Whether a write into a virtual folder was kept by its provider.
///
/// The provider sees a write as a request.  It either lists the name (a theme
/// bundle is stored in the folder itself) or consumes it (a Wi-Fi profile is
/// installed and its staged keyfile removed).  A name that is still in the
/// mount but never listed was accepted by the filesystem and ignored by the
/// provider, so the shell says so instead of letting the drop vanish.
fn drop_was_kept(dir: &Path, name: &str) -> bool {
	let present = fs::symlink_metadata(dir.join(name)).is_ok();
	let listed = fs::read_dir(dir)
		.map(|entries| {
			entries
				.flatten()
				.any(|entry| entry.file_name().to_string_lossy() == name)
		})
		.unwrap_or(false);
	drop_kept(present, listed)
}

/// A consumed name is kept (the provider installed it), and a listed name is
/// kept (the provider stored it).  Only a name that is present but unlisted was
/// accepted and then ignored.
fn drop_kept(present: bool, listed: bool) -> bool {
	!present || listed
}

/// Remember the name a virtual-folder copy landed under, for a single wait
/// shared by the whole drop rather than one wait per file.
fn note_virtual_drop(pending: &mut Vec<(PathBuf, String)>, dir: &Path, dst: &Path) {
	if let Some(name) = dst.file_name() {
		pending.push((dir.to_path_buf(), name.to_string_lossy().into_owned()));
	}
}

#[derive(QObject, Default)]
pub struct FileManager {
	base: qt_base_class!(trait QObject),

	/// A drop into a virtual folder was accepted by the filesystem and then
	/// ignored by the provider.  QML says so instead of leaving the user to
	/// wonder where the file went.
	drop_declined: qt_signal!(name: String),

	/// Bumped after an icon PNG is rendered on an idle tick. QML bindings that
	/// read it re-resolve the item's icon from the themed fallback to the
	/// cached image.
	icon_revision: qt_property!(i32; NOTIFY icon_revision_changed),
	icon_revision_changed: qt_signal!(),

	copy_file: qt_method!(
		fn copy_file(&self, source: String, dest: String) -> bool {
			let src = clean_path(&source.to_string());
			let dst = clean_path(&dest.to_string());
			if is_symlink(Path::new(&src)) {
				return link_item(Path::new(&src), Path::new(&dst));
			}
			fs::copy(src, dst).is_ok()
		}
	),

	duplicate_file: qt_method!(
		fn duplicate_file(&self, source: String) -> bool {
			let p = clean_path(&source.to_string());
			let path = Path::new(&p);
			if !path.exists() {
				return false;
			}
			let parent = match path.parent() {
				Some(parent) => parent,
				None => return false,
			};
			let fname = match path.file_name() {
				Some(name) => name.to_string_lossy().to_string(),
				None => return false,
			};
			// Duplicating a handle duplicates the link, never the section,
			// profile or device behind it.
			if is_symlink(path) {
				let dest = unique_path(parent, &fname, " (link)");
				return link_item(path, &dest);
			}
			// Duplicate is a copy: a source that is not the user's to destroy
			// must not be materialised, because a virtual folder's copy would
			// be a real folder full of projections (docs §5.4, §7.2).
			if !crate::destroy::can_destroy(path) {
				let dest = unique_path(parent, &fname, " (link)");
				return link_item(path, &dest);
			}
			let dest = unique_path(parent, &fname, " (copy)");
			if path.is_dir() {
				copy_dir_recursive(path, &dest)
			} else {
				fs::copy(path, &dest).is_ok()
			}
		}
	),

	new_folder: qt_method!(
		fn new_folder(&self, parent: String) -> bool {
			let parent_string = clean_path(&parent.to_string());
			let parent_path = Path::new(&parent_string);
			if !parent_path.is_dir() {
				return false;
			}

			let base_name = "New Folder";
			let mut candidate = parent_path.join(base_name);
			if candidate.exists() {
				let mut created = false;
				for idx in 1..100 {
					let next = parent_path.join(format!("{} {}", base_name, idx));
					if !next.exists() {
						candidate = next;
						created = true;
						break;
					}
				}
				if !created {
					return false;
				}
			}

			fs::create_dir(&candidate).is_ok()
		}
	),

	new_text_file: qt_method!(
		fn new_text_file(&self, parent: String) -> bool {
			let parent_string = clean_path(&parent.to_string());
			let parent_path = Path::new(&parent_string);
			if !parent_path.is_dir() {
				return false;
			}

			let base_name = "New Text File";
			let mut candidate = parent_path.join(format!("{}.txt", base_name));
			if candidate.exists() {
				let mut created = false;
				for idx in 1..100 {
					let next = parent_path.join(format!("{} {}.txt", base_name, idx));
					if !next.exists() {
						candidate = next;
						created = true;
						break;
					}
				}
				if !created {
					return false;
				}
			}

			std::fs::File::create(&candidate).is_ok()
		}
	),

	create_link: qt_method!(
		fn create_link(&self, source: String, dest: String) -> bool {
			let src = clean_path(&source.to_string());
			let src_path = Path::new(&src);
			if !src_path.exists() {
				return false;
			}
			let dst_str = clean_path(&dest.to_string());
			let dst = if dst_str.is_empty() {
				match (src_path.parent(), src_path.file_name()) {
					(Some(parent), Some(name)) => {
						unique_path(parent, &name.to_string_lossy(), " (link)")
					}
					_ => return false,
				}
			} else {
				let dst_path = Path::new(&dst_str);
				if dst_path.exists() {
					match (dst_path.parent(), dst_path.file_name()) {
						(Some(parent), Some(name)) => {
							unique_path(parent, &name.to_string_lossy(), " (link)")
						}
						_ => dst_path.to_path_buf(),
					}
				} else {
					dst_path.to_path_buf()
				}
			};
			link_item(src_path, &dst)
		}
	),

	/// Move a file/directory to the system trash.
	///
	/// A generated desktop entry belongs to the provider that wrote it, so it
	/// cannot simply be moved: when it declares a `Destroy=` command that command
	/// runs instead (deleting the profile and the file together).  Anything the
	/// provider marks as not-the-user's is refused here; the QML warning offers
	/// reset/unmount instead (docs `clam-configd.md` §5).  A symlink is the
	/// user's handle: it is trashed itself, never its target.
	trash_file: qt_method!(
		fn trash_file(&self, path: String) -> bool {
			let p = clean_path(&path.to_string());
			let path = Path::new(&p);
			if !crate::destroy::can_destroy(path) {
				return false;
			}
			// The link is the user's handle.  Reading through it here would
			// find the section's or entry's `Destroy=` and forget the thing it
			// names instead of deleting the handle.
			if is_symlink(path) {
				return trash::delete(path).is_ok();
			}
			let entry = crate::desktop_entry::read(path);
			if let Some(command) = entry.destroy_command() {
				return crate::desktop_entry::run_destroy(path, &entry, command);
			}
			trash::delete(path).is_ok()
		}
	),

	/// Whether the file views may offer ordinary Trash/Cut for this path.  A
	/// false result is not "nothing can be done": the delete warning uses
	/// `destroy_options` to offer reset/unmount instead (§5).
	can_destroy: qt_method!(
		fn can_destroy(&self, path: String) -> bool {
			let p = clean_path(&path.to_string());
			crate::destroy::can_destroy(Path::new(&p))
		}
	),

	/// The delete warning's choices for one path, as JSON:
	/// `{destroy, reset, unmount, title, path}`.  "destroy" means the ordinary
	/// Trash path is possible; the other flags are the alternatives the source
	/// allows (docs `clam-configd.md` §5.2, §5.5).
	destroy_options: qt_method!(
		fn destroy_options(&self, path: String) -> String {
			let p = clean_path(&path.to_string());
			serde_json::to_string(&crate::destroy::options(Path::new(&p))).unwrap_or_default()
		}
	),

	/// Reset a section through its generated `Reset=` command, keeping the
	/// handle.
	reset_file: qt_method!(
		fn reset_file(&self, path: String) -> bool {
			let p = clean_path(&path.to_string());
			crate::destroy::reset(Path::new(&p))
		}
	),

	/// Unmount a described device through its descriptor's `Unmount=` command.
	unmount_file: qt_method!(
		fn unmount_file(&self, path: String) -> bool {
			let p = clean_path(&path.to_string());
			crate::destroy::unmount(Path::new(&p))
		}
	),

	/// Permanently delete a file or directory (no trash).
	delete_file: qt_method!(
		fn delete_file(&self, path: String) -> bool {
			let p = clean_path(&path.to_string());
			let p = Path::new(&p);
			if is_symlink(p) {
				fs::remove_file(p).is_ok()
			} else if p.is_dir() {
				fs::remove_dir_all(p).is_ok()
			} else {
				fs::remove_file(p).is_ok()
			}
		}
	),

	/// Whether the Rename action may be offered for this path.  Virtual
	/// entries are read-only views, except where the provider declares a
	/// `Rename=` command (a paired Bluetooth device's label).
	can_rename: qt_method!(
		fn can_rename(&self, path: String) -> bool {
			let p = clean_path(&path.to_string());
			can_rename(Path::new(&p))
		}
	),

	/// Whether activating this entry should begin the rename flow: a
	/// provider's label-only control with no command of its own (the user
	/// name in the profile folder).
	is_rename_only: qt_method!(
		fn is_rename_only(&self, path: String) -> bool {
			let p = clean_path(&path.to_string());
			crate::desktop_entry::is_rename_only(Path::new(&p))
		}
	),

	/// The text the rename request starts with: the file name for ordinary
	/// items, or the entry's current display label where `Rename=` applies.
	rename_display_name: qt_method!(
		fn rename_display_name(&self, path: String) -> String {
			let p = clean_path(&path.to_string());
			let path = Path::new(&p);
			let file_name = path
				.file_name()
				.map(|name| name.to_string_lossy().into_owned())
				.unwrap_or_default();
			if rename_is_label_only(path) {
				crate::desktop_entry::read(path)
					.name
					.filter(|name| !name.is_empty())
					.unwrap_or(file_name)
			} else {
				file_name
			}
		}
	),

	/// Whether a successful rename changes the path (and so any remembered
	/// free-placement position), or only the provider's display label.
	rename_moves_path: qt_method!(
		fn rename_moves_path(&self, path: String) -> bool {
			let p = clean_path(&path.to_string());
			!rename_is_label_only(Path::new(&p))
		}
	),

	/// Ask the system keyboard for a string. Returns the request id, or an
	/// empty string when no keyboard is available; callers then use their own
	/// dialog, which is also the path on a system without ClamOS.
	request_text_entry: qt_method!(
		fn request_text_entry(&self, prompt: String, text: String, cursor: String) -> String {
			crate::keyboard::request(&prompt, &text, &cursor).unwrap_or_default()
		}
	),

	/// The outcome of a request as JSON: `{"status":"pending"}`,
	/// `{"status":"ok","text":"..."}` or `{"status":"cancel"}`.
	poll_text_entry: qt_method!(
		fn poll_text_entry(&self, id: String) -> String {
			match crate::keyboard::poll(&id) {
				crate::keyboard::Poll::Pending => {
					serde_json::json!({ "status": "pending" }).to_string()
				}
				crate::keyboard::Poll::Accepted(text) => {
					serde_json::json!({ "status": "ok", "text": text }).to_string()
				}
				crate::keyboard::Poll::Cancelled => {
					serde_json::json!({ "status": "cancel" }).to_string()
				}
			}
		}
	),

	/// Withdraw a request the keyboard has not answered yet.
	cancel_text_entry: qt_method!(
		fn cancel_text_entry(&self, id: String) {
			crate::keyboard::cancel(&id);
		}
	),

	/// Whether the system keyboard is running. The shell polls this while a
	/// request is pending, so it can fall back to its dialog if the keyboard
	/// dies or was never there.
	keyboard_available: qt_method!(
		fn keyboard_available(&self) -> bool {
			crate::keyboard::available()
		}
	),

	/// Rename a file or directory, or change a provider entry's label through
	/// its `Rename=` command.  Returns a JSON status object:
	/// `{"ok":bool,"error":string}`.
	rename_file: qt_method!(
		fn rename_file(&self, path: String, new_name: String) -> String {
			let p = clean_path(&path.to_string());
			let n = new_name.trim().to_string();
			let src = Path::new(&p);
			let parent = match src.parent() {
				Some(parent) => parent,
				None => return rename_status(false, "Invalid path."),
			};
			if n.is_empty() {
				return rename_status(false, "Name cannot be empty.");
			}
			if n.contains('/') {
				return rename_status(false, "A name cannot contain \"/\".");
			}
			if !can_rename(src) {
				return rename_status(
					false,
					"This item belongs to the system and cannot be renamed.",
				);
			}
			if rename_is_label_only(src) {
				let entry = crate::desktop_entry::read(src);
				let Some(command) = entry.rename_command() else {
					return rename_status(
						false,
						"This item belongs to the system and cannot be renamed.",
					);
				};
				return match crate::desktop_entry::run_rename(src, &entry, command, &n) {
					Ok(()) => rename_status(true, ""),
					Err(error) => rename_status(false, &error),
				};
			}
			let dest = parent.join(&n);
			if dest.exists() && dest != src {
				return rename_status(false, "A file with that name already exists.");
			}
			match crate::kde_bridge::rename(&p, &n) {
				Ok(()) => rename_status(true, ""),
				Err(error) => rename_status(false, error.as_str()),
			}
		}
	),

	/// Copy the given newline-separated list of paths to the system clipboard
	/// using the freedesktop "copy" URI list format (compatible with Nautilus, Dolphin, Thunar, etc.).
	/// Falls back gracefully if no clipboard tool is available.
	copy_paths_to_clipboard: qt_method!(
		fn copy_paths_to_clipboard(&self, paths_newline: String) -> bool {
			let paths = paths_newline.to_string();
			let uris: Vec<String> = paths
				.lines()
				.filter(|l| !l.trim().is_empty())
				.map(|p| clean_path(p))
				.filter(|p| !p.is_empty())
				.collect();
			if !uris.is_empty() {
				if let Ok(mut guard) = INTERNAL_CLIPBOARD.lock() {
					*guard = Some((uris, false));
				}
			}
			set_clipboard_uris(&paths, false)
		}
	),

	/// Cut: same as copy but writes the "cut" action to the clipboard.
	cut_paths_to_clipboard: qt_method!(
		fn cut_paths_to_clipboard(&self, paths_newline: String) -> bool {
			let paths = paths_newline.to_string();
			let uris: Vec<String> = paths
				.lines()
				.filter(|l| !l.trim().is_empty())
				.map(|p| clean_path(p))
				.filter(|p| !p.is_empty())
				.collect();
			if !uris.is_empty() {
				if let Ok(mut guard) = INTERNAL_CLIPBOARD.lock() {
					*guard = Some((uris, true));
				}
			}
			set_clipboard_uris(&paths, true)
		}
	),

	/// Paste files from the system clipboard (text/uri-list) into dest_dir.
	/// Returns true if at least one file was copied successfully.
	paste_from_clipboard: qt_method!(
		fn paste_from_clipboard(&self, dest_dir: String) -> bool {
			let dest = clean_path(&dest_dir.to_string());
			let dest_path = Path::new(&dest);
			if !dest_path.is_dir() {
				return false;
			}
			let (uris, is_cut) = read_clipboard_uris_and_action();
			if uris.is_empty() {
				return false;
			}
			let mut pending = Vec::new();
			let ok = if is_cut {
				cut_into(dest_path, &uris, &mut pending)
			} else {
				let uris_str = uris.join("\n");
				self.process_uris_action(
					String::from(dest.as_str()),
					String::from(uris_str.as_str()),
					String::from("copy"),
				)
			};
			self.report_declined_drops(pending);
			if ok && is_cut {
				if let Ok(mut guard) = INTERNAL_CLIPBOARD.lock() {
					*guard = None;
				}
			}
			ok
		}
	),

	/// Return MIME type string for a file path (guessed via mime_guess).
	get_mime_type: qt_method!(
		fn get_mime_type(&self, path: String) -> String {
			let p = clean_path(&path.to_string());
			let mime = mime_guess::from_path(&p)
				.first_or_octet_stream()
				.essence_str()
				.to_string();
			String::from(mime.as_str())
		}
	),

	/// Return text file content (capped at 64KB) for text/plain drag payload.
	get_text_content: qt_method!(
		fn get_text_content(&self, path: String) -> String {
			let p = clean_path(&path.to_string());
			let path_buf = Path::new(&p);
			if path_buf.is_file() {
				if let Ok(meta) = fs::metadata(path_buf) {
					if meta.len() <= 64 * 1024 {
						if let Ok(content) = fs::read_to_string(path_buf) {
							return String::from(content.as_str());
						}
					}
				}
			}
			String::default()
		}
	),

	/// Process URIs list with specified action ("copy", "move", "link") into dest_dir.
	process_uris_action: qt_method!(
		fn process_uris_action(
			&self,
			dest_dir: String,
			uris_newline: String,
			action: String,
		) -> bool {
			let dest = clean_path(&dest_dir.to_string());
			let dest_path = Path::new(&dest);
			if !dest_path.is_dir() {
				return false;
			}
			let raw_uris = uris_newline.to_string();
			let uris = parse_uri_list(&raw_uris);
			if uris.is_empty() {
				return false;
			}
			// A virtual folder is a view whose provider may accept a write and
			// then ignore it.  Moving into one would delete the source while the
			// dropped file never appears, so the shell copies instead and keeps
			// the user's original (docs §3.5, §5.4).
			let virtual_dest = is_virtual_folder(dest_path);
			let action_str = if action == "move" && virtual_dest {
				"copy".to_string()
			} else {
				action.to_string()
			};
			let mut any_ok = false;
			let mut pending = Vec::new();
			for uri in &uris {
				let src_str = clean_path(uri);
				let src = Path::new(&src_str);
				if !src.exists() {
					continue;
				}
				let Some(fname_os) = src.file_name() else {
					continue;
				};
				let fname = fname_os.to_string_lossy().to_string();
				let dst = dest_path.join(&fname);
				// The one gate: a source that is not the user's to destroy is
				// never copied or moved.  Copying a view of machine state is
				// meaningless, and moving it would either unlink the only handle
				// or materialise a virtual folder through move_item()'s
				// copy-then-delete fallback (docs §5.4, §7.2).
				let destroyable = crate::destroy::can_destroy(src);
				match action_str.as_str() {
					"move" => {
						if src == dst {
							continue;
						}
						if !destroyable {
							if link_item(src, &dst) {
								any_ok = true;
								if virtual_dest {
									note_virtual_drop(&mut pending, dest_path, &dst);
								}
							}
							continue;
						}
						if move_for_user(src, &dst) {
							any_ok = true;
						}
					}
					"link" => {
						if link_item(src, &dst) {
							any_ok = true;
							if virtual_dest {
								note_virtual_drop(&mut pending, dest_path, &dst);
							}
						}
					}
					_ => {
						if !destroyable {
							if link_item(src, &dst) {
								any_ok = true;
								if virtual_dest {
									note_virtual_drop(&mut pending, dest_path, &dst);
								}
							}
							continue;
						}
						let dst = if src == dst || dst.exists() {
							unique_path(dest_path, &fname, " (copy)")
						} else {
							dst
						};
						if copy_for_user(src, &dst) {
							any_ok = true;
							if virtual_dest {
								note_virtual_drop(&mut pending, dest_path, &dst);
							}
						}
					}
				}
			}
			self.report_declined_drops(pending);
			any_ok
		}
	),

	open_file: qt_method!(
		fn open_file(&self, path: String) -> bool {
			let p = clean_path(&path.to_string());
			crate::directory::open_file(p);
			true
		}
	),

	get_icon: qt_method!(
		pub fn get_icon(&self, path: String) -> String {
			crate::directory::get_icon(&path)
		}
	),

	/// The item's display title: the `Name` from its `.directory` (or desktop
	/// entry / AppImage) when it has one, otherwise its file name.
	get_item_title: qt_method!(
		pub fn get_item_title(&self, path: String) -> String {
			crate::directory::get_item_title(std::path::Path::new(&path))
		}
	),

	/// Build the confirmation a launch dialog shows when the execution wrapper
	/// reports that starting `launch_item` would close a suspended app for
	/// `blocked_item`. JSON: {title, message, blockedTitle, blockedIcon,
	/// blockedLaunchIcon, launchTitle, launchIcon}; empty string when there is
	/// nothing to confirm.
	launch_warning: qt_method!(
		fn launch_warning(&self, blocked_item: String, launch_item: String) -> String {
			let blocked_item = clean_path(&blocked_item.to_string());
			let launch_item = clean_path(&launch_item.to_string());
			if blocked_item.is_empty() {
				return String::new();
			}
			let blocked_title = crate::launch::item_title(&blocked_item);
			let launch_title = crate::launch::item_title(&launch_item);
			let message = format!(
				"Close \"{blocked_title}\" and launch \"{launch_title}\"?\nAny unsaved data will be lost."
			);
			serde_json::json!({
				"message": message,
				"blockedTitle": blocked_title,
				"blockedIcon": crate::launch::item_art(&blocked_item),
				"launchTitle": launch_title,
				"launchIcon": crate::launch::item_art(&launch_item),
			})
			.to_string()
		}
	),

	/// Ask the XDG desktop portal to let the user pick an application and launch it.
	/// Returns false when the portal is unavailable (the built-in dialog should be used).
	start_portal_open_with: qt_method!(
		fn start_portal_open_with(&self, path: String) -> bool {
			let p = clean_path(&path.to_string());
			crate::kde_bridge::portal_open_with(&p)
		}
	),

	/// Poll the pending portal request: 0 = finished, 1 = pending, 2 = failed (fall back to the dialog).
	poll_portal_open_with: qt_method!(
		fn poll_portal_open_with(&self) -> i32 {
			crate::kde_bridge::portal_poll()
		}
	),

	/// JSON with the default application for the file ({id, name, icon}; empty when none).
	/// Ask the execution wrapper to quit the focused guest and remove its
	/// saved state, if it has one.
	quit_active: qt_method!(
		fn quit_active(&self, path: String) -> bool {
			crate::launch::quit_active(&path)
		}
	),

	get_default_app: qt_method!(
		fn get_default_app(&self, path: String) -> String {
			let p = clean_path(&path.to_string());
			crate::kde_bridge::default_app_json(&p)
		}
	),

	/// List the applications registered for opening the file (JSON payload for the Open With dialog).
	get_open_with_apps: qt_method!(
		fn get_open_with_apps(&self, path: String) -> String {
			let p = clean_path(&path.to_string());
			crate::kde_bridge::apps_json(&p)
		}
	),

	/// Open the file with a specific application (desktop entry storage id).
	/// Returns a confirmation message when the execution wrapper asks for one.
	open_with_app: qt_method!(
		fn open_with_app(&self, path: String, app_id: String) -> String {
			let p = clean_path(&path.to_string());
			// Resolve the entry and spawn it here, so the launch goes through the
			// configured execution wrapper. Fall back to the portal launch when
			// the entry has no plain command (e.g. a D-Bus-activated app).
			if let Some((exec, entry)) = crate::kde_bridge::app_command(&app_id) {
				return crate::desktop_entry::launch_command(&exec, &entry, Some(&p));
			}
			crate::kde_bridge::launch(&app_id, &p);
			String::new()
		}
	),

	/// Finish a launch the execution wrapper held back for confirmation.
	confirm_launch: qt_method!(
		fn confirm_launch(&self) -> bool {
			crate::launch::confirm()
		}
	),

	/// Drop a launch the execution wrapper held back for confirmation.
	cancel_launch: qt_method!(
		fn cancel_launch(&self) {
			crate::launch::cancel();
		}
	),

	/// Set the application as the default handler for the file's MIME type (via XDG mimeapps.list).
	set_default_app: qt_method!(
		fn set_default_app(&self, mime: String, app_id: String) -> bool {
			crate::kde_bridge::set_default(&mime, &app_id)
		}
	),

	rotate_image: qt_method!(
		fn rotate_image(&self, path: String, degrees: i32) -> bool {
			let p = clean_path(&path.to_string());
			crate::image_utils::rotate_image(Path::new(&p), degrees)
		}
	),

	is_image_file: qt_method!(
		fn is_image_file(&self, path: String) -> bool {
			let p = clean_path(&path.to_string());
			crate::image_utils::is_image_file(Path::new(&p))
		}
	),

	is_directory: qt_method!(
		fn is_directory(&self, path: String) -> bool {
			let p = clean_path(&path.to_string());
			Path::new(&p).is_dir()
		}
	),

	/// Whether the entry is a `Type=Button` control rather than an app. A Button
	/// runs its `Exec` directly (no wrapper, no guest window), so the views give
	/// it the button sound and none of the app-launch transition (docs §6.2).
	is_button: qt_method!(
		fn is_button(&self, path: String) -> bool {
			let p = clean_path(&path.to_string());
			crate::desktop_entry::is_button(Path::new(&p))
		}
	),

	/// Whether this entry is any kind of control: a button or one of the
	/// settings controls the shell draws itself.
	is_control: qt_method!(
		fn is_control(&self, path: String) -> bool {
			let p = clean_path(&path.to_string());
			crate::desktop_entry::is_control(Path::new(&p))
		}
	),

	/// Whether this entry is a `Type=Toggle` switch.
	is_toggle: qt_method!(
		fn is_toggle(&self, path: String) -> bool {
			let p = clean_path(&path.to_string());
			crate::desktop_entry::is_toggle(Path::new(&p))
		}
	),

	/// The current state of a `Type=Toggle`; false for anything else.
	toggle_on: qt_method!(
		fn toggle_on(&self, path: String) -> bool {
			let p = clean_path(&path.to_string());
			crate::desktop_entry::toggle_state(Path::new(&p)).unwrap_or(false)
		}
	),

	/// Whether this entry is a `Type=Number` control.
	is_number: qt_method!(
		fn is_number(&self, path: String) -> bool {
			let p = clean_path(&path.to_string());
			crate::desktop_entry::is_number(Path::new(&p))
		}
	),

	/// The fields a `Type=Number` dialog shows, as JSON.
	number_spec: qt_method!(
		fn number_spec(&self, path: String) -> String {
			let p = clean_path(&path.to_string());
			let fields = crate::desktop_entry::number_fields(Path::new(&p));
			if fields.is_empty() {
				return String::from("{\"ok\":false}");
			}
			let fields: Vec<serde_json::Value> = fields
				.iter()
				.map(|field| {
					serde_json::json!({
						"label": field.label,
						"value": field.value,
						"min": field.min,
						"max": field.max,
						"default": field.default,
					})
				})
				.collect();
			serde_json::json!({ "ok": true, "fields": fields }).to_string()
		}
	),

	/// Flip a toggle and run its provider command.
	run_toggle: qt_method!(
		fn run_toggle(&self, path: String) -> bool {
			let p = clean_path(&path.to_string());
			crate::desktop_entry::run_toggle(Path::new(&p))
		}
	),

	/// Run a number control with the dialog's values, separated by commas or
	/// whitespace.
	run_number: qt_method!(
		fn run_number(&self, path: String, values: String) -> bool {
			let p = clean_path(&path.to_string());
			let values: Vec<i64> = values
				.split(|character: char| character == ',' || character.is_whitespace())
				.filter(|value| !value.is_empty())
				.filter_map(|value| value.parse::<i64>().ok())
				.collect();
			if values.is_empty() {
				return false;
			}
			crate::desktop_entry::run_number(Path::new(&p), &values)
		}
	),

	/// Switch the process icon theme at runtime.  The active ClamOS theme can
	/// declare `[Icons] Theme=`; ClamTheme calls this when it changes so the
	/// file tiles follow a dark theme without restarting the shell.
	set_icon_theme: qt_method!(
		fn set_icon_theme(&self, theme: String) -> bool {
			crate::kde_bridge::set_icon_theme(&theme)
		}
	),

	/// A folder icon recoloured to the current accent, as a cached `file://`
	/// PNG.  Breeze draws the folder body with its `ColorScheme-Accent` class,
	/// so this is how folders follow the accent the way KDE apps do.  Returns
	/// an empty string when the icon cannot be rendered, so the caller can keep
	/// the plain themed icon name.
	accent_icon: qt_method!(
		fn accent_icon(
			&self,
			name: String,
			size: i32,
			accent_r: i32,
			accent_g: i32,
			accent_b: i32,
			text_r: i32,
			text_g: i32,
			text_b: i32,
		) -> String {
			let clamp = |value: i32| value.clamp(0, 255) as u8;
			crate::kde_bridge::accent_icon(
				&name,
				size.max(1) as u32,
				(clamp(accent_r), clamp(accent_g), clamp(accent_b)),
				(clamp(text_r), clamp(text_g), clamp(text_b)),
			)
			.unwrap_or_default()
		}
	),

	/// Whether the shell should run its performance instrumentation, and in
	/// which mode. The QML benchmark only exists for development builds; in a
	/// normal boot this is zero and nothing runs.
	perf_mode: qt_method!(
		fn perf_mode(&self) -> i32 {
			perf_mode()
		}
	),

	/// Write one benchmark line to the shell log.
	perf_log: qt_method!(
		fn perf_log(&self, message: String) {
			eprintln!("hishell-perf: {}", message);
		}
	),

	/// Render one queued themed icon. Called from an idle timer so the GUI
	/// thread never pays for a batch of QIcon renders while the user is moving.
	render_icon_tick: qt_method!(
		fn render_icon_tick(&mut self) -> bool {
			if !crate::kde_bridge::render_pending_icon() {
				return false;
			}
			self.icon_revision = self.icon_revision.wrapping_add(1);
			self.icon_revision_changed();
			true
		}
	),

	icons_pending: qt_method!(
		fn icons_pending(&self) -> bool {
			crate::kde_bridge::has_pending_icons()
		}
	),

	get_home_directory: qt_method!(
		pub fn get_home_directory(&self) -> String {
			dirs::home_dir()
				.map(|path| path.to_string_lossy().into_owned())
				.unwrap_or_default()
		}
	),
}

impl FileManager {
	/// Give accepted drops a moment to be consumed, then tell QML about the
	/// names the virtual folder left behind.  The wait covers the whole drop so
	/// a multi-file drop does not pay it once per file.
	fn report_declined_drops(&self, pending: Vec<(PathBuf, String)>) {
		if pending.is_empty() {
			return;
		}
		let deadline = Instant::now() + DROP_SETTLE;
		let mut remaining = pending;
		loop {
			remaining.retain(|(dir, name)| !drop_was_kept(dir, name));
			if remaining.is_empty() || Instant::now() >= deadline {
				break;
			}
			std::thread::sleep(Duration::from_millis(50));
		}
		for (_, name) in remaining {
			self.drop_declined(name);
		}
	}
}

/// Carry out a Cut into `dest`, one URI at a time.
///
/// A generated entry that names a `Destroy=` command is not moved: for it,
/// Cut-then-Paste means *destroy* — the same thing Trash does — because moving
/// the file would leave the NetworkManager profile (or paired device) behind and
/// the provider would write the entry straight back (docs §6.3).  A source that
/// cannot be destroyed degrades to a link, exactly as a drag move does
/// (docs §5.4, §7.2), and everything else is an ordinary move.
fn cut_into(dest: &Path, uris: &[String], pending: &mut Vec<(PathBuf, String)>) -> bool {
	// Cut into a virtual folder is a copy for the same reason a drag is: the
	// provider owns the listing and may ignore the write entirely.
	let copy = is_virtual_folder(dest);
	let mut any_ok = false;
	for uri in uris {
		let src = Path::new(uri);
		if !src.exists() {
			continue;
		}
		let Some(name) = src.file_name() else {
			continue;
		};
		let dst = dest.join(name);
		if src == dst {
			continue;
		}
		if !crate::destroy::can_destroy(src) {
			if link_item(src, &dst) {
				any_ok = true;
				if copy {
					note_virtual_drop(pending, dest, &dst);
				}
			}
			continue;
		}
		let dst = if copy && dst.exists() {
			unique_path(dest, &name.to_string_lossy(), " (copy)")
		} else {
			dst
		};
		if copy {
			if copy_for_user(src, &dst) {
				any_ok = true;
				note_virtual_drop(pending, dest, &dst);
			}
		} else if move_for_user(src, &dst) {
			any_ok = true;
		}
	}
	any_ok
}

/// Move a destroyable source.  A generated entry is destroyed through its
/// `Destroy=` command; a symlink is only ever the link, so reading through it
/// must not replace the move with the target's destroy command.
fn move_for_user(src: &Path, dst: &Path) -> bool {
	if !is_symlink(src) {
		let entry = crate::desktop_entry::read(src);
		if let Some(command) = entry.destroy_command() {
			return crate::desktop_entry::run_destroy(src, &entry, command);
		}
	}
	move_item(src, dst)
}

/// Symbolically link `src` at `dst`.  If the name is taken, choose a unique
/// "… (link)" name beside it, the same way a copy does.
#[cfg(unix)]
fn link_item(src: &Path, dst: &Path) -> bool {
	let dst = if dst.exists() {
		match (dst.parent(), dst.file_name()) {
			(Some(parent), Some(name)) => unique_path(parent, &name.to_string_lossy(), " (link)"),
			_ => dst.to_path_buf(),
		}
	} else {
		dst.to_path_buf()
	};
	// Point at what the source names, not at the source symlink, so a copy of a
	// handle is independent of how long that particular handle survives.  A
	// canonicalize failure leaves `src` as-is.
	let target = fs::canonicalize(src).unwrap_or_else(|_| src.to_path_buf());
	std::os::unix::fs::symlink(target, dst).is_ok()
}

#[cfg(not(unix))]
fn link_item(_src: &Path, _dst: &Path) -> bool {
	false
}

fn move_item(src: &Path, dst: &Path) -> bool {
	if fs::rename(src, dst).is_ok() {
		return true;
	}
	// Fallback for cross-filesystem move.  A symlink is recreated at the
	// destination and unlinked here; it is never expanded into its target.
	if is_symlink(src) {
		return match (fs::read_link(src), dst.parent()) {
			(Ok(target), Some(parent)) if parent.is_dir() => {
				std::os::unix::fs::symlink(target, dst).is_ok() && fs::remove_file(src).is_ok()
			}
			_ => false,
		};
	}
	if src.is_dir() {
		if copy_dir_recursive(src, dst) {
			let _ = fs::remove_dir_all(src);
			return true;
		}
	} else if fs::copy(src, dst).is_ok() {
		let _ = fs::remove_file(src);
		return true;
	}
	false
}

fn copy_dir_recursive(src: &Path, dest: &Path) -> bool {
	// Never descend through a handle: its target may be a live mount.
	if is_symlink(src) {
		return link_item(src, dest);
	}
	if fs::create_dir_all(dest).is_err() {
		return false;
	}
	let entries = match fs::read_dir(src) {
		Ok(e) => e,
		Err(_) => return false,
	};
	for entry in entries.flatten() {
		let src_child = entry.path();
		let dest_child = dest.join(entry.file_name());
		if src_child.is_dir() {
			if !copy_dir_recursive(&src_child, &dest_child) {
				return false;
			}
		} else if fs::copy(&src_child, &dest_child).is_err() {
			return false;
		}
	}
	true
}

fn set_clipboard_uris(paths_newline: &str, cut: bool) -> bool {
	let action = if cut { "cut" } else { "copy" };
	let uris: Vec<String> = paths_newline
		.lines()
		.filter(|l| !l.trim().is_empty())
		.map(|p| {
			let clean = clean_path(p);
			format!("file://{}", clean)
		})
		.collect();

	if uris.is_empty() {
		return false;
	}

	let nautilus_data = format!("{}\n{}\n", action, uris.join("\n"));
	let uri_list = uris.join("\n");

	let mut any_ok = false;
	if try_wl_copy(&nautilus_data, "x-special/nautilus-clipboard") {
		any_ok = true;
	}
	if try_xclip(&nautilus_data, "x-special/nautilus-clipboard") {
		any_ok = true;
	}
	if !any_ok && try_xclip(&uri_list, "text/uri-list") {
		any_ok = true;
	}
	if !any_ok && try_xsel(&uri_list) {
		any_ok = true;
	}

	any_ok
}

fn try_wl_copy(data: &str, mime: &str) -> bool {
	Command::new("wl-copy")
		.arg("--type")
		.arg(mime)
		.stdin(std::process::Stdio::piped())
		.spawn()
		.ok()
		.and_then(|mut child| {
			use std::io::Write;
			child.stdin.as_mut()?.write_all(data.as_bytes()).ok()?;
			child.wait().ok()
		})
		.map(|s| s.success())
		.unwrap_or(false)
}

fn try_xclip(data: &str, mime: &str) -> bool {
	Command::new("xclip")
		.args(["-selection", "clipboard", "-t", mime, "-i"])
		.stdin(std::process::Stdio::piped())
		.spawn()
		.ok()
		.and_then(|mut child| {
			use std::io::Write;
			child.stdin.as_mut()?.write_all(data.as_bytes()).ok()?;
			child.wait().ok()
		})
		.map(|s| s.success())
		.unwrap_or(false)
}

fn try_xsel(data: &str) -> bool {
	Command::new("xsel")
		.args(["--clipboard", "--input"])
		.stdin(std::process::Stdio::piped())
		.spawn()
		.ok()
		.and_then(|mut child| {
			use std::io::Write;
			child.stdin.as_mut()?.write_all(data.as_bytes()).ok()?;
			child.wait().ok()
		})
		.map(|s| s.success())
		.unwrap_or(false)
}

fn parse_nautilus_clipboard(text: &str) -> (Vec<String>, bool) {
	let mut is_cut = false;
	let mut uris = Vec::new();
	for line in text.lines() {
		let trimmed = line.trim();
		if trimmed.is_empty()
			|| trimmed.starts_with('#')
			|| trimmed == "x-special/nautilus-clipboard"
		{
			continue;
		}
		if trimmed.eq_ignore_ascii_case("cut") {
			is_cut = true;
		} else if trimmed.eq_ignore_ascii_case("copy") {
			is_cut = false;
		} else {
			uris.push(trimmed.to_string());
		}
	}
	(uris, is_cut)
}

fn read_clipboard_uris_and_action() -> (Vec<String>, bool) {
	if let Ok(out) = Command::new("wl-paste")
		.args(["--type", "x-special/nautilus-clipboard", "--no-newline"])
		.output()
	{
		if out.status.success() {
			let text = String::from_utf8_lossy(&out.stdout);
			let (uris, is_cut) = parse_nautilus_clipboard(&text);
			if !uris.is_empty() {
				return (uris, is_cut);
			}
		}
	}

	if let Ok(out) = Command::new("xclip")
		.args([
			"-selection",
			"clipboard",
			"-t",
			"x-special/nautilus-clipboard",
			"-o",
		])
		.output()
	{
		if out.status.success() {
			let text = String::from_utf8_lossy(&out.stdout);
			let (uris, is_cut) = parse_nautilus_clipboard(&text);
			if !uris.is_empty() {
				return (uris, is_cut);
			}
		}
	}

	if let Ok(out) = Command::new("wl-paste")
		.args(["--type", "text/uri-list", "--no-newline"])
		.output()
	{
		if out.status.success() {
			let text = String::from_utf8_lossy(&out.stdout);
			let uris = parse_uri_list(&text);
			if !uris.is_empty() {
				return (uris, false);
			}
		}
	}

	if let Ok(out) = Command::new("xclip")
		.args(["-selection", "clipboard", "-t", "text/uri-list", "-o"])
		.output()
	{
		if out.status.success() {
			let text = String::from_utf8_lossy(&out.stdout);
			let uris = parse_uri_list(&text);
			if !uris.is_empty() {
				return (uris, false);
			}
		}
	}

	if let Ok(guard) = INTERNAL_CLIPBOARD.lock() {
		if let Some((uris, is_cut)) = &*guard {
			if !uris.is_empty() {
				return (uris.clone(), *is_cut);
			}
		}
	}

	(vec![], false)
}

fn parse_uri_list(text: &str) -> Vec<String> {
	text.lines()
		.map(|l| l.trim())
		.filter(|l| {
			!l.is_empty()
				&& !l.starts_with('#')
				&& *l != "x-special/nautilus-clipboard"
				&& *l != "copy"
				&& *l != "cut"
		})
		.map(|l| l.to_string())
		.collect()
}

/// Minimal percent-decoder for file paths (%20 → space, etc.)
fn percent_decode(s: &str) -> String {
	let mut out = String::with_capacity(s.len());
	let bytes = s.as_bytes();
	let mut i = 0;
	while i < bytes.len() {
		if bytes[i] == b'%' && i + 2 < bytes.len() {
			if let (Some(hi), Some(lo)) = (
				(bytes[i + 1] as char).to_digit(16),
				(bytes[i + 2] as char).to_digit(16),
			) {
				out.push((((hi << 4) | lo) as u8) as char);
				i += 3;
				continue;
			}
		}
		out.push(bytes[i] as char);
		i += 1;
	}
	out
}

#[cfg(test)]
mod tests {
	use super::{FileManager, can_rename, cut_into, rename_is_label_only};
	use std::fs;
	use std::path::PathBuf;

	/// A unique scratch directory for one test.
	fn scratch(name: &str) -> PathBuf {
		let dir = std::env::temp_dir().join(format!("{name}-{}", std::process::id()));
		fs::remove_dir_all(&dir).ok();
		fs::create_dir_all(&dir).unwrap();
		dir
	}

	#[test]
	fn only_ordinary_items_and_declared_provider_entries_can_be_renamed() {
		let dir = scratch("hishell-rename-gate");
		let section = dir.join("Bluetooth");
		fs::create_dir(&section).unwrap();
		fs::write(
			section.join(".directory"),
			"[Desktop Entry]\nType=Directory\nGenerated=true\nName=Bluetooth\n\
			 Rename=/bin/true %v\n",
		)
		.unwrap();
		let theme = section.join("theme-bundle");
		fs::create_dir(&theme).unwrap();
		fs::write(
			theme.join(".directory"),
			"[Desktop Entry]\nType=Directory\nGenerated=true\nName=Theme\n\
			 Rename=/bin/true %v\n",
		)
		.unwrap();
		let ordinary = dir.join("notes.txt");
		fs::write(&ordinary, "mine\n").unwrap();
		let wifi = section.join("wpa:abc.desktop");
		fs::write(
			&wifi,
			"[Desktop Entry]\nType=Button\nGenerated=true\nName=Home\n",
		)
		.unwrap();
		let paired = section.join("AA:BB:CC:DD:EE:FF.desktop");
		fs::write(
			&paired,
			"[Desktop Entry]\nType=Button\nGenerated=true\nName=Old label\n\
			 Rename=/bin/true %v\n",
		)
		.unwrap();
		let handle = dir.join("Bluetooth link");
		std::os::unix::fs::symlink(&section, &handle).unwrap();

		assert!(can_rename(&ordinary));
		assert!(!can_rename(&section), "a virtual section is not renamable");
		assert!(
			!can_rename(&theme),
			"a bundle inside a virtual section is not renamable"
		);
		assert!(
			!can_rename(&wifi),
			"a generated entry without Rename= is not renamable"
		);
		assert!(can_rename(&paired), "a paired device may change its label");
		assert!(rename_is_label_only(&paired));
		assert!(can_rename(&handle), "the handle is the user's to rename");
		assert!(
			!rename_is_label_only(&handle),
			"renaming the handle must not change the target's label"
		);

		let fm = FileManager::default();
		let denied: serde_json::Value = serde_json::from_str(
			&fm.rename_file(wifi.to_string_lossy().to_string(), "New name".to_string()),
		)
		.unwrap();
		assert_eq!(denied["ok"], false);
		assert!(wifi.exists());
		assert_eq!(
			fs::read_to_string(&wifi).unwrap(),
			"[Desktop Entry]\nType=Button\nGenerated=true\nName=Home\n"
		);

		fs::remove_dir_all(&dir).ok();
	}

	#[test]
	fn pasting_a_cut_generated_entry_destroys_it_instead_of_moving_it() {
		let dir = scratch("hishell-cut-destroy");
		let dest = dir.join("dest");
		fs::create_dir_all(&dest).unwrap();
		let entry = dir.join("wpa:abc.desktop");
		// `/bin/true` stands in for `clam-connect wifi --forget …`: the command
		// owns the deletion, so the file must still be where it was.
		fs::write(
			&entry,
			"[Desktop Entry]\nType=Button\nName=Home\nExec=clam-connect wifi wpa:abc\n\
			 Destroy=/bin/true\nGenerated=true\nProvider=wifi\n",
		)
		.unwrap();

		assert!(cut_into(
			&dest,
			&[entry.to_string_lossy().to_string()],
			&mut Vec::new()
		));
		assert!(entry.exists(), "a destroy is not a move");
		assert!(!dest.join("wpa:abc.desktop").exists());

		fs::remove_dir_all(&dir).ok();
	}

	#[test]
	fn pasting_a_cut_provider_entry_links_it_instead() {
		let dir = scratch("hishell-cut-link");
		let dest = dir.join("dest");
		fs::create_dir_all(&dest).unwrap();
		let entry = dir.join("00-scan.desktop");
		fs::write(
			&entry,
			"[Desktop Entry]\nType=Button\nName=Scan for networks\nExec=clam-connect wifi --scan\n\
			 Generated=true\nProvider=wifi\n",
		)
		.unwrap();

		assert!(cut_into(
			&dest,
			&[entry.to_string_lossy().to_string()],
			&mut Vec::new()
		));
		assert!(entry.exists(), "an undestroyable source is never unlinked");
		let linked = dest.join("00-scan.desktop");
		assert!(linked.exists());
		assert_eq!(fs::read_link(&linked).unwrap(), entry);

		fs::remove_dir_all(&dir).ok();
	}

	#[test]
	fn dragging_an_undestroyable_source_links_for_copy_and_move() {
		let dir = scratch("hishell-drag-link");
		let dest = dir.join("dest");
		fs::create_dir_all(&dest).unwrap();
		let section = dir.join("Wi-Fi");
		fs::create_dir(&section).unwrap();
		fs::write(
			&section.join(".directory"),
			"[Desktop Entry]\nType=Directory\nGenerated=true\nName=Wi-Fi\n",
		)
		.unwrap();

		let fm = FileManager::default();
		assert!(fm.process_uris_action(
			dest.to_string_lossy().to_string(),
			section.to_string_lossy().to_string(),
			"copy".to_string()
		));
		let copied = dest.join("Wi-Fi");
		assert!(
			fs::symlink_metadata(&copied)
				.unwrap()
				.file_type()
				.is_symlink()
		);
		assert!(section.exists(), "copy never touches the source");

		let other = dir.join("other");
		fs::create_dir_all(&other).unwrap();
		assert!(fm.process_uris_action(
			other.to_string_lossy().to_string(),
			section.to_string_lossy().to_string(),
			"move".to_string()
		));
		let moved = other.join("Wi-Fi");
		assert!(
			fs::symlink_metadata(&moved)
				.unwrap()
				.file_type()
				.is_symlink()
		);
		assert!(
			section.exists(),
			"moving an undestroyable source links instead"
		);

		fs::remove_dir_all(&dir).ok();
	}

	#[test]
	fn dropping_a_file_into_a_virtual_folder_copies_and_keeps_the_source() {
		let dir = scratch("hishell-drop-virtual");
		let section = dir.join("Bluetooth");
		fs::create_dir(&section).unwrap();
		fs::write(
			section.join(".directory"),
			"[Desktop Entry]\nType=Directory\nGenerated=true\nName=Bluetooth\n",
		)
		.unwrap();
		let source = dir.join("notes.txt");
		fs::write(&source, "keep me\n").unwrap();

		let fm = FileManager::default();
		assert!(fm.process_uris_action(
			section.to_string_lossy().to_string(),
			source.to_string_lossy().to_string(),
			"move".to_string()
		));
		assert!(
			source.exists(),
			"a provider that ignores the drop must not eat the source"
		);
		assert_eq!(
			fs::read_to_string(section.join("notes.txt")).unwrap(),
			"keep me\n"
		);

		fs::remove_dir_all(&dir).ok();
	}

	#[test]
	fn a_symlink_handle_is_copied_and_moved_as_a_link() {
		let dir = scratch("hishell-drag-handle");
		let dest = dir.join("dest");
		fs::create_dir_all(&dest).unwrap();
		let section = dir.join("Wi-Fi");
		fs::create_dir(&section).unwrap();
		fs::write(
			&section.join(".directory"),
			"[Desktop Entry]\nType=Directory\nGenerated=true\nName=Wi-Fi\n",
		)
		.unwrap();
		let handle = dir.join("Wi-Fi link");
		std::os::unix::fs::symlink(&section, &handle).unwrap();

		let fm = FileManager::default();
		assert!(fm.process_uris_action(
			dest.to_string_lossy().to_string(),
			handle.to_string_lossy().to_string(),
			"copy".to_string()
		));
		let copied = dest.join("Wi-Fi link");
		assert!(
			fs::symlink_metadata(&copied)
				.unwrap()
				.file_type()
				.is_symlink(),
			"copying a handle must not materialise the section"
		);
		assert!(section.exists());

		let other = dir.join("other");
		fs::create_dir_all(&other).unwrap();
		assert!(fm.process_uris_action(
			other.to_string_lossy().to_string(),
			handle.to_string_lossy().to_string(),
			"move".to_string()
		));
		let moved = other.join("Wi-Fi link");
		assert!(
			fs::symlink_metadata(&moved)
				.unwrap()
				.file_type()
				.is_symlink()
		);
		assert!(!handle.exists(), "the handle itself moved");
		assert!(section.exists(), "the section stayed where it was");

		fs::remove_dir_all(&dir).ok();
	}

	#[test]
	fn a_handle_to_a_generated_entry_moves_without_running_its_destroy() {
		let dir = scratch("hishell-drag-entry-handle");
		let dest = dir.join("dest");
		fs::create_dir_all(&dest).unwrap();
		let entry = dir.join("wpa:abc.desktop");
		fs::write(
			&entry,
			"[Desktop Entry]\nType=Button\nGenerated=true\nName=Home\n\
			 Destroy=/bin/false\n",
		)
		.unwrap();
		let handle = dir.join("Home link");
		std::os::unix::fs::symlink(&entry, &handle).unwrap();

		let fm = FileManager::default();
		assert!(
			fm.process_uris_action(
				dest.to_string_lossy().to_string(),
				handle.to_string_lossy().to_string(),
				"move".to_string()
			),
			"the handle moves; its target's Destroy= must not run"
		);
		let moved = dest.join("Home link");
		assert!(
			fs::symlink_metadata(&moved)
				.unwrap()
				.file_type()
				.is_symlink()
		);
		assert!(!handle.exists());
		assert!(entry.exists(), "the generated entry stayed in its section");

		fs::remove_dir_all(&dir).ok();
	}

	#[test]
	fn dragging_a_visible_network_copies_as_a_link() {
		let dir = scratch("hishell-drag-network");
		let dest = dir.join("dest");
		fs::create_dir_all(&dest).unwrap();
		let entry = dir.join("wpa:abc.desktop");
		fs::write(
			&entry,
			"[Desktop Entry]\nType=Button\nGenerated=true\nName=Visible\n",
		)
		.unwrap();

		let fm = FileManager::default();
		assert!(fm.process_uris_action(
			dest.to_string_lossy().to_string(),
			entry.to_string_lossy().to_string(),
			"copy".to_string()
		));
		let linked = dest.join("wpa:abc.desktop");
		assert!(
			fs::symlink_metadata(&linked)
				.unwrap()
				.file_type()
				.is_symlink()
		);
		assert!(entry.exists());
		assert_eq!(fs::read_link(&linked).unwrap(), entry);

		fs::remove_dir_all(&dir).ok();
	}

	#[test]
	fn pasting_a_cut_ordinary_file_moves_it() {
		let dir = scratch("hishell-cut-move");
		let dest = dir.join("dest");
		fs::create_dir_all(&dest).unwrap();
		let file = dir.join("holiday.txt");
		fs::write(&file, "sun\n").unwrap();

		assert!(cut_into(
			&dest,
			&[file.to_string_lossy().to_string()],
			&mut Vec::new()
		));
		assert!(!file.exists());
		assert_eq!(
			fs::read_to_string(dest.join("holiday.txt")).unwrap(),
			"sun\n"
		);

		fs::remove_dir_all(&dir).ok();
	}

	#[test]
	fn a_staged_drop_that_is_never_listed_was_declined() {
		assert!(!super::drop_kept(true, false));
		assert!(super::drop_kept(true, true));
		assert!(super::drop_kept(false, false));
	}
}
