use once_cell::sync::Lazy;
use std::fs::File;
use std::io::Read;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::{Duration, Instant};

const DEADZONE: i16 = 16000;
const REPEAT: Duration = Duration::from_millis(160);
const RECONNECT: Duration = Duration::from_secs(2);

const AXIS_X: usize = 0;
const AXIS_Y: usize = 1;
const AXIS_HAT_X: usize = 6;
const AXIS_HAT_Y: usize = 7;

const BUTTON_ACCEPT: usize = 0;
const BUTTON_CANCEL: usize = 1;
const BUTTON_DPAD_UP: usize = 11;
const BUTTON_DPAD_DOWN: usize = 12;
const BUTTON_DPAD_LEFT: usize = 13;
const BUTTON_DPAD_RIGHT: usize = 14;

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Input {
	Up,
	Down,
	Left,
	Right,
	Accept,
	Cancel,
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
		}
	}
}

#[derive(Default)]
struct State {
	axes: [i16; 16],
	axis_rest: [i16; 16],
	axis_seen: [bool; 16],
	buttons: [bool; 32],
}

static STATE: Lazy<Mutex<State>> = Lazy::new(|| Mutex::new(State::default()));
static QUEUE: Lazy<Mutex<Vec<Input>>> = Lazy::new(|| Mutex::new(Vec::new()));
static REPEAT_STATE: Lazy<Mutex<(Option<Input>, Instant)>> =
	Lazy::new(|| Mutex::new((None, Instant::now())));
static STARTED: AtomicBool = AtomicBool::new(false);

/// Starts the background reader for the first available joystick device.
/// Safe to call once; later calls are ignored.
pub fn init() {
	if STARTED.swap(true, Ordering::SeqCst) {
		return;
	}

	thread::spawn(|| {
		let mut announced = false;
		loop {
			if let Some((mut device, path)) = open_device() {
				if !announced {
					println!("gamepad: reading {}", path);
					announced = true;
				}
				if let Ok(mut state) = STATE.lock() {
					*state = State::default();
				}

				let mut buffer = [0u8; 8];
				while device.read_exact(&mut buffer).is_ok() {
					apply(&buffer);
				}
			}
			thread::sleep(RECONNECT);
		}
	});
}

/// Non-blocking read of the next navigation input. Held directions repeat
/// after a short delay; button presses are edge-triggered.
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

fn open_device() -> Option<(File, String)> {
	for index in 0..8 {
		let path = format!("/dev/input/js{}", index);
		if let Ok(file) = File::open(&path) {
			return Some((file, path));
		}
	}
	None
}

fn apply(buffer: &[u8; 8]) {
	let value = i16::from_ne_bytes([buffer[4], buffer[5]]);
	let kind = buffer[6];
	let number = buffer[7] as usize;
	let init = kind & 0x80 != 0;

	let mut state = match STATE.lock() {
		Ok(state) => state,
		Err(_) => return,
	};

	match kind & 0x7f {
		0x02 => {
			if number < state.axes.len() {
				if init || !state.axis_seen[number] {
					state.axis_rest[number] = value;
					state.axis_seen[number] = true;
				}
				state.axes[number] = value;
			}
		}
		0x01 => {
			if number < state.buttons.len() {
				state.buttons[number] = value != 0;
			}
			if !init && value != 0 {
				let input = match number {
					BUTTON_ACCEPT => Some(Input::Accept),
					BUTTON_CANCEL => Some(Input::Cancel),
					_ => None,
				};
				if let Some(input) = input
					&& let Ok(mut queue) = QUEUE.lock()
				{
					queue.push(input);
				}
			}
		}
		_ => {}
	}
}

fn held_direction() -> Option<Input> {
	let state = STATE.lock().ok()?;

	let mut x = axis_sign(state.axes[AXIS_X] - state.axis_rest[AXIS_X]);
	if x == 0 {
		x = axis_sign(state.axes[AXIS_HAT_X] - state.axis_rest[AXIS_HAT_X]);
	}
	let mut y = axis_sign(state.axes[AXIS_Y] - state.axis_rest[AXIS_Y]);
	if y == 0 {
		y = axis_sign(state.axes[AXIS_HAT_Y] - state.axis_rest[AXIS_HAT_Y]);
	}

	if state.buttons[BUTTON_DPAD_LEFT] {
		x -= 1;
	}
	if state.buttons[BUTTON_DPAD_RIGHT] {
		x += 1;
	}
	if state.buttons[BUTTON_DPAD_UP] {
		y -= 1;
	}
	if state.buttons[BUTTON_DPAD_DOWN] {
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

fn axis_sign(value: i16) -> i32 {
	if value > DEADZONE {
		1
	} else if value < -DEADZONE {
		-1
	} else {
		0
	}
}
