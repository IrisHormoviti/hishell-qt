use image::GenericImageView;
use image::RgbaImage;
use image::imageops::FilterType;
use md5;
use mime_guess::from_path;
use std::collections::{HashMap, HashSet, VecDeque};
use std::fs;
use std::fs::File;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, ExitStatus, Output, Stdio};
use std::sync::{Condvar, Mutex, OnceLock};
use std::thread;
use std::time::{Duration, Instant, UNIX_EPOCH};
use zip::ZipArchive;

/// Thumbnails are generated and cached at the freedesktop tier sizes, like
/// Dolphin does, so a cached file can be shared with KDE applications.
const TIERS: [u32; 4] = [128, 256, 512, 1024];

/// Upper bound for decoding an image in-process; larger files fall back to the
/// external thumbnailers, which stream and seek instead of loading it all.
const MAX_DECODE_BYTES: u64 = 64 * 1024 * 1024;

/// Concurrent thumbnail workers, matching KIO's cached-thumbnail pool size.
const MAX_WORKERS: usize = 4;

/// Pending jobs kept per folder; a fast scroll past a long folder drops the
/// oldest requests instead of growing the queue without bound.
const MAX_PENDING_PER_FOLDER: usize = 256;

/// A thumbnailer that never finishes would otherwise hold a worker forever.
const COMMAND_TIMEOUT: Duration = Duration::from_secs(15);

const IMAGE_EXTS: &[&str] = &[
	"png", "jpg", "jpeg", "jpe", "bmp", "gif", "webp", "avif", "tif", "tiff", "svg", "svgz", "xpm",
	"ico", "icns", "jxl", "heif", "heic", "kra", "ora", "appimage",
];

const VIDEO_EXTS: &[&str] = &[
	"mp4", "m4v", "mkv", "webm", "avi", "mov", "mpeg", "mpg", "flv", "wmv", "3gp", "ogv", "m2ts",
	"ts",
];

fn ext_lower(path: &Path) -> String {
	path.extension()
		.and_then(|e| e.to_str())
		.unwrap_or("")
		.to_lowercase()
}

fn is_video_ext(ext: &str) -> bool {
	VIDEO_EXTS.contains(&ext)
}

/// The cache tier a requested pixel size maps to (normal/large/x-large/xx-large).
fn bucket_size(size: u32) -> u32 {
	for tier in TIERS {
		if size <= tier {
			return tier;
		}
	}
	TIERS[TIERS.len() - 1]
}

fn tier_name(bucket: u32) -> &'static str {
	match bucket {
		128 => "normal",
		256 => "large",
		512 => "x-large",
		_ => "xx-large",
	}
}

fn cache_root() -> PathBuf {
	dirs::cache_dir()
		.unwrap_or_else(|| PathBuf::from("/tmp"))
		.join("thumbnails")
}

/// The percent-encoded file URI the freedesktop spec hashes for the cache name.
fn file_uri(src: &Path) -> String {
	let path = src.to_string_lossy();
	if let Some(uri) = crate::kde_bridge::file_uri(&path) {
		return uri;
	}
	let abs = std::fs::canonicalize(src).unwrap_or_else(|_| src.to_path_buf());
	format!("file://{}", abs.to_string_lossy())
}

pub fn cache_path_for(src: &Path, size: u32) -> PathBuf {
	let bucket = bucket_size(size);
	let digest = md5::compute(file_uri(src).as_bytes());
	cache_root()
		.join(tier_name(bucket))
		.join(format!("{:x}.png", digest))
}

fn source_stat(src: &Path) -> Option<(i64, u64)> {
	let meta = fs::metadata(src).ok()?;
	let mtime = meta
		.modified()
		.ok()
		.and_then(|t| t.duration_since(UNIX_EPOCH).ok())
		.map(|d| d.as_secs() as i64)
		.unwrap_or(0);
	Some((mtime, meta.len()))
}

struct ThumbMeta {
	uri: String,
	mtime: i64,
	size: Option<u64>,
}

/// Reads the `Thumb::*` text chunks from a cached thumbnail, checking that the
/// PNG header is intact but never decoding the image data.
fn read_thumb_meta(path: &Path) -> Option<ThumbMeta> {
	let file = std::io::BufReader::new(File::open(path).ok()?);
	let mut decoder = png::Decoder::new(file);
	decoder.set_ignore_text_chunk(false);
	let reader = decoder.read_info().ok()?;
	let info = reader.info();

	let mut uri = None;
	let mut mtime = None;
	let mut size = None;
	let mut take = |keyword: &str, text: &str| match keyword {
		"Thumb::URI" => uri = Some(text.to_string()),
		"Thumb::MTime" => mtime = text.trim().parse::<i64>().ok(),
		"Thumb::Size" => size = text.trim().parse::<u64>().ok(),
		_ => {}
	};

	for chunk in &info.uncompressed_latin1_text {
		take(&chunk.keyword, &chunk.text);
	}
	for chunk in &info.compressed_latin1_text {
		if let Ok(text) = chunk.get_text() {
			take(chunk.keyword.as_str(), text.as_str());
		}
	}
	for chunk in &info.utf8_text {
		if let Ok(text) = chunk.get_text() {
			take(chunk.keyword.as_str(), text.as_str());
		}
	}

	Some(ThumbMeta {
		uri: uri?,
		mtime: mtime?,
		size,
	})
}

/// URI of the cached thumbnail for `src`, when it is present and still matches
/// the file's URI, modification time and size.
fn cached_uri(src: &Path, size: u32) -> Option<String> {
	let path = cache_path_for(src, size);
	let meta = read_thumb_meta(&path)?;
	if meta.uri != file_uri(src) {
		return None;
	}
	let (mtime, file_size) = source_stat(src)?;
	if meta.mtime != mtime {
		return None;
	}
	if let Some(cached_size) = meta.size {
		if cached_size != file_size {
			return None;
		}
	}
	Some(format!("file://{}", path.to_string_lossy()))
}

#[derive(Clone)]
struct SystemThumb {
	mime_globs: Vec<String>,
	exec: String,
}

static SYSTEM_THUMBNAILERS: OnceLock<Vec<SystemThumb>> = OnceLock::new();
static IMAGEMAGICK: OnceLock<Option<String>> = OnceLock::new();

fn load_system_thumbnailers() -> &'static Vec<SystemThumb> {
	SYSTEM_THUMBNAILERS.get_or_init(|| {
		let mut out: Vec<SystemThumb> = Vec::new();
		let dirs = [
			PathBuf::from("/usr/share/thumbnailers"),
			dirs::home_dir()
				.map(|d| d.join(".local/share/thumbnailers"))
				.unwrap_or_default(),
		];

		for dir in dirs {
			let Ok(entries) = fs::read_dir(dir) else {
				continue;
			};
			for e in entries.flatten() {
				if e.path().extension().and_then(|s| s.to_str()) != Some("thumbnailer") {
					continue;
				}
				let Ok(contents) = fs::read_to_string(e.path()) else {
					continue;
				};
				let mut exec_line = None;
				let mut mimes: Vec<String> = Vec::new();
				for line in contents.lines() {
					let line = line.trim();
					if let Some(rest) = line.strip_prefix("Exec=") {
						exec_line = Some(rest.to_string());
					} else if let Some(rest) = line.strip_prefix("MimeType=") {
						for m in rest.split(';') {
							let m = m.trim();
							if !m.is_empty() {
								mimes.push(m.to_string());
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
		out
	})
}

fn imagemagick_command() -> Option<&'static str> {
	IMAGEMAGICK
		.get_or_init(|| {
			if Command::new("magick").arg("--version").output().is_ok() {
				Some("magick".to_string())
			} else if Command::new("convert").arg("--version").output().is_ok() {
				Some("convert".to_string())
			} else {
				None
			}
		})
		.as_deref()
}

/// Whether an item is a candidate for a thumbnail: a known image or video
/// extension, or a MIME type one of the installed thumbnailers handles.
fn is_thumbnailable(src: &Path) -> bool {
	let ext = ext_lower(src);
	if IMAGE_EXTS.contains(&ext.as_str()) || is_video_ext(&ext) {
		return true;
	}
	let mime = from_path(src)
		.first_or_octet_stream()
		.essence_str()
		.to_string();
	for thumb in load_system_thumbnailers() {
		for glob in &thumb.mime_globs {
			if glob == &mime {
				return true;
			}
			if let Some(prefix) = glob.strip_suffix("/*") {
				if mime.starts_with(&format!("{prefix}/")) {
					return true;
				}
			}
		}
	}
	false
}

// ── Job queue ───────────────────────────────────────────────────────────────

#[derive(Clone)]
struct Job {
	src: PathBuf,
	folder: PathBuf,
	size: u32,
	epoch: u64,
}

#[derive(Default)]
struct Pending {
	queue: VecDeque<Job>,
	queued: HashSet<(PathBuf, u32)>,
	folder_counts: HashMap<PathBuf, usize>,
	epochs: HashMap<PathBuf, u64>,
}

struct ThumbState {
	pending: Mutex<Pending>,
	cond: Condvar,
	results: Mutex<HashMap<String, (String, Instant)>>,
}

static STATE: OnceLock<ThumbState> = OnceLock::new();

fn state() -> &'static ThumbState {
	STATE.get_or_init(|| {
		let st = ThumbState {
			pending: Mutex::new(Pending::default()),
			cond: Condvar::new(),
			results: Mutex::new(HashMap::new()),
		};
		let workers = thread::available_parallelism()
			.map(|n| n.get())
			.unwrap_or(2)
			.min(MAX_WORKERS);
		for _ in 0..workers {
			thread::spawn(worker_loop);
		}
		st
	})
}

fn next_job(st: &'static ThumbState) -> Job {
	let mut pending = st.pending.lock().unwrap();
	loop {
		while let Some(job) = pending.queue.pop_front() {
			pending.queued.remove(&(job.src.clone(), job.size));
			if let Some(count) = pending.folder_counts.get_mut(&job.folder) {
				*count = count.saturating_sub(1);
			}
			// Jobs queued before the folder was left are stale: the cache may
			// still end up filled, but nothing needs to wait for them.
			if pending.epochs.get(&job.folder).copied().unwrap_or(0) == job.epoch {
				return job;
			}
		}
		pending = st.cond.wait(pending).unwrap();
	}
}

fn worker_loop() {
	let st = state();
	loop {
		let job = next_job(st);
		if let Ok(dst) = generate(&job) {
			let mut results = st.results.lock().unwrap();
			// Results are keyed by source path so every view showing the folder
			// can pick them up; old entries are dropped after a while.
			results.retain(|_, (_, at)| at.elapsed() < Duration::from_secs(120));
			results.insert(
				job.src.to_string_lossy().to_string(),
				(dst.to_string_lossy().to_string(), Instant::now()),
			);
		}
	}
}

/// Request a thumbnail for a single item. Returns the URI of the cached
/// thumbnail when one is already valid, otherwise queues generation and
/// returns `None`. Called for visible items only, like Dolphin does.
pub fn request(src: &Path, size: u32, folder: &Path) -> Option<String> {
	if !is_thumbnailable(src) {
		return None;
	}
	let bucket = bucket_size(size);
	if let Some(uri) = cached_uri(src, bucket) {
		return Some(uri);
	}

	let st = state();
	let mut pending = st.pending.lock().unwrap();
	let key = (src.to_path_buf(), bucket);
	if pending.queued.contains(&key) {
		return None;
	}

	if pending.folder_counts.get(folder).copied().unwrap_or(0) >= MAX_PENDING_PER_FOLDER {
		drop_oldest_for_folder(&mut pending, folder);
	}

	let epoch = pending.epochs.get(folder).copied().unwrap_or(0);
	pending.queued.insert(key);
	*pending
		.folder_counts
		.entry(folder.to_path_buf())
		.or_insert(0) += 1;
	pending.queue.push_back(Job {
		src: src.to_path_buf(),
		folder: folder.to_path_buf(),
		size: bucket,
		epoch,
	});
	st.cond.notify_one();
	None
}

fn drop_oldest_for_folder(pending: &mut Pending, folder: &Path) {
	if let Some(pos) = pending.queue.iter().position(|job| job.folder == folder) {
		if let Some(job) = pending.queue.remove(pos) {
			pending.queued.remove(&(job.src, job.size));
			if let Some(count) = pending.folder_counts.get_mut(folder) {
				*count = count.saturating_sub(1);
			}
		}
	}
}

/// Drop queued work for a folder the view has left; workers check the epoch so
/// jobs already in flight stop early too.
pub fn cancel_folder(folder: &Path) {
	let st = state();
	let mut pending = st.pending.lock().unwrap();
	*pending.epochs.entry(folder.to_path_buf()).or_insert(0) += 1;
	let mut i = 0;
	while i < pending.queue.len() {
		if pending.queue[i].folder == folder {
			if let Some(job) = pending.queue.remove(i) {
				pending.queued.remove(&(job.src, job.size));
				if let Some(count) = pending.folder_counts.get_mut(folder) {
					*count = count.saturating_sub(1);
				}
			}
		} else {
			i += 1;
		}
	}
}

/// Whether any generated thumbnail is waiting to be picked up.
pub fn has_results() -> bool {
	!state().results.lock().unwrap().is_empty()
}

/// The cached thumbnail URI for a source path, once generation has finished.
pub fn result_for(src: &str) -> Option<String> {
	state()
		.results
		.lock()
		.unwrap()
		.get(src)
		.map(|(dst, _)| format!("file://{dst}"))
}

pub fn invalidate(src: &Path) {
	for tier in TIERS {
		let path = cache_path_for(src, tier);
		if path.exists() {
			let _ = fs::remove_file(&path);
		}
	}
}

// ── Generation ──────────────────────────────────────────────────────────────

fn generate(job: &Job) -> Result<PathBuf, String> {
	let src = &job.src;
	let size = job.size;
	let (mtime, file_size) = source_stat(src).ok_or("cannot stat file")?;
	if file_size == 0 {
		return Err("empty file".to_string());
	}

	let dst = cache_path_for(src, size);
	if let Some(parent) = dst.parent() {
		fs::create_dir_all(parent).map_err(|e| e.to_string())?;
	}
	let uri = file_uri(src);
	let ext = ext_lower(src);
	let tmp = temp_path_for(&dst);

	// .kra keeps an embedded preview; extracting it beats any external tool.
	if ext == "kra"
		&& extract_preview_from_kra(src, &dst, size, &uri, mtime, file_size).unwrap_or(false)
	{
		return Ok(dst);
	}

	// AppImages carry their icon; pull it out directly.
	if ext == "appimage"
		&& try_extract_icon_from_appimage(src, &dst, size, &uri, mtime, file_size).unwrap_or(false)
	{
		return Ok(dst);
	}

	// Images decode in-process through Qt, which scales while decoding the way
	// KIO's image thumbnailer does.
	if IMAGE_EXTS.contains(&ext.as_str()) && file_size <= MAX_DECODE_BYTES {
		if crate::kde_bridge::thumbnail_image(
			&src.to_string_lossy(),
			&dst.to_string_lossy(),
			size,
			&uri,
			mtime,
			file_size,
		) {
			return Ok(dst);
		}
	}

	// Everything else goes through the system's freedesktop thumbnailers,
	// which write the raw image; the cache copy gets the Thumb::* metadata.
	let mime = from_path(src)
		.first_or_octet_stream()
		.essence_str()
		.to_string();
	for thumb in load_system_thumbnailers() {
		if !thumbnailer_matches(thumb, &mime, &ext) {
			continue;
		}
		if run_system_thumb(thumb, src, &tmp, size)
			&& adopt_thumbnail(&tmp, &dst, size, &uri, mtime, file_size)
		{
			return Ok(dst);
		}
		let _ = fs::remove_file(&tmp);
	}

	// Videos without a system thumbnailer still get one from ffmpeg.
	if is_video_ext(&ext)
		&& run_ffmpegthumbnailer(src, &tmp, size)
		&& adopt_thumbnail(&tmp, &dst, size, &uri, mtime, file_size)
	{
		return Ok(dst);
	}
	let _ = fs::remove_file(&tmp);

	if let Some(im) = imagemagick_command() {
		if run_imagemagick(im, src, &tmp, size)
			&& adopt_thumbnail(&tmp, &dst, size, &uri, mtime, file_size)
		{
			return Ok(dst);
		}
	}
	let _ = fs::remove_file(&tmp);

	// Last resort: decode with the Rust image crate, which covers a few formats
	// the Qt plugins may not have.
	if IMAGE_EXTS.contains(&ext.as_str()) && file_size <= MAX_DECODE_BYTES {
		if run_image_crate(src, &dst, size, &uri, mtime, file_size).unwrap_or(false) {
			return Ok(dst);
		}
	}

	Err("no thumbnailer succeeded".to_string())
}

fn thumbnailer_matches(thumb: &SystemThumb, mime: &str, ext: &str) -> bool {
	for glob in &thumb.mime_globs {
		if glob == mime {
			return true;
		}
		if let Some(prefix) = glob.strip_suffix("/*") {
			if mime.starts_with(&format!("{prefix}/")) {
				return true;
			}
		}
		// Loose fallback for globs like "application/x-krita" when the MIME
		// database does not know the extension.
		let glob_l = glob.to_lowercase();
		if ext.len() >= 3 && (glob_l.contains(ext)) {
			return true;
		}
	}
	false
}

fn run_system_thumb(thumb: &SystemThumb, src: &Path, dst: &Path, size: u32) -> bool {
	let src_path = src.to_string_lossy().to_string();
	let uri = file_uri(src);

	let escape = |s: &str| {
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

	let mut cmd = thumb.exec.clone();
	cmd = cmd.replace("%i", &escape(&src_path));
	cmd = cmd.replace("%u", &escape(&uri));
	cmd = cmd.replace("%o", &escape(&dst.to_string_lossy()));
	cmd = cmd.replace("%s", &size.to_string());

	let mut command = Command::new("sh");
	command.arg("-c").arg(&cmd);
	match run_command_with_timeout(&mut command, COMMAND_TIMEOUT) {
		Some(status) => status.success() && dst.exists(),
		None => false,
	}
}

fn run_ffmpegthumbnailer(src: &Path, dst: &Path, size: u32) -> bool {
	let mut command = Command::new("ffmpegthumbnailer");
	command
		.arg("-i")
		.arg(src.as_os_str())
		.arg("-o")
		.arg(dst.as_os_str())
		.arg("-s")
		.arg(size.to_string());
	matches!(run_command_with_timeout(&mut command, COMMAND_TIMEOUT), Some(status) if status.success())
		&& dst.exists()
}

fn run_imagemagick(im: &str, src: &Path, dst: &Path, size: u32) -> bool {
	let mut command = Command::new(im);
	command
		.arg(src.as_os_str())
		.arg("-thumbnail")
		.arg(format!("{size}x{size}>"))
		.arg(&dst.as_os_str());
	matches!(run_command_with_timeout(&mut command, COMMAND_TIMEOUT), Some(status) if status.success())
		&& dst.exists()
		&& fs::metadata(dst).map(|m| m.len() > 0).unwrap_or(false)
}

/// Loads an external thumbnailer's output, fits it to the tier box and stores
/// it with the `Thumb::*` metadata, like KIO's saveThumbnailData() does.
fn adopt_thumbnail(
	tmp: &Path,
	dst: &Path,
	size: u32,
	uri: &str,
	mtime: i64,
	file_size: u64,
) -> bool {
	let Ok(img) = image::open(tmp) else {
		let _ = fs::remove_file(tmp);
		return false;
	};
	let fitted = fit_resize(&img, size);
	let ok = save_thumb(&fitted, dst, uri, mtime, file_size).is_ok();
	let _ = fs::remove_file(tmp);
	ok
}

/// Scratch path beside the cache entry so the final rename stays on one file
/// system. The `.part` suffix keeps it distinct from save_thumb()'s temp file.
fn temp_path_for(dst: &Path) -> PathBuf {
	dst.with_file_name(format!(
		"{}.part{}",
		dst.file_name()
			.map(|n| n.to_string_lossy().to_string())
			.unwrap_or_default(),
		std::process::id()
	))
}

fn run_image_crate(
	src: &Path,
	dst: &Path,
	size: u32,
	uri: &str,
	mtime: i64,
	file_size: u64,
) -> Result<bool, String> {
	let Ok(img) = image::open(src) else {
		return Ok(false);
	};
	let fitted = fit_resize(&img, size);
	save_thumb(&fitted, dst, uri, mtime, file_size)?;
	Ok(true)
}

/// Scale an image down to fit a square box, keeping the aspect ratio and never
/// enlarging, like the freedesktop thumbnail spec wants.
fn fit_resize(img: &image::DynamicImage, size: u32) -> RgbaImage {
	let (w, h) = img.dimensions();
	let scale = f32::min(size as f32 / w as f32, size as f32 / h as f32).min(1.0);
	let new_w = ((w as f32 * scale).round() as u32).max(1);
	let new_h = ((h as f32 * scale).round() as u32).max(1);
	img.resize_exact(new_w, new_h, FilterType::Lanczos3)
		.to_rgba8()
}

/// Writes a thumbnail PNG with the `Thumb::*` metadata the freedesktop spec
/// (and the KDE cache) use, replacing the destination atomically.
fn save_thumb(
	img: &RgbaImage,
	dst: &Path,
	uri: &str,
	mtime: i64,
	file_size: u64,
) -> Result<(), String> {
	let tmp = dst.with_file_name(format!(
		"{}.tmp{}",
		dst.file_name()
			.map(|n| n.to_string_lossy().to_string())
			.unwrap_or_default(),
		std::process::id()
	));
	let result = (|| -> Result<(), String> {
		let file = File::create(&tmp).map_err(|e| e.to_string())?;
		let mut encoder = png::Encoder::new(file, img.width(), img.height());
		encoder.set_color(png::ColorType::Rgba);
		encoder.set_depth(png::BitDepth::Eight);
		encoder
			.add_text_chunk("Thumb::URI".to_string(), uri.to_string())
			.map_err(|e| e.to_string())?;
		encoder
			.add_text_chunk("Thumb::MTime".to_string(), mtime.to_string())
			.map_err(|e| e.to_string())?;
		encoder
			.add_text_chunk("Thumb::Size".to_string(), file_size.to_string())
			.map_err(|e| e.to_string())?;
		encoder
			.add_text_chunk(
				"Software".to_string(),
				"hishell Thumbnail Generator".to_string(),
			)
			.map_err(|e| e.to_string())?;
		let mut writer = encoder.write_header().map_err(|e| e.to_string())?;
		writer
			.write_image_data(img.as_raw())
			.map_err(|e| e.to_string())?;
		Ok(())
	})();
	match result {
		Ok(()) => fs::rename(&tmp, dst).map_err(|e| {
			let _ = fs::remove_file(&tmp);
			e.to_string()
		}),
		Err(e) => {
			let _ = fs::remove_file(&tmp);
			Err(e)
		}
	}
}

// ── External process helpers ────────────────────────────────────────────────

fn wait_with_timeout(child: &mut Child, timeout: Duration) -> Option<ExitStatus> {
	let start = Instant::now();
	loop {
		match child.try_wait() {
			Ok(Some(status)) => return Some(status),
			Ok(None) => {}
			Err(_) => {
				let _ = child.kill();
				let _ = child.wait();
				return None;
			}
		}
		if start.elapsed() >= timeout {
			let _ = child.kill();
			let _ = child.wait();
			return None;
		}
		thread::sleep(Duration::from_millis(25));
	}
}

fn run_command_with_timeout(command: &mut Command, timeout: Duration) -> Option<ExitStatus> {
	let mut child = command.spawn().ok()?;
	wait_with_timeout(&mut child, timeout)
}

/// Runs a command capturing its output, with the same timeout. The pipes are
/// drained on reader threads so a chatty child cannot deadlock.
fn output_with_timeout(command: &mut Command, timeout: Duration) -> Option<Output> {
	command.stdout(Stdio::piped()).stderr(Stdio::piped());
	let mut child = command.spawn().ok()?;
	let mut stdout = child.stdout.take()?;
	let mut stderr = child.stderr.take()?;
	let out_thread = thread::spawn(move || {
		let mut buf = Vec::new();
		let _ = stdout.read_to_end(&mut buf);
		buf
	});
	let err_thread = thread::spawn(move || {
		let mut buf = Vec::new();
		let _ = stderr.read_to_end(&mut buf);
		buf
	});
	let status = wait_with_timeout(&mut child, timeout);
	let stdout = out_thread.join().unwrap_or_default();
	let stderr = err_thread.join().unwrap_or_default();
	status.map(|status| Output {
		status,
		stdout,
		stderr,
	})
}

// ── Format specific extractors ──────────────────────────────────────────────

fn extract_preview_from_kra(
	src: &Path,
	dst: &Path,
	size: u32,
	uri: &str,
	mtime: i64,
	file_size: u64,
) -> Result<bool, String> {
	let file = File::open(src).map_err(|e| format!("open zip error: {e}"))?;
	let mut archive = ZipArchive::new(file).map_err(|e| format!("zip read error: {e}"))?;

	let candidates = [
		"preview.png",
		"Preview.png",
		"mergedimage.png",
		"mergedimage.jpg",
		"Thumbnails/thumbnail.png",
		"Thumbnails/thumbnail.jpg",
	];
	for name in candidates.iter() {
		if let Ok(mut entry) = archive.by_name(name) {
			let mut buf: Vec<u8> = Vec::new();
			if entry.read_to_end(&mut buf).is_err() {
				continue;
			}
			if let Ok(img) = image::load_from_memory(&buf) {
				let fitted = fit_resize(&img, size);
				save_thumb(&fitted, dst, uri, mtime, file_size)?;
				return Ok(true);
			}
		}
	}

	// fallback: try any png/jpg in the archive
	for i in 0..archive.len() {
		let Ok(mut entry) = archive.by_index(i) else {
			continue;
		};
		let name = entry.name().to_lowercase();
		if !(name.ends_with(".png") || name.ends_with(".jpg") || name.ends_with(".jpeg")) {
			continue;
		}
		let mut buf: Vec<u8> = Vec::new();
		if entry.read_to_end(&mut buf).is_err() {
			continue;
		}
		if let Ok(img) = image::load_from_memory(&buf) {
			let fitted = fit_resize(&img, size);
			save_thumb(&fitted, dst, uri, mtime, file_size)?;
			return Ok(true);
		}
	}

	Ok(false)
}

fn try_extract_icon_from_appimage(
	src: &Path,
	dst: &Path,
	size: u32,
	uri: &str,
	mtime: i64,
	file_size: u64,
) -> Result<bool, String> {
	let mut list_command = Command::new("bsdtar");
	list_command.arg("-tf").arg(src.as_os_str());
	let Some(listing) = output_with_timeout(&mut list_command, COMMAND_TIMEOUT) else {
		return Ok(false);
	};
	if !listing.status.success() {
		return Ok(false);
	}
	let listing = String::from_utf8_lossy(&listing.stdout);

	let mut candidate: Option<String> = None;
	for line in listing.lines() {
		let line = line.trim();
		let lower = line.to_lowercase();
		let is_image = lower.ends_with(".png")
			|| lower.ends_with(".svg")
			|| lower.ends_with(".xpm")
			|| lower.ends_with(".jpg")
			|| lower.ends_with(".jpeg");
		if !is_image {
			continue;
		}
		if !(lower.contains("/icons/")
			|| lower.contains("/pixmaps/")
			|| lower.contains("/apps/")
			|| lower.contains("icon"))
		{
			continue;
		}
		if candidate.is_none()
			|| lower.contains("128")
			|| lower.contains("256")
			|| lower.contains("512")
		{
			candidate = Some(line.to_string());
			if lower.contains("256") || lower.contains("512") {
				break;
			}
		}
	}

	let Some(candidate) = candidate else {
		return Ok(false);
	};

	let mut extract_command = Command::new("bsdtar");
	extract_command
		.arg("-xOf")
		.arg(src.as_os_str())
		.arg(&candidate);
	let Some(extracted) = output_with_timeout(&mut extract_command, COMMAND_TIMEOUT) else {
		return Ok(false);
	};
	if !extracted.status.success() {
		return Ok(false);
	}
	let Ok(img) = image::load_from_memory(&extracted.stdout) else {
		return Ok(false);
	};
	let fitted = fit_resize(&img, size);
	save_thumb(&fitted, dst, uri, mtime, file_size)?;
	Ok(true)
}
