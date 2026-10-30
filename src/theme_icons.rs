//! Themed icon rendering for QML.
//!
//! `Hishell.Theme.Icon` resolves a theme icon name to a cached PNG by asking
//! this singleton. The shell already renders folder icons through
//! `kde_bridge::accent_icon`; this is the same path for the fixed icons the UI
//! names directly (search, arrows, emblems), so the QML never needs an icon
//! toolkit of its own.

use qmetaobject::prelude::*;
use qmetaobject::QSingletonInit;

/// A QML singleton (module `Hishell`, type `ThemeIcons`).
#[derive(QObject, Default)]
pub struct ThemeIcons {
	base: qt_base_class!(trait QObject),

	/// The theme backend the host asked for: "clamos" on a ClamOS device, "kde"
	/// on a desktop, or "" to probe. Set by the launcher as
	/// HISHELL_THEME_BACKEND, so a build does not have to guess from files.
	backend: qt_method!(
		fn backend(&self) -> String {
			std::env::var("HISHELL_THEME_BACKEND").unwrap_or_default()
		}
	),

	resolve: qt_method!(
		/// The cached PNG path for a theme icon name at `size` physical
		/// pixels, rendered on first use. A path or URL is returned as-is;
		/// `accent` and `text` are the colours the theme marks as accent
		/// (folders), as QML colour strings.
		fn resolve(&self, source: String, size: i32, accent: String, text: String) -> String {
			if source.is_empty() {
				return String::new();
			}
			if source.starts_with("file:")
				|| source.starts_with("qrc:")
				|| source.starts_with('/')
			{
				return source;
			}
			crate::kde_bridge::accent_icon(
				&source,
				size.max(1) as u32,
				parse_color(&accent),
				parse_color(&text),
			)
			.unwrap_or_default()
		}
	),
}

impl QSingletonInit for ThemeIcons {
	fn init(&mut self) {}
}

/// `#rgb`, `#rrggbb` or `#aarrggbb` to an RGB triple. Anything else renders
/// the icon without recolouring it.
fn parse_color(value: &str) -> (u8, u8, u8) {
	let hex = value.trim_start_matches('#');
	let digits: Vec<u8> = hex
		.chars()
		.filter_map(|c| c.to_digit(16).map(|d| d as u8))
		.collect();
	match digits.len() {
		3 => (digits[0] * 17, digits[1] * 17, digits[2] * 17),
		6 => (
			digits[0] * 16 + digits[1],
			digits[2] * 16 + digits[3],
			digits[4] * 16 + digits[5],
		),
		8 => (
			digits[2] * 16 + digits[3],
			digits[4] * 16 + digits[5],
			digits[6] * 16 + digits[7],
		),
		_ => (0, 0, 0),
	}
}
