use gilrs::{Axis, Button, EventType, Gilrs};
use once_cell::sync::Lazy;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::{Duration, Instant};

// How long a direction must be held before it repeats at all. Without this
// pause a normal-length press outlasts the repeat interval and steps twice.
const REPEAT_DELAY: Duration = Duration::from_millis(400);
// Slightly longer than the focus scroll animation in FolderView.qml, so a
// held direction arrives as a sequence of finished steps rather than a stream
// of animations that each cancel the one before.
const REPEAT_INTERVAL: Duration = Duration::from_millis(120);
const STICK_THRESHOLD: f32 = 0.35;
/// After the shell was frozen (a guest owned the panels), ignore the pad for a
/// moment. Reopening the devices already throws away the events the kernel
/// queued while the process was stopped; the grace period also skips the
/// synthetic press of a button that is still physically held.
const RESUME_GRACE: Duration = Duration::from_millis(400);
/// A pause this much longer than the 200 ms poll is not a slow scheduler: the
/// process was stopped.
const STOPPED_GAP: Duration = Duration::from_secs(1);

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Input {
	Up,
	Down,
	Left,
	Right,
	Accept,
	Cancel,
	Menu,
	Select,
	Directory,
}

impl Input {
	pub fn as_str(&self) -> &'static str {
		match self {
			Input::Up => "up",
			Input::Down => "down",
			Input::Left => "left",
			Input::Right => "right",
			Input::Accept => "accept",
			Input::Cancel => "cancel",
			Input::Menu => "menu",
			Input::Select => "select",
			Input::Directory => "directory",
		}
	}
}

#[derive(Default)]
struct State {
	dpad_up: bool,
	dpad_down: bool,
	dpad_left: bool,
	dpad_right: bool,
	stick_x: f32,
	stick_y: f32,
}

static STATE: Lazy<Mutex<State>> = Lazy::new(|| Mutex::new(State::default()));
static QUEUE: Lazy<Mutex<Vec<Input>>> = Lazy::new(|| Mutex::new(Vec::new()));
/// The direction being held, when it was last dispatched, and how many
/// repeats it has produced. `count` stays zero until the initial delay has
/// passed, which separates "first repeat" from the cadence after it.
struct Repeat {
	input: Option<Input>,
	when: Instant,
	count: u32,
}

static REPEAT_STATE: Lazy<Mutex<Repeat>> = Lazy::new(|| {
	Mutex::new(Repeat {
		input: None,
		when: Instant::now(),
		count: 0,
	})
});
static STARTED: AtomicBool = AtomicBool::new(false);
/// When the shell last came back from being frozen.
static RESUMED: Lazy<Mutex<Option<Instant>>> = Lazy::new(|| Mutex::new(None));

/// Queues an input that came from somewhere other than the gamepad, such as
/// the keyboard menu key. It is dispatched through the same routing as the
/// controller so that both behave identically.
pub fn push(input: Input) {
	if let Ok(mut queue) = QUEUE.lock() {
		queue.push(input);
	}
}

/// Drops every queued and in-flight input, and forgets the held-button and
/// repeat state. Called when the shell takes the panels back from a guest: the
/// presses that piled up while the shell was paused belong to the app, and a
/// button still held at that moment must not fire the moment the shell resumes
/// (which would relaunch the app that was just closed).
pub fn discard() {
	if let Ok(mut queue) = QUEUE.lock() {
		queue.clear();
	}
	if let Ok(mut state) = STATE.lock() {
		*state = State::default();
	}
	if let Ok(mut repeat) = REPEAT_STATE.lock() {
		*repeat = Repeat {
			input: None,
			when: Instant::now(),
			count: 0,
		};
	}
}

#[unsafe(no_mangle)]
pub extern "C" fn hishell_menu_key_pressed() {
	push(Input::Menu);
}

/// Starts the gilrs event pump. gilrs normalises controllers through the SDL
/// mapping database, so d-pads, sticks and face buttons mean the same thing
/// regardless of the controller or the mode it is connected in.
pub fn init() {
	if STARTED.swap(true, Ordering::SeqCst) {
		return;
	}

	thread::spawn(|| {
		let mut gilrs = match Gilrs::new() {
			Ok(gilrs) => gilrs,
			Err(error) => {
				println!("gamepad: unavailable ({})", error);
				return;
			}
		};
		// println!("gamepad: ready");
		snapshot(&gilrs);

		loop {
			let before = Instant::now();
			let event = gilrs.next_event_blocking(Some(Duration::from_millis(200)));
			// The compositor freezes the shell with SIGSTOP while a guest owns
			// the panels. The kernel keeps queueing that device's events for
			// the stopped process, so on resume gilrs would hand the file view
			// every button pressed during the game. Reopen the devices instead:
			// the old file descriptions (and their backlog) go away.
			if before.elapsed() > STOPPED_GAP {
				discard();
				if let Ok(mut resumed) = RESUMED.lock() {
					*resumed = Some(Instant::now());
				}
				match Gilrs::new() {
					Ok(fresh) => {
						gilrs = fresh;
						snapshot(&gilrs);
					}
					Err(error) => println!("gamepad: reopen after resume failed ({error})"),
				}
				continue;
			}
			if let Some(event) = event
				&& let EventType::ButtonPressed(button, _) = event.event
				&& let Some(input) = button_input(button)
				&& let Ok(mut queue) = QUEUE.lock()
			{
				queue.push(input);
			}
			snapshot(&gilrs);
		}
	});
}

/// Non-blocking read of the next navigation input. Held directions repeat
/// after a short delay; buttons are edge-triggered.
pub fn poll() -> Option<Input> {
	// Nothing pressed during the guest session or while the shell was stopped
	// may reach the file view on the way back.
	if let Ok(resumed) = RESUMED.lock()
		&& let Some(at) = *resumed
		&& at.elapsed() < RESUME_GRACE
	{
		return None;
	}
	if let Ok(mut queue) = QUEUE.lock()
		&& !queue.is_empty()
	{
		return Some(queue.remove(0));
	}

	let direction = held_direction();
	let mut repeat = match REPEAT_STATE.lock() {
		Ok(repeat) => repeat,
		Err(_) => return None,
	};
	let now = Instant::now();
	match direction {
		Some(input) => {
			if repeat.input == Some(input) {
				let wait = if repeat.count == 0 {
					REPEAT_DELAY
				} else {
					REPEAT_INTERVAL
				};
				if now.duration_since(repeat.when) < wait {
					return None;
				}
				repeat.count = repeat.count.saturating_add(1);
			} else {
				repeat.count = 0;
			}
			repeat.input = Some(input);
			repeat.when = now;
			Some(input)
		}
		None => {
			repeat.input = None;
			repeat.count = 0;
			None
		}
	}
}

fn snapshot(gilrs: &Gilrs) {
	let mut state = State::default();

	for (_, gamepad) in gilrs.gamepads() {
		if !gamepad.is_connected() {
			continue;
		}
		state.dpad_up |= gamepad.is_pressed(Button::DPadUp);
		state.dpad_down |= gamepad.is_pressed(Button::DPadDown);
		state.dpad_left |= gamepad.is_pressed(Button::DPadLeft);
		state.dpad_right |= gamepad.is_pressed(Button::DPadRight);

		let x = gamepad.value(Axis::LeftStickX);
		let y = gamepad.value(Axis::LeftStickY);
		if x.abs() > state.stick_x.abs() {
			state.stick_x = x;
		}
		if y.abs() > state.stick_y.abs() {
			state.stick_y = y;
		}
	}

	if let Ok(mut current) = STATE.lock() {
		*current = state;
	}
}

fn button_input(button: Button) -> Option<Input> {
	match button {
		Button::South => Some(Input::Accept),
		Button::East => Some(Input::Cancel),
		Button::North => Some(Input::Menu),
		Button::West => Some(Input::Select),
		Button::Start => Some(Input::Directory),
		_ => None,
	}
}

fn held_direction() -> Option<Input> {
	let state = STATE.lock().ok()?;

	let mut x: i32 = 0;
	let mut y: i32 = 0;

	if state.dpad_left {
		x -= 1;
	}
	if state.dpad_right {
		x += 1;
	}
	if state.dpad_up {
		y -= 1;
	}
	if state.dpad_down {
		y += 1;
	}

	if state.stick_x < -STICK_THRESHOLD {
		x -= 1;
	}
	if state.stick_x > STICK_THRESHOLD {
		x += 1;
	}
	if state.stick_y < -STICK_THRESHOLD {
		y -= 1;
	}
	if state.stick_y > STICK_THRESHOLD {
		y += 1;
	}

	if x == 0 && y == 0 {
		return None;
	}
	if x.abs() >= y.abs() {
		Some(if x < 0 { Input::Left } else { Input::Right })
	} else {
		Some(if y < 0 { Input::Up } else { Input::Down })
	}
}
