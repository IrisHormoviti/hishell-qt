use crossbeam_channel::{
	Receiver as CReceiver, Sender as CSender, TryRecvError as CTryRecvError, unbounded,
};
use image::GenericImage;
use image::GenericImageView;
use image::RgbaImage;
use image::imageops::FilterType;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::OnceLock;
use std::sync::mpsc::{self, Sender};
use std::thread;

use md5;
use mime_guess::from_path;
use std::fs::File;
use zip::ZipArchive;

fn imagemagick_command() -> Option<String> {
	if Command::new("magick").arg("--version").output().is_ok() {
		return Some("magick".to_string());
	}
	if Command::new("convert").arg("--version").output().is_ok() {
		return Some("convert".to_string());
	}
	None
}
#[derive(Clone)]
struct SystemThumb {
	mime_globs: Vec<String>,
	exec: String,
}

static SYSTEM_THUMBNAILERS: OnceLock<Vec<SystemThumb>> = OnceLock::new();

pub struct Task {
	pub src: PathBuf,
	pub size: u32,
}

static SENDER: OnceLock<Sender<Task>> = OnceLock::new();
static RESULT_SENDER: OnceLock<CSender<(String, String)>> = OnceLock::new();
static RESULT_RECEIVER: OnceLock<CReceiver<(String, String)>> = OnceLock::new();

pub fn init() -> Sender<Task> {
	if let Some(s) = SENDER.get() {
		return s.clone();
	}

	let (tx, rx) = mpsc::channel::<Task>();
	let (res_tx, res_rx) = unbounded::<(String, String)>();

	// spawn a single worker thread that processes thumbnails sequentially
	let res_tx_clone = res_tx.clone();
	thread::spawn(move || {
		for task in rx.iter() {
			if let Ok(()) = generate_thumbnail(&task.src, task.size) {
				let dst = cache_path_for(&task.src, task.size);
				let _ = res_tx_clone.send((
					task.src.to_string_lossy().to_string(),
					dst.to_string_lossy().to_string(),
				));
			}
		}
	});

	SENDER.set(tx.clone()).ok();
	RESULT_SENDER.set(res_tx).ok();
	RESULT_RECEIVER.set(res_rx).ok();
	tx
}

/// Non-blocking drain of generated thumbnails. Returns pairs (src_path, dst_path).
pub fn drain_results() -> Vec<(String, String)> {
	if let Some(rx) = RESULT_RECEIVER.get() {
		let mut out = Vec::new();
		loop {
			match rx.try_recv() {
				Ok(pair) => out.push(pair),
				Err(CTryRecvError::Empty) => break,
				Err(CTryRecvError::Disconnected) => break,
			}
		}
		out
	} else {
		Vec::new()
	}
}

fn cache_dir_for_size(size: u32) -> PathBuf {
	let base = dirs::cache_dir().unwrap_or_else(|| PathBuf::from("/tmp"));
	// freedesktop spec uses 'normal' and 'large' directories
	let size_dir = if size <= 128 { "normal" } else { "large" };
	let dir = base.join("thumbnails").join(size_dir);
	let _ = fs::create_dir_all(&dir);
	dir
}

pub fn cache_path_for(src: &Path, size: u32) -> PathBuf {
	// hash of path + mtime
	// freedesktop thumbnail spec: filename is MD5 of the file URI
	let abs = std::fs::canonicalize(src).unwrap_or_else(|_| src.to_path_buf());
	let uri = format!("file://{}", abs.to_string_lossy());
	let digest = md5::compute(uri.as_bytes());
	let hex = format!("{:x}", digest);
	cache_dir_for_size(size).join(format!("{}.png", hex))
}

fn is_video_ext(ext: &str) -> bool {
	matches!(
		ext.to_lowercase().as_str(),
		"mp4" | "mkv" | "webm" | "avi" | "mov" | "mpeg" | "mpg"
	)
}

fn generate_thumbnail(src: &Path, size: u32) -> Result<(), String> {
	// safety: avoid processing very large files
	const MAX_BYTES: u64 = 10 * 1024 * 1024; // 10 MB
	if let Ok(meta) = std::fs::metadata(src) {
		if meta.len() > MAX_BYTES {
			return Err("file too large".to_string());
		}
	}
	let mime = from_path(src)
		.first_or_octet_stream()
		.essence_str()
		.to_string();
	// Quick path: for .kra (zip) files try to extract an embedded preview image
	if let Some(ext) = src.extension().and_then(|e| e.to_str()) {
		if ext.eq_ignore_ascii_case("kra") {
			let dst = cache_path_for(src, size);
			if extract_preview_from_kra(src, &dst, size).unwrap_or(false) {
				return Ok(());
			}
			// fall through to system thumbnailers if no embedded preview found
		}
	}
	// handle .desktop files: attempt to locate the referenced icon
	if let Some(ext) = src.extension().and_then(|e| e.to_str()) {
		if ext.eq_ignore_ascii_case("desktop") {
			let dst = cache_path_for(src, size);
			if try_desktop_icon(src, &dst, size).unwrap_or(false) {
				return Ok(());
			}
		}
	}
	// handle AppImage binaries (common suffix .AppImage)
	if let Some(fname) = src.file_name().and_then(|n| n.to_str()) {
		if fname.to_lowercase().ends_with(".appimage") {
			let dst = cache_path_for(src, size);
			if try_extract_icon_from_appimage(src, &dst, size).unwrap_or(false) {
				return Ok(());
			}
		}
	}
	// try system thumbnailers per freedesktop spec first
	if let Some(list) = load_system_thumbnailers() {
		let mime = from_path(src)
			.first_or_octet_stream()
			.essence_str()
			.to_string();

		let ext = src
			.extension()
			.and_then(|e| e.to_str())
			.unwrap_or("")
			.to_lowercase();
		for t in list.iter() {
			for mg in &t.mime_globs {
				if mg.ends_with("/*") {
					let prefix = &mg[..mg.len() - 2];
					if mime.starts_with(&(prefix.to_string() + "/")) {
						if run_system_thumb(t, src, size)? {
							return Ok(());
						}
					}
				} else if mg == &mime {
					if run_system_thumb(t, src, size)? {
						return Ok(());
					}
				} else {
					// heuristic: match by extension keywords if mime didn't match
					let mg_l = mg.to_lowercase();
					if !ext.is_empty() && (mg_l.contains(&ext) || mg_l.contains("krita")) {
						if run_system_thumb(t, src, size)? {
							return Ok(());
						}
					}
				}
			}
		}
	}

	// If this is a .kra file and system thumbnailers didn't produce a result,
	// try some known kra/openraster thumbnailer binaries directly as a fallback.
	if let Some(ext) = src.extension().and_then(|e| e.to_str()) {
		if ext.eq_ignore_ascii_case("kra") {
			let tools = [
				"gnome-kra-thumbnailer",
				"gnome-openraster-thumbnailer",
				"kra-thumbnailer",
			];
			for tool in &tools {
				if Command::new("which").arg(tool).output().is_ok() {
					let status = Command::new(tool)
						.arg("-s")
						.arg(size.to_string())
						.arg(src.as_os_str())
						.arg(&cache_path_for(src, size).as_os_str())
						.status();
					match status {
						Ok(st) => {
							let dst = cache_path_for(src, size);
							if st.success() && dst.exists() {
								return Ok(());
							}
						}
						Err(_) => {}
					}
				}
			}
		}
	}

	let dst = cache_path_for(src, size);
	if dst.exists() {
		return Ok(());
	}

	let ext = src.extension().and_then(|e| e.to_str()).unwrap_or("");
	// prefer ffmpegthumbnailer for videos
	if is_video_ext(ext) {
		if let Ok(status) = Command::new("ffmpegthumbnailer")
			.arg("-i")
			.arg(src.as_os_str())
			.arg("-o")
			.arg(&dst.as_os_str())
			.arg("-s")
			.arg(size.to_string())
			.status()
		{
			if status.success() {
				return Ok(());
			}
		}
	}

	// Only attempt ImageMagick on files that look like images (or known image-like extensions)
	let im_cmd = imagemagick_command();
	let ext = src
		.extension()
		.and_then(|e| e.to_str())
		.unwrap_or("")
		.to_lowercase();
	if let Some(im) = im_cmd {
		if mime.starts_with("image/") || ext == "svg" || ext == "xpm" {
			let status = Command::new(&im)
				.arg(src.as_os_str())
				.arg("-thumbnail")
				.arg(format!("{}x{}^", size, size))
				.arg("-gravity")
				.arg("center")
				.arg("-extent")
				.arg(format!("{}x{}", size, size))
				.arg(&dst.as_os_str())
				.status();

			if let Ok(status) = status {
				if status.success()
					&& dst.exists() && fs::metadata(&dst).map(|m| m.len() > 0).unwrap_or(false)
				{
					return Ok(());
				} else if dst.exists() {
					let _ = fs::remove_file(&dst);
				}
			}
		}
	}

	// as last resort, try the Rust `image` crate to resize simple raster images
	// only attempt this for known raster image extensions to avoid trying to
	// open archive formats like .kra as images.
	let image_exts = ["png", "jpg", "jpeg", "bmp", "gif", "webp", "avif", "tiff"];
	let ext = src
		.extension()
		.and_then(|e| e.to_str())
		.unwrap_or("")
		.to_lowercase();
	if image_exts.contains(&ext.as_str()) {
		match image::open(src) {
			Ok(img) => {
				// resize-to-fit and pad to square to avoid cropping
				let (w, h) = img.dimensions();
				let scale = f32::min(size as f32 / w as f32, size as f32 / h as f32);
				let new_w = (w as f32 * scale).max(1.0).round() as u32;
				let new_h = (h as f32 * scale).max(1.0).round() as u32;
				let resized = img.resize_exact(new_w, new_h, FilterType::Lanczos3);
				let mut canvas: RgbaImage = RgbaImage::new(size, size);
				let x = (size.saturating_sub(new_w)) / 2;
				let y = (size.saturating_sub(new_h)) / 2;
				let _ = canvas.copy_from(&resized.to_rgba8(), x, y);
				if let Err(e) = canvas.save(&dst) {
					return Err(format!("image save error: {}", e));
				}
				return Ok(());
			}
			Err(e) => return Err(format!("cannot open image: {}", e)),
		}
	}

	Err("no thumbnailer succeeded".to_string())
}

fn try_desktop_icon(src: &Path, dst: &Path, size: u32) -> Result<bool, String> {
	let s = std::fs::read_to_string(src).map_err(|e| format!("desktop read: {}", e))?;
	let mut icon_name: Option<String> = None;
	for line in s.lines() {
		let l = line.trim();
		if l.starts_with("Icon=") {
			icon_name = Some(l[5..].trim().to_string());
			break;
		}
	}
	let icon_name = match icon_name {
		Some(i) => i,
		None => return Ok(false),
	};

	// If the icon is an absolute path or relative path that exists, use it
	let try_paths = || -> Option<PathBuf> {
		if icon_name.contains('/') {
			// relative or absolute path
			let p = if icon_name.starts_with('/') {
				PathBuf::from(&icon_name)
			} else {
				src.parent()
					.unwrap_or_else(|| Path::new("."))
					.join(&icon_name)
			};
			if p.exists() {
				return Some(p);
			}
		}

		// search common icon locations by name
		let candidates = ["png", "svg", "xpm", "jpg", "jpeg"];
		// check /usr/share/pixmaps
		let pix = PathBuf::from("/usr/share/pixmaps").join(format!("{}.png", icon_name));
		if pix.exists() {
			return Some(pix);
		}

		// search /usr/share/icons/hicolor/*/apps/{name}.{ext}
		let icons_base = PathBuf::from("/usr/share/icons/hicolor");
		if icons_base.exists() {
			if let Ok(entries) = fs::read_dir(&icons_base) {
				for e in entries.flatten() {
					let sub = e.path();
					let apps_dir = sub.join("apps");
					for ext in &candidates {
						let p = apps_dir.join(format!("{}.{}", icon_name, ext));
						if p.exists() {
							return Some(p);
						}
					}
				}
			}
		}

		// search /usr/share/icons/*/*/apps/
		let icons_root = PathBuf::from("/usr/share/icons");
		if icons_root.exists() {
			if let Ok(entries) = fs::read_dir(&icons_root) {
				for e in entries.flatten() {
					let sub = e.path();
					// try a couple of common subdirs
					let apps_dir = sub.join("48x48/apps");
					for ext in &candidates {
						let p = apps_dir.join(format!("{}.{}", icon_name, ext));
						if p.exists() {
							return Some(p);
						}
					}
				}
			}
		}

		// local icons
		if let Some(home) = dirs::home_dir() {
			let local = home.join(".local/share/icons");
			if local.exists() {
				if let Ok(entries) = fs::read_dir(&local) {
					for e in entries.flatten() {
						let sub = e.path();
						let apps_dir = sub.join("apps");
						for ext in &candidates {
							let p = apps_dir.join(format!("{}.{}", icon_name, ext));
							if p.exists() {
								return Some(p);
							}
						}
					}
				}
			}
		}

		None
	}();

	if let Some(icon_path) = try_paths {
		return run_icon_to_dst(&icon_path, dst, size);
	}

	Ok(false)
}

fn try_extract_icon_from_appimage(src: &Path, dst: &Path, size: u32) -> Result<bool, String> {
	// require bsdtar to inspect AppImage
	if Command::new("bsdtar").arg("--version").output().is_err() {
		return Ok(false);
	}

	let out = Command::new("bsdtar")
		.arg("-tf")
		.arg(src.as_os_str())
		.output();
	let output = match out {
		Ok(o) => o,
		Err(_) => return Ok(false),
	};
	if !output.status.success() {
		return Ok(false);
	}
	let list = String::from_utf8_lossy(&output.stdout);
	// search for reasonable icon file paths
	let mut candidate: Option<String> = None;
	for line in list.lines() {
		let l = line.trim();
		let ll = l.to_lowercase();
		if ll.ends_with(".png")
			|| ll.ends_with(".svg")
			|| ll.ends_with(".xpm")
			|| ll.ends_with(".jpg")
			|| ll.ends_with(".jpeg")
		{
			if ll.contains("/icons/")
				|| ll.contains("/pixmaps/")
				|| ll.contains("/apps/")
				|| ll.contains("icon")
			{
				// prefer larger sizes if indicated
				if candidate.is_none()
					|| ll.contains("128")
					|| ll.contains("256")
					|| ll.contains("512")
				{
					candidate = Some(l.to_string());
					if ll.contains("256") || ll.contains("512") {
						break;
					}
				}
			}
		}
	}

	let candidate = match candidate {
		Some(c) => c,
		None => return Ok(false),
	};

	// extract the candidate entry and pipe to convert if available, otherwise write tmp and use image crate
	let dst_str = dst.to_string_lossy().to_string();
	if imagemagick_command().is_some() {
		// use bsdtar to extract to stdout and convert from stdin
		let im = imagemagick_command().unwrap_or_else(|| "convert".to_string());
		let cmd = format!(
			"bsdtar -xOf '{}' '{}' | {im} png:- -thumbnail {s}x{s}^ -gravity center -extent {s}x{s} '{dst}'",
			src.to_string_lossy(),
			candidate,
			im = im,
			s = size,
			dst = dst_str
		);
		let status = Command::new("sh").arg("-c").arg(cmd).status();
		if let Ok(st) = status {
			if st.success() && dst.exists() {
				return Ok(true);
			}
		}
	}

	// fallback: extract to temp file then load via image crate
	let tmp = cache_dir_for_size(size).join("appimage_icon_tmp");
	let status = Command::new("bsdtar")
		.arg("-xOf")
		.arg(src.as_os_str())
		.arg(candidate)
		.output();
	if let Ok(output) = status {
		if output.status.success() {
			if std::fs::write(&tmp, &output.stdout).is_ok() {
				let res = run_icon_to_dst(&tmp, dst, size);
				let _ = std::fs::remove_file(&tmp);
				return res;
			}
		}
	}

	Ok(false)
}

fn run_icon_to_dst(icon_path: &Path, dst: &Path, size: u32) -> Result<bool, String> {
	if let Some(im) = imagemagick_command() {
		let status = Command::new(&im)
			.arg(icon_path.as_os_str())
			.arg("-thumbnail")
			.arg(format!("{}x{}^", size, size))
			.arg("-gravity")
			.arg("center")
			.arg("-extent")
			.arg(format!("{}x{}", size, size))
			.arg(dst.as_os_str())
			.status();
		if let Ok(st) = status {
			if st.success() && dst.exists() {
				return Ok(true);
			}
		}
	}

	// fallback to Rust image crate for raster formats
	let ext = icon_path
		.extension()
		.and_then(|e| e.to_str())
		.unwrap_or("")
		.to_lowercase();
	let raster_exts = ["png", "jpg", "jpeg", "bmp", "webp", "gif", "tiff", "avif"];
	if raster_exts.contains(&ext.as_str()) {
		if let Ok(img) = image::open(icon_path) {
			let (w, h) = img.dimensions();
			let scale = f32::min(size as f32 / w as f32, size as f32 / h as f32);
			let new_w = (w as f32 * scale).max(1.0).round() as u32;
			let new_h = (h as f32 * scale).max(1.0).round() as u32;
			let resized = img.resize_exact(new_w, new_h, FilterType::Lanczos3);
			let mut canvas: RgbaImage = RgbaImage::new(size, size);
			let x = (size.saturating_sub(new_w)) / 2;
			let y = (size.saturating_sub(new_h)) / 2;
			let _ = canvas.copy_from(&resized.to_rgba8(), x, y);
			if let Err(e) = canvas.save(dst) {
				return Err(format!("save icon: {}", e));
			}
			return Ok(true);
		}
	}

	Ok(false)
}

fn run_system_thumb(t: &SystemThumb, src: &Path, size: u32) -> Result<bool, String> {
	// build command by replacing known placeholders and run via shell
	let src_path = src.to_string_lossy().to_string();
	let uri = format!("file://{}", src_path);
	let dst = cache_path_for(src, size);

	let esc = |s: &str| {
		// simple single-quote shell escape
		let mut out = String::from("'");
		for c in s.chars() {
			if c == '\'' {
				out.push_str("'\\''");
			} else {
				out.push(c);
			}
		}
		out.push('\'');
		out
	};

	let mut cmd = t.exec.clone();
	cmd = cmd.replace("%i", &esc(&src_path));
	cmd = cmd.replace("%u", &esc(&uri));
	cmd = cmd.replace("%o", &esc(&dst.to_string_lossy()));
	cmd = cmd.replace("%s", &size.to_string());

	// run via shell and capture output for better diagnostics
	match Command::new("sh").arg("-c").arg(&cmd).output() {
		Ok(output) => {
			let status = output.status;
			if status.success() && dst.exists() {
				return Ok(true);
			}
		}
		Err(_) => {}
	}

	Ok(false)
}

fn extract_preview_from_kra(src: &Path, dst: &Path, size: u32) -> Result<bool, String> {
	let file = File::open(src).map_err(|e| format!("open zip error: {}", e))?;
	let mut archive = ZipArchive::new(file).map_err(|e| format!("zip read error: {}", e))?;

	let total = archive.len();

	for i in 0..(total.min(20)) {
		let _ = archive.by_index(i);
	}

	// common preview names
	let candidates = [
		"preview.png",
		"Preview.png",
		"mergedimage.png",
		"mergedimage.jpg",
		"Thumbnails/thumbnail.png",
		"Thumbnails/thumbnail.jpg",
	];
	for name in candidates.iter() {
		if let Ok(mut f) = archive.by_name(name) {
			let mut buf: Vec<u8> = Vec::new();
			use std::io::Read;
			if let Err(_) = f.read_to_end(&mut buf) {
				continue;
			}
			match image::load_from_memory(&buf) {
				Ok(img0) => {
					// resize-to-fit and pad to square to avoid cropping
					let (w, h) = img0.dimensions();
					let scale = f32::min(size as f32 / w as f32, size as f32 / h as f32);
					let new_w = (w as f32 * scale).max(1.0).round() as u32;
					let new_h = (h as f32 * scale).max(1.0).round() as u32;
					let resized = img0.resize_exact(new_w, new_h, FilterType::Lanczos3);
					let mut canvas: RgbaImage = RgbaImage::new(size, size);
					let x = (size.saturating_sub(new_w)) / 2;
					let y = (size.saturating_sub(new_h)) / 2;
					let _ = canvas.copy_from(&resized.to_rgba8(), x, y);
					if let Err(_) = canvas.save(dst) {
						continue;
					}
					return Ok(true);
				}
				Err(_) => continue,
			}
		}
	}

	// fallback: try any png/jpg in archive
	for i in 0..archive.len() {
		if let Ok(mut f) = archive.by_index(i) {
			let name = f.name().to_string();
			if name.to_lowercase().ends_with(".png")
				|| name.to_lowercase().ends_with(".jpg")
				|| name.to_lowercase().ends_with(".jpeg")
			{
				let mut buf: Vec<u8> = Vec::new();
				use std::io::Read;
				if let Err(_) = f.read_to_end(&mut buf) {
					continue;
				}
				if let Ok(img) = image::load_from_memory(&buf) {
					// resize-to-fit and pad to square to avoid cropping
					let (w, h) = img.dimensions();
					let scale = f32::min(size as f32 / w as f32, size as f32 / h as f32);
					let new_w = (w as f32 * scale).max(1.0).round() as u32;
					let new_h = (h as f32 * scale).max(1.0).round() as u32;
					let resized = img.resize_exact(new_w, new_h, FilterType::Lanczos3);
					let mut canvas: RgbaImage = RgbaImage::new(size, size);
					let x = (size.saturating_sub(new_w)) / 2;
					let y = (size.saturating_sub(new_h)) / 2;
					let _ = canvas.copy_from(&resized.to_rgba8(), x, y);
					if let Err(_) = canvas.save(dst) {
						continue;
					}
					return Ok(true);
				}
			}
		}
	}

	Ok(false)
}

fn load_system_thumbnailers() -> Option<&'static Vec<SystemThumb>> {
	if let Some(list) = SYSTEM_THUMBNAILERS.get() {
		return Some(list);
	}

	let mut out: Vec<SystemThumb> = Vec::new();
	let dirs = vec![
		std::path::PathBuf::from("/usr/share/thumbnailers"),
		dirs::home_dir()
			.map(|d| d.join(".local/share/thumbnailers"))
			.unwrap_or_default(),
	];

	for dir in dirs.into_iter() {
		if dir.exists() {
			if let Ok(entries) = fs::read_dir(dir) {
				for e in entries.flatten() {
					if let Some(ext) = e.path().extension().and_then(|s| s.to_str()) {
						if ext == "thumbnailer" {
							if let Ok(s) = fs::read_to_string(e.path()) {
								let mut exec_line = None;
								let mut mimes: Vec<String> = Vec::new();
								for line in s.lines() {
									let l = line.trim();
									if l.starts_with("Exec=") {
										exec_line = Some(l[5..].to_string());
									} else if l.starts_with("MimeType=") {
										let rest = &l[9..];
										for m in rest.split(';') {
											let mm = m.trim();
											if !mm.is_empty() {
												mimes.push(mm.to_string());
											}
										}
									}
								}
								if let Some(exec) = exec_line {
									if !mimes.is_empty() {
										out.push(SystemThumb {
											mime_globs: mimes,
											exec,
										});
									}
								}
							}
						}
					}
				}
			}
		}
	}

	SYSTEM_THUMBNAILERS.set(out).ok();
	SYSTEM_THUMBNAILERS.get()
}

pub fn enqueue(src: &Path, size: u32) {
	let sender = init();
	let _ = sender.send(Task {
		src: src.to_path_buf(),
		size,
	});
}

pub fn thumbnail_uri_if_exists(src: &Path, size: u32) -> Option<String> {
	let p = cache_path_for(src, size);
	if p.exists() {
		Some(format!("file://{}", p.to_string_lossy()))
	} else {
		None
	}
}
