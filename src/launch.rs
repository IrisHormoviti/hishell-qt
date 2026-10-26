//! Launching programs, with the host's execution wrapper applied.
//!
//! A host can set `[Layout] ExecutionWrapper` to a command that every launch is
//! run through, so it can supervise starts (session transitions, suspend and
//! resume, per-item bookkeeping) without that logic living in the shell. The
//! program and its arguments are appended to the wrapper, and paths of the item
//! and application name are exported as `HISHELL_APP_ITEM` / `HISHELL_APP_NAME`.
//!
//! Before a launch the wrapper is asked, in `--preflight` mode, whether it would
//! displace something (e.g. a different suspended app the host would have to
//! close). If it answers with a message, the launch is held back and the caller
//! is expected to confirm it with the user, then call [`confirm`].

use std::io;
use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::sync::Mutex;

use once_cell::sync::Lazy;

/// Environment variable carrying the path of the item a program was launched
/// for, so the wrapper can associate the program with it.
pub const ITEM_ENV: &str = "HISHELL_APP_ITEM";

/// Environment variable carrying the launched application's display name, so
/// the wrapper can name it in messages.
pub const NAME_ENV: &str = "HISHELL_APP_NAME";

/// Environment variable carrying the name of the output the shell is on, so a
/// program it launches can open its window on the same panel. The shell's own
/// output is the `[Layout] Screen` setting; without it the window would land on
/// the platform default, which on a two-panel device is the other panel
/// (docs §5.6).
pub const SCREEN_ENV: &str = "HISHELL_SCREEN";

/// The configured wrapper. Kept here so every launch site can reach it without
/// threading the owning `Config` through each call; it is a host setting, so
/// every `Config` carries the same value and the last one loaded is fine.
static WRAPPER: Lazy<Mutex<String>> = Lazy::new(|| Mutex::new(String::new()));

/// The output the shell is on, from `[Layout] Screen`. Empty means the platform
/// default, and then no `HISHELL_SCREEN` is exported at all.
static SCREEN: Lazy<Mutex<String>> = Lazy::new(|| Mutex::new(String::new()));

/// A launch held back for confirmation.
struct Pending {
	program: String,
	args: Vec<String>,
	item: String,
	name: String,
	animation: String,
	cwd: Option<PathBuf>,
}

static PENDING: Lazy<Mutex<Option<Pending>>> = Lazy::new(|| Mutex::new(None));

pub fn set_wrapper(wrapper: &str) {
	*WRAPPER.lock().unwrap() = wrapper.to_string();
}

pub fn set_screen(screen: &str) {
	*SCREEN.lock().unwrap() = screen.to_string();
}

/// Export the environment every launch carries: the item's path, the
/// application's display name, and the shell's output when it has one.
fn apply_launch_env(command: &mut Command, item: &str, name: &str) {
	if !item.is_empty() {
		command.env(ITEM_ENV, item);
	}
	if !name.is_empty() {
		command.env(NAME_ENV, name);
	}
	let screen = SCREEN.lock().unwrap().clone();
	if !screen.is_empty() {
		command.env(SCREEN_ENV, screen);
	}
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
	let wrapper = WRAPPER.lock().unwrap().clone();
	if wrapper.trim().is_empty() || !command_exists(&wrapper) {
		return spawn_now(program, args, item, name, animation, cwd);
	}
	match preflight(&wrapper, program, args, item, name) {
		Some(message) => {
			*PENDING.lock().unwrap() = Some(Pending {
				program: program.to_string(),
				args: args.to_vec(),
				item: item.to_string(),
				name: name.to_string(),
				animation: animation.to_string(),
				cwd: cwd.map(Path::to_path_buf),
			});
			Launch::NeedsConfirm(message)
		}
		None => spawn_now(program, args, item, name, animation, cwd),
	}
}

/// Start the launch held back by [`request`], returning whether one was pending.
pub fn confirm() -> bool {
	let pending = PENDING.lock().unwrap().take();
	let Some(pending) = pending else {
		return false;
	};
	matches!(
		spawn_now(
			&pending.program,
			&pending.args,
			&pending.item,
			&pending.name,
			&pending.animation,
			pending.cwd.as_deref(),
		),
		Launch::Started
	)
}

/// Forget a launch held back by [`request`].
pub fn cancel() {
	*PENDING.lock().unwrap() = None;
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
/// file view can mark them. Runs `<wrapper> --active-items`, one path per line.
/// Empty when there is no wrapper or nothing is active.
pub fn active_items() -> Vec<String> {
	let wrapper = WRAPPER.lock().unwrap().clone();
	if wrapper.trim().is_empty() || !command_exists(&wrapper) {
		return Vec::new();
	}
	let parts: Vec<String> = wrapper.split_whitespace().map(String::from).collect();
	let Some((head, rest)) = parts.split_first() else {
		return Vec::new();
	};
	let mut command = Command::new(head);
	command.args(rest);
	command.arg("--active-items");
	let Ok(output) = command.output() else {
		return Vec::new();
	};
	String::from_utf8_lossy(&output.stdout)
		.lines()
		.map(str::trim)
		.filter(|line| !line.is_empty())
		.map(String::from)
		.collect()
}

fn spawn_now(
	program: &str,
	args: &[String],
	item: &str,
	name: &str,
	animation: &str,
	cwd: Option<&Path>,
) -> Launch {
	match spawn(program, args, item, name, animation, cwd) {
		Ok(_) => Launch::Started,
		Err(error) => {
			withdraw_launch();
			Launch::Failed(error.to_string())
		}
	}
}

/// Where the compositor watches for launch animations. The host owns the
/// directory; the fallback matches its default.
fn launch_marker() -> PathBuf {
	if let Ok(path) = std::env::var("CLAM_LAUNCH_MARKER")
		&& !path.is_empty()
	{
		return PathBuf::from(path);
	}
	let dir = std::env::var("CLAM_APP_MANAGER_DIR")
		.unwrap_or_else(|_| String::from("/tmp/clam-app-manager"));
	PathBuf::from(dir).join("launch")
}

/// Tell the compositor to wash the screens for this launch. `animation` is
/// `white` or `black`, from the desktop entry's `LaunchAnimation` key; empty
/// means the entry did not ask for one. The item lets the compositor leave a
/// resume to the card animation instead.
fn announce_launch(animation: &str, item: &str) {
	let animation = animation.trim();
	if animation != "white" && animation != "black" {
		return;
	}
	let path = launch_marker();
	if let Some(parent) = path.parent() {
		let _ = std::fs::create_dir_all(parent);
	}
	let nonce = std::time::SystemTime::now()
		.duration_since(std::time::UNIX_EPOCH)
		.map(|elapsed| elapsed.as_nanos())
		.unwrap_or(0);
	let text = format!("{animation}\n{nonce}\n{item}\n");
	let temporary = path.with_extension("tmp");
	if std::fs::write(&temporary, text).is_ok() {
		let _ = std::fs::rename(&temporary, path);
	}
}

/// The launch did not start after all: let the compositor fade the wash out
/// instead of holding it until its timeout.
fn withdraw_launch() {
	let _ = std::fs::remove_file(launch_marker());
}

/// Run the wrapper in `--preflight` mode and return its message, if any.
fn preflight(
	wrapper: &str,
	program: &str,
	args: &[String],
	item: &str,
	name: &str,
) -> Option<String> {
	let parts: Vec<String> = wrapper.split_whitespace().map(String::from).collect();
	let (head, rest) = parts.split_first()?;
	let mut command = Command::new(head);
	command.args(rest);
	command.arg("--preflight");
	command.arg(program);
	command.args(args);
	apply_launch_env(&mut command, item, name);
	let output = command.output().ok()?;
	let message = String::from_utf8_lossy(&output.stdout).trim().to_string();
	(!message.is_empty()).then_some(message)
}

/// Whether the wrapper's command exists, so a stale config cannot break every
/// launch (the check is a cheap `which`-style path test for the common case).
fn command_exists(command: &str) -> bool {
	let program = command.split_whitespace().next().unwrap_or_default();
	if program.is_empty() {
		return false;
	}
	if program.contains('/') {
		return Path::new(program).exists();
	}
	std::env::var_os("PATH")
		.map(|paths| std::env::split_paths(&paths).any(|dir| dir.join(program).exists()))
		.unwrap_or(false)
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
	let mut command = Command::new(program);
	command.args(args);
	apply_launch_env(&mut command, item, name);
	if let Some(cwd) = cwd {
		command.current_dir(cwd);
	}
	command.spawn()
}

/// Spawn `program` with `args`, through the configured wrapper, in `cwd` when
/// given. `item` and `name` are exported to the wrapper.
pub fn spawn(
	program: &str,
	args: &[String],
	item: &str,
	name: &str,
	animation: &str,
	cwd: Option<&Path>,
) -> io::Result<Child> {
	let wrapper = WRAPPER.lock().unwrap().clone();
	let parts: Vec<String> = wrapper.split_whitespace().map(String::from).collect();
	let mut command = match parts.as_slice() {
		[] => {
			let mut command = Command::new(program);
			command.args(args);
			command
		}
		[head, rest @ ..] => {
			// The wrapper is a plain command line (no field codes); it takes the
			// real program and its arguments as its own.
			let mut command = Command::new(head);
			command.args(rest);
			command.arg(program);
			command.args(args);
			command
		}
	};
	apply_launch_env(&mut command, item, name);
	if let Some(cwd) = cwd {
		command.current_dir(cwd);
	}
	announce_launch(animation, item);
	command.spawn()
}
