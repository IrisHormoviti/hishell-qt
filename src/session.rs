//! Last shell location, persisted across restarts.
//!
//! Returning from a guest app must land back where the user was — and so must
//! a crash, a redeploy or a reboot. The shell therefore saves the folder it is
//! browsing and the item its cursor sits on, and picks both up at startup:
//! `main` opens the saved folder directly, and the FocusManager re-applies the
//! saved focus to the first file view that loads it.
//!
//! The file format, schema version, atomic write, and backward-compatible load
//! live in `hishell::session::SessionStore`; this module keeps the host session
//! handover markers, which are ClamOS-specific runtime state rather than saved
//! shell state.

use std::fs;
use std::path::PathBuf;
use std::time::Duration;

use hishell::{SessionData, SessionStore};
use once_cell::sync::Lazy;

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
/// * `ACTIVE` — file whose contents change whenever the set of suspended
///   items changes, so the shell refreshes the per-item "active" marks.
/// * `INPUT_GRAB` — set while a launched app has taken the gamepad for itself
///   (the connection dialog): the shell keeps drawing and keeps the touch
///   panel, but must not act on the pad.
const ENV_SUSPEND: &str = "HISHELL_SESSION_SUSPEND";
const ENV_HIDE: &str = "HISHELL_SESSION_HIDE";
const ENV_RETURN_FRAME: &str = "HISHELL_SESSION_RETURN_FRAME";
const ENV_FOCUS: &str = "HISHELL_SESSION_FOCUS";
const ENV_ACTIVE: &str = "HISHELL_SESSION_ACTIVE";
const ENV_INPUT_GRAB: &str = "HISHELL_SESSION_INPUT_GRAB";

/// Ignore window for a stale marker: if the host died before it could remove
/// its files, the shell must not stay hidden forever.
const MARKER_MAX_AGE: Duration = Duration::from_secs(3600);

/// Ignore window for the input grab, which is much shorter: the grabber
/// re-writes its marker several times a second while it runs, so a marker that
/// stops moving means the grabber is gone and the shell should take the pad
/// back on its own — a crash there must not leave the buttons dead.
const GRAB_MAX_AGE: Duration = Duration::from_secs(15);

static STORE: Lazy<SessionStore> = Lazy::new(SessionStore::default);

fn env_path(name: &str) -> String {
	std::env::var(name).unwrap_or_default()
}

fn load() -> SessionData {
	STORE.load()
}

/// The folder to open at startup: the saved one when it still exists, else the
/// fallback the caller computed (the command line argument or the home).
pub fn startup_path(fallback: &str) -> String {
	let path = load().path;
	if !path.as_os_str().is_empty() && path.is_dir() {
		return path.to_string_lossy().into_owned();
	}
	fallback.to_string()
}

/// The item to focus at startup, when one was saved.
pub fn startup_focus() -> Option<String> {
	load()
		.focus
		.map(|path| path.to_string_lossy().into_owned())
		.filter(|focus| !focus.is_empty())
}

pub fn save_path(path: &str) {
	update(|session| session.path = PathBuf::from(path));
}

pub fn save_focus(path: &str) {
	if path.is_empty() {
		return;
	}
	update(|session| session.focus = Some(PathBuf::from(path)));
}

fn update(mutate: impl FnOnce(&mut SessionData)) {
	let mut session = load();
	let before = session.clone();
	mutate(&mut session);
	if session != before {
		let _ = STORE.save(&session);
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

/// Whether a launched app has taken the gamepad for itself. The shell stays
/// visible and keeps its touch panel, but drops every pad input while this is
/// up: the pad is read from evdev directly, so it is the only way to hand the
/// buttons over (docs §5.6).
pub fn input_grabbed() -> bool {
	marker_fresh_within(&env_path(ENV_INPUT_GRAB), GRAB_MAX_AGE)
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

/// Revision of the host's suspended-item set. A host that can suspend more
/// than one item writes a new value whenever the set changes; the file view
/// then re-queries `--active-items`. Empty when the host has no such file.
pub fn active_revision() -> String {
	let path = env_path(ENV_ACTIVE);
	if path.is_empty() {
		return String::new();
	}
	fs::read_to_string(path)
		.map(|text| text.trim().to_string())
		.unwrap_or_default()
}

fn marker_fresh(path: &str) -> bool {
	marker_fresh_within(path, MARKER_MAX_AGE)
}

fn marker_fresh_within(path: &str, max_age: Duration) -> bool {
	let Ok(metadata) = fs::metadata(path) else {
		return false;
	};
	let Ok(modified) = metadata.modified() else {
		return false;
	};
	match modified.elapsed() {
		Ok(age) => age < max_age,
		// A modification time in the future is a recent write under clock skew.
		Err(_) => true,
	}
}
