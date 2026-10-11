//! AppImages append a SquashFS image with a desktop entry and an icon at its
//! root; both are read directly and exposed the same way `.desktop` files and
//! `.directory` folders are.

use crate::desktop_entry::DesktopEntry;
use crate::squashfs::Squashfs;
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{LazyLock, Mutex};
use std::time::UNIX_EPOCH;

const MAX_ENTRY_BYTES: u64 = 512 * 1024;
const MAX_ICON_BYTES: usize = 4 * 1024 * 1024;
const ICON_EXTENSIONS: &[&str] = &["png", "svg", "xpm", "jpg", "jpeg", "webp"];

struct CachedEntry {
	mtime: i64,
	size: u64,
	entry: Option<DesktopEntry>,
}

static ENTRY_CACHE: LazyLock<Mutex<HashMap<PathBuf, CachedEntry>>> =
	LazyLock::new(|| Mutex::new(HashMap::new()));

pub fn is_appimage(path: &Path) -> bool {
	path.extension()
		.and_then(|ext| ext.to_str())
		.is_some_and(|ext| ext.eq_ignore_ascii_case("appimage"))
}

/// The desktop entry embedded in an AppImage, cached per path until it changes.
pub fn desktop_entry(path: &Path) -> Option<DesktopEntry> {
	if !is_appimage(path) {
		return None;
	}
	let (mtime, size) = stat_key(path)?;

	if let Some(cached) = ENTRY_CACHE.lock().unwrap().get(path)
		&& cached.mtime == mtime
		&& cached.size == size
	{
		return cached.entry.clone();
	}

	let entry = extract_entry(path);
	ENTRY_CACHE.lock().unwrap().insert(
		path.to_path_buf(),
		CachedEntry {
			mtime,
			size,
			entry: entry.clone(),
		},
	);
	entry
}

/// Extracts the AppImage's icon into the cache directory and returns its path.
pub fn icon(path: &Path) -> Option<PathBuf> {
	if !is_appimage(path) {
		return None;
	}
	let (mtime, size) = stat_key(path)?;
	let entry = desktop_entry(path);

	// An icon that points at a real file on the host is used as is.
	if let Some(icon) = entry.as_ref().and_then(|entry| entry.icon.as_deref()) {
		let icon = icon.trim();
		if icon.starts_with('/') && Path::new(icon).is_file() {
			return Some(PathBuf::from(icon));
		}
	}

	let cache_dir = dirs::cache_dir()?.join("hishell").join("appimage");
	let key = format!(
		"{:x}",
		md5::compute(format!("{}|{}|{}", path.display(), mtime, size))
	);
	if let Some(cached) = cached_icon(&cache_dir, &key) {
		return Some(cached);
	}

	let mut image = Squashfs::open(path)?;
	let (extension, bytes) = extract_icon(&mut image, entry.as_ref())?;

	fs::create_dir_all(&cache_dir).ok()?;
	let target = cache_dir.join(format!("{key}.{extension}"));
	let tmp = cache_dir.join(format!(".{key}.tmp"));
	fs::write(&tmp, &bytes).ok()?;
	fs::rename(&tmp, &target).ok()?;
	remove_stale_icons(&cache_dir, &key, &target);

	Some(target)
}

fn stat_key(path: &Path) -> Option<(i64, u64)> {
	let meta = fs::metadata(path).ok()?;
	let mtime = meta
		.modified()
		.ok()
		.and_then(|time| time.duration_since(UNIX_EPOCH).ok())
		.map(|duration| duration.as_secs() as i64)
		.unwrap_or(0);
	Some((mtime, meta.len()))
}

fn extract_entry(path: &Path) -> Option<DesktopEntry> {
	let mut image = Squashfs::open(path)?;
	let root = image.root_inode();
	let name = image
		.read_dir(root)?
		.into_iter()
		.find(|entry| entry.name.to_lowercase().ends_with(".desktop"))?
		.name;

	let inode = image.lookup_path(&name)?;
	let bytes = image.read_file(&inode)?;
	if bytes.len() as u64 > MAX_ENTRY_BYTES {
		return None;
	}

	Some(crate::desktop_entry::parse(&String::from_utf8_lossy(
		&bytes,
	)))
}

fn extract_icon(image: &mut Squashfs, entry: Option<&DesktopEntry>) -> Option<(String, Vec<u8>)> {
	let mut candidates = Vec::new();
	if let Some(icon) = entry.and_then(|entry| entry.icon.as_deref()) {
		let icon = icon.trim();
		if icon.starts_with('/') {
			// Absolute paths refer to a file inside the image.
			candidates.push(icon.trim_start_matches('/').to_string());
		} else if icon.contains('/') {
			candidates.push(icon.trim_start_matches("./").to_string());
		} else {
			for extension in ICON_EXTENSIONS {
				candidates.push(format!("{icon}.{extension}"));
			}
			candidates.push(icon.to_string());
		}
	}
	candidates.push(".DirIcon".to_string());

	for name in candidates {
		let Some(inode) = image.lookup_path(&name) else {
			continue;
		};
		let Some(bytes) = image.read_file(&inode) else {
			continue;
		};
		if bytes.len() > MAX_ICON_BYTES {
			continue;
		}
		if let Some(extension) = sniff_image(&bytes) {
			return Some((extension.to_string(), bytes));
		}
	}

	None
}

fn cached_icon(cache_dir: &Path, key: &str) -> Option<PathBuf> {
	let prefix = format!("{key}.");
	fs::read_dir(cache_dir)
		.ok()?
		.flatten()
		.map(|entry| entry.path())
		.find(|path| {
			path.file_name()
				.and_then(|name| name.to_str())
				.is_some_and(|name| name.starts_with(&prefix))
		})
}

fn remove_stale_icons(cache_dir: &Path, key: &str, keep: &Path) {
	let prefix = format!("{key}.");
	let Ok(entries) = fs::read_dir(cache_dir) else {
		return;
	};
	for entry in entries.flatten() {
		let path = entry.path();
		if path == keep {
			continue;
		}
		let stale = path
			.file_name()
			.and_then(|name| name.to_str())
			.is_some_and(|name| name.starts_with(&prefix));
		if stale {
			let _ = fs::remove_file(path);
		}
	}
}

/// Recognizes the image formats an AppImage icon can be stored in.
fn sniff_image(bytes: &[u8]) -> Option<&'static str> {
	if bytes.starts_with(&[0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a]) {
		return Some("png");
	}
	if bytes.starts_with(&[0xff, 0xd8, 0xff]) {
		return Some("jpg");
	}
	if bytes.starts_with(b"GIF87a") || bytes.starts_with(b"GIF89a") {
		return Some("gif");
	}
	if bytes.len() >= 12 && &bytes[0..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
		return Some("webp");
	}
	if bytes.starts_with(b"BM") {
		return Some("bmp");
	}
	if bytes.starts_with(&[0x00, 0x00, 0x01, 0x00]) {
		return Some("ico");
	}
	if bytes.starts_with(b"/* XPM */") {
		return Some("xpm");
	}

	let head = String::from_utf8_lossy(&bytes[..bytes.len().min(1024)]);
	if head.contains("<svg") {
		return Some("svg");
	}

	None
}

#[cfg(test)]
mod tests {
	use super::{desktop_entry, icon, is_appimage};
	use std::path::Path;

	#[test]
	fn recognizes_appimage_paths() {
		assert!(is_appimage(Path::new("/tmp/app.AppImage")));
		assert!(is_appimage(Path::new("/tmp/app.appimage")));
		assert!(!is_appimage(Path::new("/tmp/app.desktop")));
		assert!(!is_appimage(Path::new("/tmp/appimage")));
	}

	#[test]
	fn reads_embedded_entry_and_icon() {
		let path = Path::new("/home/iris/Applications/aseprite.appimage");
		if !path.exists() {
			return;
		}

		let entry = desktop_entry(path).expect("embedded desktop entry");
		assert_eq!(entry.name.as_deref(), Some("Aseprite"));
		assert_eq!(entry.icon.as_deref(), Some("aseprite"));

		let icon = icon(path).expect("embedded icon");
		assert!(icon.exists());
		assert_eq!(
			std::fs::read(&icon).unwrap()[..8],
			[0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a]
		);
	}
}
