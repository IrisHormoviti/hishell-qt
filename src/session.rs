//! Last shell location, persisted across restarts.
//!
//! Returning from a guest app must land back where the user was — and so must
//! a crash, a redeploy or a reboot. The shell therefore saves the folder it is
//! browsing and the item its cursor sits on, and picks both up at startup:
//! `main` opens the saved folder directly, and the FocusManager re-applies the
//! saved focus to the first file view that loads it.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::Duration;

use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};

/// Environment variables naming the host's session handover files, so the
/// shell does not have to know the host's own paths. Unset means the host has
/// no session handover and the whole feature stays inert.
///
/// * `SUSPEND` — set while a launched app owns the panels: the shell washes
///   itself out for the transition and holds it while the app starts.
/// * `HIDE` — set once the app is on screen: the shell fades the wash out over
///   the app, then unmaps so the app's window is revealed.
/// * `RETURN_FRAME` — image the shell shows for a moment on the way back.
/// * `FOCUS` — file the shell publishes the focused item to.
const ENV_SUSPEND: &str = "HISHELL_SESSION_SUSPEND";
const ENV_HIDE: &str = "HISHELL_SESSION_HIDE";
const ENV_RETURN_FRAME: &str = "HISHELL_SESSION_RETURN_FRAME";
const ENV_FOCUS: &str = "HISHELL_SESSION_FOCUS";

/// Ignore window for a stale marker: if the host died before it could remove
/// its files, the shell must not stay hidden forever.
const MARKER_MAX_AGE: Duration = Duration::from_secs(3600);

fn env_path(name: &str) -> String {
	std::env::var(name).unwrap_or_default()
}

#[derive(Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
struct Session {
	path: String,
	focus: String,
}

static SESSION: Lazy<Mutex<Option<Session>>> = Lazy::new(|| Mutex::new(None));

fn file() -> PathBuf {
	dirs::config_dir()
		.unwrap_or_else(|| PathBuf::from("/home/root/.config"))
		.join("hishell")
		.join("session.json")
}

fn load() -> Session {
	let mut cached = SESSION.lock().unwrap();
	if cached.is_none() {
		*cached = Some(load_uncached());
	}
	cached.clone().unwrap_or_default()
}

fn load_uncached() -> Session {
	fs::read_to_string(file())
		.ok()
		.and_then(|text| serde_json::from_str(&text).ok())
		.unwrap_or_default()
}

/// The folder to open at startup: the saved one when it still exists, else the
/// fallback the caller computed (the command line argument or the home).
pub fn startup_path(fallback: &str) -> String {
	let path = load().path;
	if !path.is_empty() && Path::new(&path).is_dir() {
		return path;
	}
	fallback.to_string()
}

/// The item to focus at startup, when one was saved.
pub fn startup_focus() -> Option<String> {
	let focus = load().focus;
	(!focus.is_empty()).then_some(focus)
}

pub fn save_path(path: &str) {
	update(|session| session.path = path.to_string());
}

pub fn save_focus(path: &str) {
	if path.is_empty() {
		return;
	}
	update(|session| session.focus = path.to_string());
}

fn update(mutate: impl FnOnce(&mut Session)) {
	let mut cached = SESSION.lock().unwrap();
	let session = cached.get_or_insert_with(load_uncached);
	let before = session.clone();
	mutate(session);
	if *session == before {
		return;
	}
	let text = serde_json::to_string(session).unwrap_or_default();
	let target = file();
	if let Some(parent) = target.parent() {
		let _ = fs::create_dir_all(parent);
	}
	// Write-and-rename, with the scratch file NEXT TO the target: a scratch in
	// /tmp would make the rename fail with EXDEV (tmpfs vs the home's ext2).
	let temporary = PathBuf::from(format!("{}.tmp", target.display()));
	if fs::write(&temporary, text).is_ok() {
		let _ = fs::rename(&temporary, target);
	}
}

/// Whether an app currently owns the panels (the host's suspend marker).
/// Callers poll this; it is one stat on tmpfs, and the marker self-expires, so
/// a host that died cannot keep it up forever.
pub fn suspended() -> bool {
	marker_fresh(&env_path(ENV_SUSPEND))
}

/// Whether the host has revealed the app on screen and the shell should unmap
/// until it exits.
pub fn hidden() -> bool {
	marker_fresh(&env_path(ENV_HIDE))
}

/// Image the shell shows for a moment on the way back from an app, or empty.
pub fn return_frame_path() -> String {
	env_path(ENV_RETURN_FRAME)
}

/// File the shell publishes the focused item to, or empty when the host has
/// not asked for one.
pub fn focus_file() -> String {
	env_path(ENV_FOCUS)
}

fn marker_fresh(path: &str) -> bool {
	let Ok(metadata) = fs::metadata(path) else {
		return false;
	};
	let Ok(modified) = metadata.modified() else {
		return false;
	};
	match modified.elapsed() {
		Ok(age) => age < MARKER_MAX_AGE,
		// A modification time in the future is a recent write under clock skew.
		Err(_) => true,
	}
}
