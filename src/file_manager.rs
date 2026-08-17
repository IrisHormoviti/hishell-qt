use qmetaobject::prelude::*;
use std::fs;
use std::path::Path;
use std::process::Command;

#[derive(QObject, Default)]
pub struct FileManager {
	base: qt_base_class!(trait QObject),

	copy_file: qt_method!(
		fn copy_file(&self, source: QString, dest: QString) -> bool {
			fs::copy(source.to_string(), dest.to_string()).is_ok()
		}
	),

	duplicate_file: qt_method!(
		fn duplicate_file(&self, source: QString) -> bool {
			let p = source.to_string();
			let path = Path::new(&p);
			if path.is_dir() {
				// duplicate directory
				if let Some(parent) = path.parent() {
					let base = path.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
					let new_name = format!("{} (copy)", base);
					let dest = parent.join(&new_name);
					return copy_dir_recursive(path, &dest);
				}
				return false;
			}
			if let (Some(parent), Some(stem)) = (path.parent(), path.file_stem()) {
				let ext = path.extension().map(|e| format!(".{}", e.to_string_lossy())).unwrap_or_default();
				let new_name = format!("{} (copy){}", stem.to_string_lossy(), ext);
				let dest = parent.join(new_name);
				fs::copy(&p, &dest).is_ok()
			} else {
				false
			}
		}
	),

	new_folder: qt_method!(
		fn new_folder(&self, parent: QString) -> bool {
			let parent_string = parent.to_string();
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
			let parent_string = parent.to_string();
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
			#[cfg(unix)]
			{
				std::os::unix::fs::symlink(source.to_string(), dest.to_string()).is_ok()
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
			trash::delete(path.to_string()).is_ok()
		}
	),

	/// Permanently delete a file or directory (no trash).
	delete_file: qt_method!(
		fn delete_file(&self, path: QString) -> bool {
			let p = path.to_string();
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
			let p = path.to_string();
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
			set_clipboard_uris(&paths, false)
		}
	),

	/// Cut: same as copy but writes the "cut" action to the clipboard.
	cut_paths_to_clipboard: qt_method!(
		fn cut_paths_to_clipboard(&self, paths_newline: QString) -> bool {
			let paths = paths_newline.to_string();
			set_clipboard_uris(&paths, true)
		}
	),

	/// Paste files from the system clipboard (text/uri-list) into dest_dir.
	/// Returns true if at least one file was copied successfully.
	paste_from_clipboard: qt_method!(
		fn paste_from_clipboard(&self, dest_dir: QString) -> bool {
			let dest = dest_dir.to_string();
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
			self.process_uris_action(dest_dir, QString::from(uris_str.as_str()), QString::from(action))
		}
	),

	/// Return MIME type string for a file path (guessed via mime_guess).
	get_mime_type: qt_method!(
		fn get_mime_type(&self, path: QString) -> QString {
			let p = path.to_string();
			let mime = mime_guess::from_path(&p).first_or_octet_stream().essence_str().to_string();
			QString::from(mime.as_str())
		}
	),

	/// Return text file content (capped at 64KB) for text/plain drag payload.
	get_text_content: qt_method!(
		fn get_text_content(&self, path: QString) -> QString {
			let p = path.to_string();
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
		fn process_uris_action(&self, dest_dir: QString, uris_newline: QString, action: QString) -> bool {
			let dest = dest_dir.to_string();
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
				let raw = if uri.starts_with("file://") { &uri[7..] } else { uri.as_str() };
				let src_str = percent_decode(raw);
				let src = Path::new(&src_str);
				if !src.exists() {
					continue;
				}
				if let Some(fname) = src.file_name() {
					let dst = dest_path.join(fname);
					if src == dst {
						continue;
					}
					match action_str.as_str() {
						"move" => {
							if move_item(src, &dst) {
								any_ok = true;
							}
						}
						"link" => {
							#[cfg(unix)]
							{
								if std::os::unix::fs::symlink(src, &dst).is_ok() {
									any_ok = true;
								}
							}
						}
						_ => {
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

/// Write a freedesktop clipboard URI list.
/// Format expected by GTK/Qt file managers:
///   x-special/nautilus-clipboard\ncopy\nfile:///path\nfile:///path2
fn set_clipboard_uris(paths_newline: &str, cut: bool) -> bool {
	// Build URI list
	let action = if cut { "cut" } else { "copy" };
	let uris: Vec<String> = paths_newline
		.lines()
		.filter(|l| !l.trim().is_empty())
		.map(|p| {
			if p.starts_with("file://") {
				p.to_string()
			} else {
				format!("file://{}", p)
			}
		})
		.collect();

	if uris.is_empty() {
		return false;
	}

	// Nautilus/Dolphin compatible format
	let nautilus_data = format!("x-special/nautilus-clipboard\n{}\n{}\n", action, uris.join("\n"));
	// Plain URI list (text/uri-list)
	let uri_list = uris.join("\n");

	// Try wl-clipboard (Wayland)
	if try_wl_copy(&nautilus_data, "x-special/nautilus-clipboard") {
		return true;
	}
	// Try xclip (X11)
	if try_xclip(&nautilus_data, "x-special/nautilus-clipboard") {
		return true;
	}
	// Try xsel as last resort with plain URI list
	if try_xsel(&uri_list) {
		return true;
	}

	false
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

/// Read file URIs from the system clipboard and return (uris, is_cut).
fn read_clipboard_uris_and_action() -> (Vec<String>, bool) {
	// First try nautilus-clipboard format for cut detection
	if let Ok(out) = Command::new("wl-paste")
		.args(["--type", "x-special/nautilus-clipboard", "--no-newline"])
		.output()
	{
		if out.status.success() {
			let text = String::from_utf8_lossy(&out.stdout);
			let lines: Vec<&str> = text.lines().collect();
			if lines.len() >= 2 {
				let is_cut = lines[0].trim() == "cut" || lines[1].trim() == "cut";
				let uris = parse_uri_list(&text);
				if !uris.is_empty() {
					return (uris, is_cut);
				}
			}
		}
	}

	// Wayland standard uri-list
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

	// X11 standard uri-list
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

	(vec![], false)
}

fn parse_uri_list(text: &str) -> Vec<String> {
	text.lines()
		.map(|l| l.trim())
		.filter(|l| !l.is_empty() && !l.starts_with('#'))
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
