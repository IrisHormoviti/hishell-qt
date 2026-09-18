use once_cell::sync::Lazy;
use qmetaobject::prelude::*;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;
use trash;

static INTERNAL_CLIPBOARD: Lazy<Mutex<Option<(Vec<String>, bool)>>> =
	Lazy::new(|| Mutex::new(None));

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
		fn copy_file(&self, source: QString, dest: QString) -> bool {
			let src = clean_path(&source.to_string());
			let dst = clean_path(&dest.to_string());
			fs::copy(src, dst).is_ok()
		}
	),

	duplicate_file: qt_method!(
		fn duplicate_file(&self, source: QString) -> bool {
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
		fn new_folder(&self, parent: QString) -> bool {
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
		fn new_text_file(&self, parent: QString) -> bool {
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
		fn create_link(&self, source: QString, dest: QString) -> bool {
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
	trash_file: qt_method!(
		fn trash_file(&self, path: QString) -> bool {
			let p = clean_path(&path.to_string());
			trash::delete(p).is_ok()
		}
	),

	/// Permanently delete a file or directory (no trash).
	delete_file: qt_method!(
		fn delete_file(&self, path: QString) -> bool {
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
	rename_file: qt_method!(
		fn rename_file(&self, path: QString, new_name: QString) -> bool {
			let p = clean_path(&path.to_string());
			let n = new_name.to_string();
			let src = Path::new(&p);
			let parent = match src.parent() {
				Some(p) => p,
				None => return false,
			};
			let dest = parent.join(&n);
			fs::rename(src, dest).is_ok()
		}
	),

	/// Copy the given newline-separated list of paths to the system clipboard
	/// using the freedesktop "copy" URI list format (compatible with Nautilus, Dolphin, Thunar, etc.).
	/// Falls back gracefully if no clipboard tool is available.
	copy_paths_to_clipboard: qt_method!(
		fn copy_paths_to_clipboard(&self, paths_newline: QString) -> bool {
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
		fn cut_paths_to_clipboard(&self, paths_newline: QString) -> bool {
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
		fn paste_from_clipboard(&self, dest_dir: QString) -> bool {
			let dest = clean_path(&dest_dir.to_string());
			let dest_path = Path::new(&dest);
			if !dest_path.is_dir() {
				return false;
			}
			let (uris, is_cut) = read_clipboard_uris_and_action();
			if uris.is_empty() {
				return false;
			}
			let uris_str = uris.join("\n");
			let action = if is_cut { "move" } else { "copy" };
			let ok = self.process_uris_action(
				QString::from(dest.as_str()),
				QString::from(uris_str.as_str()),
				QString::from(action),
			);
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
		fn get_mime_type(&self, path: QString) -> QString {
			let p = clean_path(&path.to_string());
			let mime = mime_guess::from_path(&p)
				.first_or_octet_stream()
				.essence_str()
				.to_string();
			QString::from(mime.as_str())
		}
	),

	/// Return text file content (capped at 64KB) for text/plain drag payload.
	get_text_content: qt_method!(
		fn get_text_content(&self, path: QString) -> QString {
			let p = clean_path(&path.to_string());
			let path_buf = Path::new(&p);
			if path_buf.is_file() {
				if let Ok(meta) = fs::metadata(path_buf) {
					if meta.len() <= 64 * 1024 {
						if let Ok(content) = fs::read_to_string(path_buf) {
							return QString::from(content.as_str());
						}
					}
				}
			}
			QString::default()
		}
	),

	/// Process URIs list with specified action ("copy", "move", "link") into dest_dir.
	process_uris_action: qt_method!(
		fn process_uris_action(
			&self,
			dest_dir: QString,
			uris_newline: QString,
			action: QString,
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
		fn open_file(&self, path: QString) -> bool {
			let p = clean_path(&path.to_string());
			crate::directory::open_file(p);
			true
		}
	),

	open_file_with_dialog: qt_method!(
		fn open_file_with_dialog(&self, path: QString) -> bool {
			let p = clean_path(&path.to_string());
			crate::portal::open_file_with_portal(Path::new(&p))
		}
	),

	rotate_image: qt_method!(
		fn rotate_image(&self, path: QString, degrees: i32) -> bool {
			let p = clean_path(&path.to_string());
			crate::image_utils::rotate_image(Path::new(&p), degrees)
		}
	),

	is_image_file: qt_method!(
		fn is_image_file(&self, path: QString) -> bool {
			let p = clean_path(&path.to_string());
			crate::image_utils::is_image_file(Path::new(&p))
		}
	),

	is_directory: qt_method!(
		fn is_directory(&self, path: QString) -> bool {
			let p = clean_path(&path.to_string());
			Path::new(&p).is_dir()
		}
	),
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
