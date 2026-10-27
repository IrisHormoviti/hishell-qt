//! Ask the system keyboard for a string.
//!
//! The ClamOS keyboard already draws the text being typed with its own OK and
//! Cancel bar, and it covers the touch panel while it is up. A dialog with a
//! second text field would only be hidden underneath it, so simple text entry
//! (a rename, for one) is a request to the keyboard instead.
//!
//! The keyboard is a separate process, so the exchange uses files in the same
//! directory as its placeholder hint (`/tmp/clam-keyboard`, overridable with
//! `CLAMKEYBOARD_ENTRY_DIR`):
//!
//! ```text
//! request:                 response:
//! id=42-7                  id=42-7
//! prompt=Rename            status=ok
//! cursor=stem              text=New Name
//! text=Old Name
//! ```
//!
//! `request` refuses when the keyboard's liveness marker is missing or stale,
//! and callers fall back to their own dialog. That is what keeps the shell
//! usable on systems without ClamOS's keyboard.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// A keyboard that has not refreshed its marker for this long is gone. The
/// keyboard refreshes it once a second while its event loop runs.
const READY_MAX_AGE: Duration = Duration::from_secs(5);

static NEXT_ID: AtomicU64 = AtomicU64::new(0);

/// What happened to a request.
pub enum Poll {
	Pending,
	Accepted(String),
	Cancelled,
}

fn dir() -> PathBuf {
	std::env::var("CLAMKEYBOARD_ENTRY_DIR")
		.ok()
		.filter(|value| !value.is_empty())
		.map_or_else(|| PathBuf::from("/tmp/clam-keyboard"), PathBuf::from)
}

fn request_path(dir: &Path) -> PathBuf {
	dir.join("request")
}

fn response_path(dir: &Path) -> PathBuf {
	dir.join("response")
}

fn field<'a>(body: &'a str, key: &str) -> Option<&'a str> {
	let prefix = format!("{key}=");
	body.lines()
		.find_map(|line| line.strip_prefix(prefix.as_str()))
}

fn fresh_marker(dir: &Path) -> bool {
	let Ok(metadata) = fs::metadata(dir.join("ready")) else {
		return false;
	};
	metadata
		.modified()
		.ok()
		.and_then(|time| time.elapsed().ok())
		.is_some_and(|age| age < READY_MAX_AGE)
}

/// Whether the system keyboard is running and can take a request.
pub fn available() -> bool {
	fresh_marker(&dir())
}

/// Ask for a string. Returns the request id, or `None` when the keyboard is not
/// available or the request could not be written.
pub fn request(prompt: &str, text: &str, cursor: &str) -> Option<String> {
	request_in(&dir(), prompt, text, cursor)
}

fn request_in(dir: &Path, prompt: &str, text: &str, cursor: &str) -> Option<String> {
	if !fresh_marker(dir) {
		return None;
	}
	fs::create_dir_all(dir).ok()?;
	let stamp = SystemTime::now()
		.duration_since(UNIX_EPOCH)
		.ok()?
		.as_nanos();
	let id = format!(
		"{}-{stamp}-{}",
		std::process::id(),
		NEXT_ID.fetch_add(1, Ordering::Relaxed)
	);
	let body = format!(
		"id={id}\nprompt={}\ncursor={}\ntext={}\n",
		prompt.replace(['\n', '\r'], " "),
		cursor.replace(['\n', '\r'], " "),
		text.replace(['\n', '\r'], " ")
	);
	// A response still lying around belongs to an earlier request; an id match
	// would otherwise be the only thing between it and this one.
	let _ = fs::remove_file(response_path(dir));
	let temporary = dir.join(format!("request.tmp.{id}"));
	fs::write(&temporary, body).ok()?;
	fs::rename(&temporary, request_path(dir)).ok()?;
	Some(id)
}

/// Check for the response to `id`.
pub fn poll(id: &str) -> Poll {
	poll_in(&dir(), id)
}

fn poll_in(dir: &Path, id: &str) -> Poll {
	let Ok(body) = fs::read_to_string(response_path(dir)) else {
		return Poll::Pending;
	};
	if field(&body, "id") != Some(id) {
		return Poll::Pending;
	}
	let status = field(&body, "status").unwrap_or("");
	let text = field(&body, "text").unwrap_or("").to_string();
	match status {
		"ok" => {
			let _ = fs::remove_file(response_path(dir));
			Poll::Accepted(text)
		}
		"cancel" => {
			let _ = fs::remove_file(response_path(dir));
			Poll::Cancelled
		}
		_ => Poll::Pending,
	}
}

/// Withdraw a request that is still waiting. A response that has already been
/// written for this id goes too, so a late reply cannot be read later.
pub fn cancel(id: &str) {
	cancel_in(&dir(), id);
}

fn cancel_in(dir: &Path, id: &str) {
	let request = request_path(dir);
	if fs::read_to_string(&request)
		.ok()
		.and_then(|body| field(&body, "id").map(str::to_string))
		.as_deref()
		== Some(id)
	{
		let _ = fs::remove_file(&request);
	}
	let response = response_path(dir);
	if fs::read_to_string(&response)
		.ok()
		.and_then(|body| field(&body, "id").map(str::to_string))
		.as_deref()
		== Some(id)
	{
		let _ = fs::remove_file(&response);
	}
}

#[cfg(test)]
mod tests {
	use super::{Poll, cancel_in, poll_in, request_in};
	use std::fs;
	use std::path::PathBuf;
	use std::time::{SystemTime, UNIX_EPOCH};

	fn scratch(name: &str) -> PathBuf {
		let stamp = SystemTime::now()
			.duration_since(UNIX_EPOCH)
			.unwrap()
			.as_nanos();
		let dir = std::env::temp_dir().join(format!("hishell-keyboard-{name}-{stamp}"));
		fs::create_dir_all(&dir).unwrap();
		fs::write(dir.join("ready"), b"test\n").unwrap();
		dir
	}

	#[test]
	fn round_trips_a_request_and_response() {
		let dir = scratch("round-trip");
		let id = request_in(&dir, "Rename", "Old Name.nds", "stem").expect("a request");
		let body = fs::read_to_string(dir.join("request")).unwrap();
		assert!(body.contains("cursor=stem"));
		assert!(body.contains("text=Old Name.nds"));

		fs::write(
			dir.join("response"),
			format!("id={id}\nstatus=ok\ntext=New Name.nds\n"),
		)
		.unwrap();
		match poll_in(&dir, &id) {
			Poll::Accepted(text) => assert_eq!(text, "New Name.nds"),
			_ => panic!("expected an accepted response"),
		}
		assert!(!dir.join("response").exists());
		fs::remove_dir_all(dir).ok();
	}

	#[test]
	fn a_response_for_another_request_is_not_taken() {
		let dir = scratch("other-id");
		let id = request_in(&dir, "Rename", "Old", "end").expect("a request");
		fs::write(
			dir.join("response"),
			"id=someone-else\nstatus=ok\ntext=Wrong\n",
		)
		.unwrap();
		assert!(matches!(poll_in(&dir, &id), Poll::Pending));
		fs::remove_dir_all(dir).ok();
	}

	#[test]
	fn cancel_removes_the_waiting_request() {
		let dir = scratch("cancel");
		let id = request_in(&dir, "Rename", "Old", "end").expect("a request");
		cancel_in(&dir, &id);
		assert!(!dir.join("request").exists());
		fs::remove_dir_all(dir).ok();
	}
}
