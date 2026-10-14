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

/// Set by `hishell-launch-guest` while a guest app owns the panels. The shell
/// and clam-topscreen wash themselves to white while it exists, so the launch
/// looks like a deliberate transition instead of a crash.
const SUSPEND_FILE: &str = "/tmp/clam-shell.suspend";

/// Set by the wrapper once the guest is on screen: the shell apps unmap so
/// the guest's window (which sits below them) is revealed.
const HIDE_FILE: &str = "/tmp/clam-shell.hide";

/// Ignore window for a stale marker: if the wrapper died before it could
/// remove its files, the shell must not stay hidden forever.
const MARKER_MAX_AGE: Duration = Duration::from_secs(3600);

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

/// Whether a guest currently owns the panels. Callers poll this; it is one
/// stat on tmpfs and self-expires, so a dead wrapper cannot keep the markers
/// up forever.
pub fn suspended() -> bool {
	marker_fresh(SUSPEND_FILE)
}

/// Whether the wrapper has revealed the guest and the shell apps should unmap
/// until the guest exits.
pub fn hidden() -> bool {
	marker_fresh(HIDE_FILE)
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
