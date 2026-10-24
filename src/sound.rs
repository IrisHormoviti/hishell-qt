//! Event sounds.
//!
//! ClamOS ships an XDG sound theme (the "3ds" theme in /usr/share/sounds). The
//! playback itself — theme lookup and ALSA output — lives in `kde_bridge`
//! through libcanberra; this type is the QML-facing half.
//!
//! QML asks for a sound by name, e.g. `sound.play("menu-popup")`. The names are
//! the XDG Sound Naming Specification names the ClamOS theme defines, see
//! ClamOS `tools/make-sound-theme.sh`, plus Hishell's own application sounds.
//!
//! Playback runs on its own thread. `ca_context_play()` is documented as
//! asynchronous, but the ALSA driver opens the output device inside the call:
//! when the device takes time to start (a speaker amplifier that is still
//! powering up, or one that fails and is retried by the kernel), the call
//! blocks for hundreds of milliseconds. On this device that was a visible
//! stutter on every cursor move, because the call came from the GUI thread.
//! The queue is bounded: sounds are feedback, and it is better to drop one
//! than to play a backlog long after the action.

use std::sync::Mutex;
use std::sync::mpsc::{SyncSender, TrySendError, sync_channel};

use once_cell::sync::Lazy;
use qmetaobject::prelude::*;

use crate::kde_bridge;

/// How many sounds may wait for the audio device. A fast scroll can ask for
/// several per second; eight keeps the feedback current without a burst.
const QUEUE: usize = 8;

enum Command {
	Play(String),
	Volume(f64),
}

static SENDER: Lazy<Mutex<Option<SyncSender<Command>>>> = Lazy::new(|| Mutex::new(None));

/// The queue's sending end, starting the playback thread on first use.
fn sender() -> Option<SyncSender<Command>> {
	let mut slot = SENDER.lock().ok()?;
	if slot.is_none() {
		let (tx, rx) = sync_channel(QUEUE);
		std::thread::Builder::new()
			.name("event-sounds".into())
			.spawn(move || {
				// The libcanberra context is created here and never touched
				// from another thread: it is not thread-safe.
				for command in rx {
					match command {
						Command::Play(event_id) => {
							kde_bridge::play_sound(&event_id);
						}
						Command::Volume(factor) => {
							kde_bridge::set_sound_volume(factor);
						}
					}
				}
			})
			.ok()?;
		*slot = Some(tx);
	}
	slot.clone()
}

fn submit(command: Command) -> bool {
	let Some(tx) = sender() else {
		return false;
	};
	match tx.try_send(command) {
		Ok(()) => true,
		// A full queue means the device is slower than the UI; dropping the
		// sound is what keeps the UI responsive.
		Err(TrySendError::Full(_)) | Err(TrySendError::Disconnected(_)) => false,
	}
}

#[derive(QObject, Default)]
pub struct Sound {
	base: qt_base_class!(trait QObject),
	window: qt_property!(QVariant),

	/// Whether event sounds are enabled (the global user setting).
	enabled: qt_property!(bool; NOTIFY enabled_changed),
	enabled_changed: qt_signal!(),

	/// Queue one event sound by name. Returns whether it was queued; an
	/// unknown name or a missing driver simply stays silent.
	play: qt_method!(
		fn play(&self, event_id: String) -> bool {
			if !self.enabled {
				return false;
			}
			submit(Command::Play(event_id))
		}
	),

	/// Set the event-sound volume, 0.0..=1.0.
	set_volume: qt_method!(
		fn set_volume(&self, factor: f64) {
			submit(Command::Volume(factor));
		}
	),
}
