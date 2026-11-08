//! Launch adapter over the core execution service.
//!
//! The wrapper, preflight, confirm/cancel, environment, launch marker, active
//! items, and quit all live in `hishell::execution`. This module only keeps the
//! process-global handle the shipping frontend reaches from QML, plus the
//! direct spawn that provider commands need because they wait on the child.

use std::io;
use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::sync::Mutex;

pub use hishell::execution::{ITEM_ENV, NAME_ENV, SCREEN_ENV};
use hishell::{Execution, ExecutionWrapper, LaunchId, LaunchOutcome, SpawnRequest};
use once_cell::sync::Lazy;

static EXECUTION: Lazy<Mutex<Execution>> =
	Lazy::new(|| Mutex::new(Execution::free_desktop(None, None)));
static PENDING: Lazy<Mutex<Option<LaunchId>>> = Lazy::new(|| Mutex::new(None));

pub fn set_wrapper(wrapper: &str) {
	let wrapper = wrapper.trim();
	EXECUTION
		.lock()
		.unwrap()
		.set_wrapper((!wrapper.is_empty()).then(|| ExecutionWrapper {
			command: wrapper.to_string(),
		}));
}

pub fn set_screen(screen: &str) {
	let screen = screen.trim();
	EXECUTION
		.lock()
		.unwrap()
		.set_screen((!screen.is_empty()).then(|| screen.to_string()));
}

/// The outcome of asking to launch something.
pub enum Launch {
	/// The program was started (or, with no wrapper, started directly).
	Started,
	/// A different item's app is suspended and this launch would close it. The
	/// wrapper reported that item's path so the caller can name it and confirm.
	NeedsConfirm(String),
	/// Starting failed. Carries the error.
	Failed(String),
}

/// Ask to launch `program` with `args`, in `cwd` when given. `item` is the path
/// of the item the launch is for and `name` its application's display name.
/// With a wrapper this runs its preflight first; when that asks for a
/// confirmation the launch is remembered and [`confirm`] finishes it.
pub fn request(
	program: &str,
	args: &[String],
	item: &str,
	name: &str,
	animation: &str,
	cwd: Option<&Path>,
) -> Launch {
	let request = SpawnRequest {
		program: program.to_string(),
		args: args.to_vec(),
		item: PathBuf::from(item),
		name: name.to_string(),
		cwd: cwd.map(Path::to_path_buf),
		animation: animation.to_string(),
		screen: None,
		through_wrapper: true,
	};
	let outcome = EXECUTION.lock().unwrap().request_spawn(request);
	match outcome {
		Ok(LaunchOutcome::Started) => Launch::Started,
		Ok(LaunchOutcome::NeedsConfirmation { id, warning }) => {
			*PENDING.lock().unwrap() = Some(id);
			Launch::NeedsConfirm(warning.item.to_string_lossy().into_owned())
		}
		Ok(LaunchOutcome::Blocked { reason }) => Launch::Failed(format!("{reason:?}")),
		Err(error) => Launch::Failed(format!("{error:?}")),
	}
}

/// Start the launch held back by [`request`], returning whether one was pending.
pub fn confirm() -> bool {
	let Some(id) = PENDING.lock().unwrap().take() else {
		return false;
	};
	EXECUTION.lock().unwrap().confirm(id).is_ok()
}

/// Forget a launch held back by [`request`].
pub fn cancel() {
	if let Some(id) = PENDING.lock().unwrap().take() {
		EXECUTION.lock().unwrap().cancel(id);
	}
}

/// Reduce a launch outcome to what a launch site returns to QML: the path of
/// the item whose suspended app this launch would close, or empty when it
/// started (failures are logged).
pub fn result(launch: Launch) -> String {
	match launch {
		Launch::Started => String::new(),
		Launch::NeedsConfirm(item) => item,
		Launch::Failed(error) => {
			eprintln!("could not launch: {error}");
			String::new()
		}
	}
}

/// A display name for a program path, used when no desktop entry provides one.
pub fn app_name(path: &str) -> String {
	Path::new(path)
		.file_name()
		.map(|name| name.to_string_lossy().into_owned())
		.unwrap_or_default()
}

/// The file title of an item (its `.directory`/desktop-entry name, else its
/// file name), the same title the views show.
pub fn item_title(path: &str) -> String {
	crate::directory::get_item_title(Path::new(path))
}

/// The icon source of an item (a `file://` URL, a themed icon name or a path),
/// the same icon the views show.
pub fn item_icon(path: &str) -> String {
	crate::directory::get_icon(path)
}

/// The art for an item in a dialog: its thumbnail (finished, or queued for the
/// next visit) when it has one — so box art shows, matching the file view — and
/// otherwise its regular icon.
pub fn item_art(path: &str) -> String {
	let thumbnail = crate::thumbnailer::result_for(path).or_else(|| {
		let folder = Path::new(path).parent().map(Path::to_path_buf)?;
		crate::thumbnailer::request(Path::new(path), 128, &folder)
	});
	thumbnail.unwrap_or_else(|| item_icon(path))
}

/// Ask the wrapper which items currently have an active (suspended) app, so the
/// file view can mark them. Empty when there is no wrapper or nothing is active.
pub fn active_items() -> Vec<String> {
	EXECUTION
		.lock()
		.unwrap()
		.active_items()
		.into_iter()
		.map(|path| path.to_string_lossy().into_owned())
		.collect()
}

/// Ask the wrapper to quit the guest for `item` and drop its saved state.
/// Returns whether the wrapper accepted the request.
pub fn quit_active(item: &str) -> bool {
	EXECUTION.lock().unwrap().quit(Path::new(item)).is_ok()
}

/// Spawn `program` with `args` **directly**, bypassing the execution wrapper.
///
/// For entries that are controls rather than apps (`Type=Button`): a settings
/// action must not go through the guest-app preflight/lifecycle. The item and
/// name env vars are still exported, so the program can identify itself.
pub fn spawn_direct(
	program: &str,
	args: &[String],
	item: &str,
	name: &str,
	cwd: Option<&Path>,
) -> io::Result<Child> {
	let screen = EXECUTION.lock().unwrap().screen().map(str::to_string);
	let mut command = Command::new(program);
	command.args(args);
	if !item.is_empty() {
		command.env(ITEM_ENV, item);
	}
	if !name.is_empty() {
		command.env(NAME_ENV, name);
	}
	if let Some(screen) = screen.as_deref().filter(|screen| !screen.is_empty()) {
		command.env(SCREEN_ENV, screen);
	}
	if let Some(cwd) = cwd {
		command.current_dir(cwd);
	}
	command.spawn()
}
