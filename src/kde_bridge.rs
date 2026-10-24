use serde_json::Value;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::PathBuf;
use std::process::Command;

unsafe extern "C" {
	fn hishell_open_with_apps(path: *const c_char) -> *const c_char;
	fn hishell_open_with_launch(storage_id: *const c_char, path: *const c_char) -> bool;
	fn hishell_open_with_default(path: *const c_char) -> bool;
	fn hishell_app_command(storage_id: *const c_char) -> *const c_char;
	fn hishell_default_app_command(path: *const c_char) -> *const c_char;
	fn hishell_default_app(path: *const c_char) -> *const c_char;
	fn hishell_rename(path: *const c_char, new_name: *const c_char) -> *const c_char;
	fn hishell_portal_open_with(path: *const c_char) -> bool;
	fn hishell_portal_poll() -> i32;
	fn hishell_send_key(key: i32) -> bool;
	fn hishell_hook_menu_key();
	fn hishell_suppress_touch_hover();
	fn hishell_play_sound(event_id: *const c_char) -> bool;
	fn hishell_set_sound_volume(factor: f64);
	fn hishell_set_window_icon(source: *const c_char) -> bool;
	fn hishell_file_uri(path: *const c_char) -> *const c_char;
	fn hishell_mime_type(path: *const c_char) -> *const c_char;
	fn hishell_clear_app_cache();
	fn hishell_set_icon_theme(name: *const c_char) -> bool;
	fn hishell_warm_icons();
	fn hishell_install_message_handler();
	fn hishell_accent_icon(
		name: *const c_char,
		size: i32,
		accent_r: i32,
		accent_g: i32,
		accent_b: i32,
		text_r: i32,
		text_g: i32,
		text_b: i32,
		cache_dir: *const c_char,
	) -> *const c_char;
	fn hishell_thumbnailer_dirs() -> *const c_char;
	fn hishell_thumbnail_image(
		src: *const c_char,
		dst: *const c_char,
		size: i32,
		uri: *const c_char,
		mtime_secs: i64,
		file_size: i64,
	) -> bool;
}

/// Delivers a synthetic key press/release to whatever currently holds the
/// keyboard focus, so popups (menus, dialogs) can be driven by the controller.
pub fn send_key(key: i32) -> bool {
	unsafe { hishell_send_key(key) }
}

/// Takes the keyboard's context menu key away from the platform so it can be
/// routed like the gamepad's menu button.
pub fn hook_menu_key() {
	unsafe { hishell_hook_menu_key() }
}

/// Stops Qt Quick from painting hover effects when a finger moves over the
/// touch panel. See the C++ side for why.
pub fn suppress_touch_hover() {
	unsafe { hishell_suppress_touch_hover() }
}

/// Play an XDG event sound by name through libcanberra (e.g. "dialog-error").
/// Returns whether the sound was started; a missing sound or driver is not an
/// error, so callers can ignore the result.
pub fn play_sound(event_id: &str) -> bool {
	let Ok(id) = CString::new(event_id) else {
		return false;
	};
	unsafe { hishell_play_sound(id.as_ptr()) }
}

/// Set the output volume for event sounds, 0.0..=1.0.
pub fn set_sound_volume(factor: f64) {
	unsafe { hishell_set_sound_volume(factor) }
}

/// Pre-resolves the action-menu icons once, so focusing an item does not pay for
/// a synchronous icon-theme scan. See the C++ side for why.
pub fn warm_icons() {
	unsafe { hishell_warm_icons() }
}

/// Routes every Qt message (QML errors included) to stderr, flushed, so a QML
/// load failure reaches the launcher's log instead of only the window.
pub fn install_message_handler() {
	unsafe { hishell_install_message_handler() }
}

/// Switch the process icon theme at runtime (e.g. to `breeze-dark` when the
/// active theme declares `[Icons] Theme=...`).  QIcon caches per theme, so
/// existing items re-resolve on their next paint.
pub fn set_icon_theme(name: &str) -> bool {
	let Ok(name) = CString::new(name) else {
		return false;
	};
	unsafe { hishell_set_icon_theme(name.as_ptr()) }
}

/// Renders a themed icon with the accent applied to the parts the icon theme
/// marks `ColorScheme-Accent` (Breeze draws every folder body that way), and
/// returns the cached PNG's `file://` URI. `None` means the icon could not be
/// rendered; callers fall back to the plain themed icon name.
pub fn accent_icon(name: &str, size: u32, accent: (u8, u8, u8), text: (u8, u8, u8)) -> Option<String> {
	if name.is_empty() || size == 0 {
		return None;
	}
	let cache_dir = dirs::cache_dir()?.join("hishell").join("accent-icons");
	let cache_dir = CString::new(cache_dir.to_string_lossy().as_bytes()).ok()?;
	let name = CString::new(name).ok()?;
	let rendered = unsafe {
		hishell_accent_icon(
			name.as_ptr(),
			size as i32,
			accent.0 as i32,
			accent.1 as i32,
			accent.2 as i32,
			text.0 as i32,
			text.1 as i32,
			text.2 as i32,
			cache_dir.as_ptr(),
		)
	};
	if rendered.is_null() {
		return None;
	}
	let value = unsafe { CStr::from_ptr(rendered) }
		.to_string_lossy()
		.into_owned();
	if value.is_empty() { None } else { Some(value) }
}

/// Applies an icon to the focused top-level window, so the task switcher and
/// title bar show the current folder's icon. `source` is a themed icon name or
/// a `file://` URI; an empty string clears the icon.
pub fn set_window_icon(source: &str) -> bool {
	let Ok(source) = CString::new(source) else {
		return false;
	};
	unsafe { hishell_set_window_icon(source.as_ptr()) }
}

fn empty_payload() -> String {
	String::from(r#"{"mime":"","mimeDescription":"","apps":[]}"#)
}

fn is_default(app: &Value) -> bool {
	app.get("isDefault")
		.and_then(Value::as_bool)
		.unwrap_or(false)
}

fn is_hidden(app: &Value) -> bool {
	app.get("noDisplay")
		.and_then(Value::as_bool)
		.unwrap_or(false)
}

fn clean_payload(raw: &str) -> String {
	let Ok(mut payload) = serde_json::from_str::<Value>(raw) else {
		return empty_payload();
	};
	let Some(apps) = payload.get_mut("apps").and_then(Value::as_array_mut) else {
		return empty_payload();
	};
	apps.retain(|app| !is_hidden(app) || is_default(app));
	apps.sort_by_key(|app| !is_default(app));
	payload.to_string()
}

pub fn apps_json(path: &str) -> String {
	let Ok(path) = CString::new(path) else {
		return empty_payload();
	};
	let json = unsafe { hishell_open_with_apps(path.as_ptr()) };
	if json.is_null() {
		return empty_payload();
	}
	let raw = unsafe { CStr::from_ptr(json) }.to_string_lossy();
	clean_payload(&raw)
}

pub fn launch(storage_id: &str, path: &str) -> bool {
	let (Ok(storage_id), Ok(path)) = (CString::new(storage_id), CString::new(path)) else {
		return false;
	};
	unsafe { hishell_open_with_launch(storage_id.as_ptr(), path.as_ptr()) }
}

/// The command behind a desktop entry, as `(exec, entry path)`, or `None` when
/// it cannot be resolved. Resolved in the backend so the caller can spawn the
/// application itself, through its execution wrapper.
pub fn app_command(storage_id: &str) -> Option<(String, String)> {
	let storage_id = CString::new(storage_id).ok()?;
	parse_command(unsafe { hishell_app_command(storage_id.as_ptr()) })
}

/// The command behind the default application for a file, as `(exec, entry
/// path)`, or `None` when there is no default.
pub fn default_app_command(path: &str) -> Option<(String, String)> {
	let path = CString::new(path).ok()?;
	parse_command(unsafe { hishell_default_app_command(path.as_ptr()) })
}

fn parse_command(json: *const c_char) -> Option<(String, String)> {
	if json.is_null() {
		return None;
	}
	let raw = unsafe { CStr::from_ptr(json) }.to_string_lossy();
	let value: Value = serde_json::from_str(&raw).ok()?;
	let exec = value.get("exec")?.as_str()?.to_string();
	if exec.trim().is_empty() {
		return None;
	}
	let path = value
		.get("path")
		.and_then(Value::as_str)
		.unwrap_or_default()
		.to_string();
	Some((exec, path))
}

pub fn open_with_default(path: &str) -> bool {
	let Ok(path) = CString::new(path) else {
		return false;
	};
	unsafe { hishell_open_with_default(path.as_ptr()) }
}

/// JSON `{id, name, icon}` of the default application; `{}` when there is none.
pub fn default_app_json(path: &str) -> String {
	let Ok(path) = CString::new(path) else {
		return String::from("{}");
	};
	let json = unsafe { hishell_default_app(path.as_ptr()) };
	if json.is_null() {
		return String::from("{}");
	}
	unsafe { CStr::from_ptr(json) }
		.to_string_lossy()
		.into_owned()
}

/// Rename a local file to `new_name` within its directory via KIO.
/// Returns `Ok(())` on success, otherwise the job's error message.
pub fn rename(path: &str, new_name: &str) -> Result<(), String> {
	let (Ok(path), Ok(new_name)) = (CString::new(path), CString::new(new_name)) else {
		return Err(String::from("Invalid path or name."));
	};
	let error = unsafe { hishell_rename(path.as_ptr(), new_name.as_ptr()) };
	if error.is_null() {
		return Err(String::from("Rename failed."));
	}
	let message = unsafe { CStr::from_ptr(error) }.to_string_lossy();
	if message.is_empty() {
		Ok(())
	} else {
		Err(message.into_owned())
	}
}

pub fn portal_open_with(path: &str) -> bool {
	let Ok(path) = CString::new(path) else {
		return false;
	};
	unsafe { hishell_portal_open_with(path.as_ptr()) }
}

/// 0 = finished, 1 = request pending, 2 = failed (use the built-in dialog).
pub fn portal_poll() -> i32 {
	unsafe { hishell_portal_poll() }
}

pub fn set_default(mime: &str, storage_id: &str) -> bool {
	if mime.is_empty() || storage_id.is_empty() {
		return false;
	}
	let ok = Command::new("gio")
		.args(["mime", mime, storage_id])
		.status()
		.map(|status| status.success())
		.unwrap_or(false);
	if ok {
		// The default application for this content type changed; drop the
		// cached trader results so the next lookup sees the new setting.
		unsafe { hishell_clear_app_cache() };
	}
	ok
}

/// Percent-encoded `file://` URI used as a freedesktop thumbnail cache key.
pub fn file_uri(path: &str) -> Option<String> {
	let path = CString::new(path).ok()?;
	let uri = unsafe { hishell_file_uri(path.as_ptr()) };
	if uri.is_null() {
		return None;
	}
	let uri = unsafe { CStr::from_ptr(uri) }
		.to_string_lossy()
		.into_owned();
	if uri.is_empty() { None } else { Some(uri) }
}

/// The shared-mime-info content type for a path, resolved with `QMimeDatabase`
/// (the same database KDE uses), so extensions it registers beyond what
/// `mime_guess` knows — like aseprite's `image/x-aseprite` — are recognised.
pub fn mime_type(path: &str) -> Option<String> {
	let path = CString::new(path).ok()?;
	let mime = unsafe { hishell_mime_type(path.as_ptr()) };
	if mime.is_null() {
		return None;
	}
	let mime = unsafe { CStr::from_ptr(mime) }
		.to_string_lossy()
		.into_owned();
	if mime.is_empty() { None } else { Some(mime) }
}

/// Directories to search for external freedesktop `*.thumbnailer` files.
/// Resolved by Qt from `$XDG_DATA_HOME`/`$XDG_DATA_DIRS`, so the conventional
/// locations are never hard-coded.
pub fn thumbnailer_dirs() -> Vec<PathBuf> {
	let raw = unsafe { hishell_thumbnailer_dirs() };
	if raw.is_null() {
		return Vec::new();
	}
	unsafe { CStr::from_ptr(raw) }
		.to_string_lossy()
		.lines()
		.filter(|line| !line.is_empty())
		.map(PathBuf::from)
		.collect()
}

/// Renders an image thumbnail with QImageReader and stores it with the
/// freedesktop `Thumb::*` text chunks. Runs on the thumbnail worker threads.
pub fn thumbnail_image(
	src: &str,
	dst: &str,
	size: u32,
	uri: &str,
	mtime_secs: i64,
	file_size: u64,
) -> bool {
	let (Ok(src), Ok(dst), Ok(uri)) = (CString::new(src), CString::new(dst), CString::new(uri))
	else {
		return false;
	};
	unsafe {
		hishell_thumbnail_image(
			src.as_ptr(),
			dst.as_ptr(),
			size as i32,
			uri.as_ptr(),
			mtime_secs,
			file_size as i64,
		)
	}
}
