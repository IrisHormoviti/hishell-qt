use once_cell::sync::Lazy;
use qmetaobject::prelude::*;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;
use trash;

static INTERNAL_CLIPBOARD: Lazy<Mutex<Option<(Vec<String>, bool)>>> =
	Lazy::new(|| Mutex::new(None));

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

#[derive(QObject, Default)]
pub struct FileManager {
	base: qt_base_class!(trait QObject),

	copy_file: qt_method!(
		fn copy_file(&self, source: String, dest: String) -> bool {
			let src = clean_path(&source.to_string());
			let dst = clean_path(&dest.to_string());
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
			#[cfg(unix)]
			{
				std::os::unix::fs::symlink(src_path, dst).is_ok()
			}
			#[cfg(not(unix))]
			{
				false
			}
		}
	),

	/// Move a file/directory to the system trash.
	///
	/// A generated desktop entry belongs to the provider that wrote it, so it
	/// cannot simply be moved: when it declares a `Destroy=` command that command
	/// runs instead (deleting the profile and the file together), and when it
	/// does not, trashing is refused — deleting the file would only make the
	/// daemon write it back (docs `settings-as-folders.md` §6.3).
	trash_file: qt_method!(
		fn trash_file(&self, path: String) -> bool {
			let p = clean_path(&path.to_string());
			let path = Path::new(&p);
			let entry = crate::desktop_entry::read(path);
			if let Some(command) = entry.destroy_command() {
				return crate::desktop_entry::run_destroy(path, &entry, command);
			}
			if !entry.is_destroyable() {
				return false;
			}
			trash::delete(path).is_ok()
		}
	),

	/// Whether the file views may offer Trash/Cut for this path. False for a
	/// generated entry the provider does not let the user destroy (§6.3).
	can_destroy: qt_method!(
		fn can_destroy(&self, path: String) -> bool {
			let p = clean_path(&path.to_string());
			crate::desktop_entry::read(Path::new(&p)).is_destroyable()
		}
	),

	/// Permanently delete a file or directory (no trash).
	delete_file: qt_method!(
		fn delete_file(&self, path: String) -> bool {
			let p = clean_path(&path.to_string());
			let p = Path::new(&p);
			if p.is_dir() {
				fs::remove_dir_all(p).is_ok()
			} else {
				fs::remove_file(p).is_ok()
			}
		}
	),

	/// Rename (move) a file or directory to a new name within the same parent.
	/// Returns a JSON status object: `{"ok":bool,"error":string}`.
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
			let ok = if is_cut {
				cut_into(dest_path, &uris)
			} else {
				let uris_str = uris.join("\n");
				self.process_uris_action(
					String::from(dest.as_str()),
					String::from(uris_str.as_str()),
					String::from("copy"),
				)
			};
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
			let action_str = action.to_string();
			let mut any_ok = false;
			for uri in &uris {
				let src_str = clean_path(uri);
				let src = Path::new(&src_str);
				if !src.exists() {
					continue;
				}
				if let Some(fname_os) = src.file_name() {
					let fname = fname_os.to_string_lossy().to_string();
					let mut dst = dest_path.join(&fname);
					match action_str.as_str() {
						"move" => {
							if src == dst {
								continue;
							}
							if move_item(src, &dst) {
								any_ok = true;
							}
						}
						"link" => {
							#[cfg(unix)]
							{
								if dst.exists() {
									dst = unique_path(dest_path, &fname, " (link)");
								}
								if std::os::unix::fs::symlink(src, &dst).is_ok() {
									any_ok = true;
								}
							}
						}
						_ => {
							if src == dst || dst.exists() {
								dst = unique_path(dest_path, &fname, " (copy)");
							}
							if src.is_dir() {
								if copy_dir_recursive(src, &dst) {
									any_ok = true;
								}
							} else if fs::copy(src, &dst).is_ok() {
								any_ok = true;
							}
						}
					}
				}
			}
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

	get_home_directory: qt_method!(
		pub fn get_home_directory(&self) -> String {
			dirs::home_dir()
				.map(|path| path.to_string_lossy().into_owned())
				.unwrap_or_default()
		}
	),
}

/// Carry out a Cut into `dest`, one URI at a time.
///
/// A generated entry that names a `Destroy=` command is not moved: for it,
/// Cut-then-Paste means *destroy* — the same thing Trash does — because moving
/// the file would leave the NetworkManager profile (or paired device) behind and
/// the provider would write the entry straight back (docs §6.3). A generated
/// entry with no such command is refused rather than moved, and everything else
/// is an ordinary move.
fn cut_into(dest: &Path, uris: &[String]) -> bool {
	let mut any_ok = false;
	for uri in uris {
		let src = Path::new(uri);
		if !src.exists() {
			continue;
		}
		let entry = crate::desktop_entry::read(src);
		if let Some(command) = entry.destroy_command() {
			if crate::desktop_entry::run_destroy(src, &entry, command) {
				any_ok = true;
			}
			continue;
		}
		if !entry.is_destroyable() {
			continue;
		}
		let Some(name) = src.file_name() else {
			continue;
		};
		let dst = dest.join(name);
		if src == dst {
			continue;
		}
		if move_item(src, &dst) {
			any_ok = true;
		}
	}
	any_ok
}

fn move_item(src: &Path, dst: &Path) -> bool {
	if fs::rename(src, dst).is_ok() {
		return true;
	}
	// Fallback for cross-filesystem move
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
	use super::cut_into;
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

		assert!(cut_into(&dest, &[entry.to_string_lossy().to_string()]));
		assert!(entry.exists(), "a destroy is not a move");
		assert!(!dest.join("wpa:abc.desktop").exists());

		fs::remove_dir_all(&dir).ok();
	}

	#[test]
	fn pasting_a_cut_provider_entry_is_refused() {
		let dir = scratch("hishell-cut-refused");
		let dest = dir.join("dest");
		fs::create_dir_all(&dest).unwrap();
		let entry = dir.join("00-scan.desktop");
		fs::write(
			&entry,
			"[Desktop Entry]\nType=Button\nName=Scan for networks\nExec=clam-connect wifi --scan\n\
			 Generated=true\nProvider=wifi\n",
		)
		.unwrap();

		assert!(!cut_into(&dest, &[entry.to_string_lossy().to_string()]));
		assert!(entry.exists());
		assert!(!dest.join("00-scan.desktop").exists());

		fs::remove_dir_all(&dir).ok();
	}

	#[test]
	fn pasting_a_cut_ordinary_file_moves_it() {
		let dir = scratch("hishell-cut-move");
		let dest = dir.join("dest");
		fs::create_dir_all(&dest).unwrap();
		let file = dir.join("holiday.txt");
		fs::write(&file, "sun\n").unwrap();

		assert!(cut_into(&dest, &[file.to_string_lossy().to_string()]));
		assert!(!file.exists());
		assert_eq!(fs::read_to_string(dest.join("holiday.txt")).unwrap(), "sun\n");

		fs::remove_dir_all(&dir).ok();
	}
}
