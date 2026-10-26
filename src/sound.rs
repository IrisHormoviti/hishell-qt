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
//! than to play a backlog long after the action. Playback itself is slow to
//! start on this device (each `ca_context_play` opens the PCM), so a fast
//! scroll could fill the queue and keep ticking after the finger stopped.
//! Commands therefore carry their enqueue time: by the time the worker reaches
//! one that has waited too long, its moment has passed and it is dropped.
//! Transient sounds (scroll ticks) have a much shorter deadline than UI
//! feedback, because a scroll sound is only useful while the content moves.

use std::sync::Mutex;
use std::sync::mpsc::{SyncSender, TrySendError, sync_channel};
use std::time::{Duration, Instant};

use once_cell::sync::Lazy;
use qmetaobject::prelude::*;

use crate::kde_bridge;

/// How many sounds may wait for the audio device. A fast scroll can ask for
/// several per second; eight keeps the feedback current without a burst.
const QUEUE: usize = 8;

/// A queued sound older than this is no longer feedback; it is stale.
const MAX_AGE: Duration = Duration::from_millis(250);

/// Scroll ticks are only meaningful while the view is still moving.
const TRANSIENT_MAX_AGE: Duration = Duration::from_millis(120);

enum Command {
	Play(String, Instant, Duration),
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
						Command::Play(event_id, queued, max_age) => {
							// `ca_context_play` blocks while it opens the device,
							// so the queue can hold a sound that was already
							// superseded by the gesture that queued it.
							if queued.elapsed() <= max_age {
								kde_bridge::play_sound(&event_id);
							}
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
			submit(Command::Play(event_id, Instant::now(), MAX_AGE))
		}
	),

	/// Queue a sound that is only useful right now (a scroll tick). It is
	/// dropped once it has waited longer than a scroll sound can stay
	/// meaningful, so the end of a gesture is silent instead of a backlog.
	play_transient: qt_method!(
		fn play_transient(&self, event_id: String) -> bool {
			if !self.enabled {
				return false;
			}
			submit(Command::Play(event_id, Instant::now(), TRANSIENT_MAX_AGE))
		}
	),

	/// Set the event-sound volume, 0.0..=1.0.
	set_volume: qt_method!(
		fn set_volume(&self, factor: f64) {
			submit(Command::Volume(factor));
		}
	),
}
