//! Event sounds.
//!
//! ClamOS ships an XDG sound theme (the "3ds" theme in /usr/share/sounds). The
//! playback itself — theme lookup and PulseAudio output — lives in
//! `kde_bridge` through libcanberra; this type is the QML-facing half.
//!
//! QML asks for a sound by name, e.g. `sound.play("menu-popup")`. The names are
//! the XDG Sound Naming Specification names the ClamOS theme defines (see
//! ClamOS `tools/make-sound-theme.sh`), plus Hishell's own application sounds.

use qmetaobject::prelude::*;

use crate::kde_bridge;

#[derive(QObject, Default)]
pub struct Sound {
	base: qt_base_class!(trait QObject),
	window: qt_property!(QVariant),

	/// Whether event sounds are enabled (the global user setting).
	enabled: qt_property!(bool; NOTIFY enabled_changed),
	enabled_changed: qt_signal!(),

	/// Play one event sound by name. Returns whether it started; an unknown name
	/// or a missing driver simply stays silent.
	play: qt_method!(
		fn play(&self, event_id: String) -> bool {
			if !self.enabled {
				return false;
			}
			kde_bridge::play_sound(&event_id)
		}
	),

	/// Set the event-sound volume, 0.0..=1.0.
	set_volume: qt_method!(
		fn set_volume(&self, factor: f64) {
			kde_bridge::set_sound_volume(factor);
		}
	),
}
