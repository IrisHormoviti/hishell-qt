use serde_json::Value;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::process::Command;

unsafe extern "C" {
	fn hishell_open_with_apps(path: *const c_char) -> *const c_char;
	fn hishell_open_with_launch(storage_id: *const c_char, path: *const c_char) -> bool;
	fn hishell_open_with_default(path: *const c_char) -> bool;
	fn hishell_default_app(path: *const c_char) -> *const c_char;
	fn hishell_portal_open_with(path: *const c_char) -> bool;
	fn hishell_portal_poll() -> i32;
	fn hishell_send_key(key: i32) -> bool;
	fn hishell_hook_menu_key();
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
	Command::new("gio")
		.args(["mime", mime, storage_id])
		.status()
		.map(|status| status.success())
		.unwrap_or(false)
}
