use gilrs::{Axis, Button, EventType, Gilrs};
use once_cell::sync::Lazy;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::{Duration, Instant};

const REPEAT: Duration = Duration::from_millis(160);
const STICK_THRESHOLD: f32 = 0.35;

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
static REPEAT_STATE: Lazy<Mutex<(Option<Input>, Instant)>> =
	Lazy::new(|| Mutex::new((None, Instant::now())));
static STARTED: AtomicBool = AtomicBool::new(false);

/// Queues an input that came from somewhere other than the gamepad, such as
/// the keyboard menu key. It is dispatched through the same routing as the
/// controller so that both behave identically.
pub fn push(input: Input) {
	if let Ok(mut queue) = QUEUE.lock() {
		queue.push(input);
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
			if let Some(event) = gilrs.next_event_blocking(Some(Duration::from_millis(200)))
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
			if repeat.0 == Some(input) && now.duration_since(repeat.1) < REPEAT {
				return None;
			}
			*repeat = (Some(input), now);
			Some(input)
		}
		None => {
			repeat.0 = None;
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
