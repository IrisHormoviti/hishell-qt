use std::path::Path;

pub fn is_image_file(path: &Path) -> bool {
	if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
		let ext_l = ext.to_lowercase();
		matches!(
			ext_l.as_str(),
			"png" | "jpg" | "jpeg" | "bmp" | "gif" | "webp" | "avif" | "tiff" | "svg" | "ico"
		)
	} else {
		false
	}
}

pub fn rotate_image(path: &Path, degrees: i32) -> bool {
	if let Ok(img) = image::open(path) {
		let normalized = ((degrees % 360) + 360) % 360;
		let rotated = match normalized {
			90 => img.rotate90(),
			180 => img.rotate180(),
			270 => img.rotate270(),
			_ => img,
		};
		if rotated.save(path).is_ok() {
			crate::thumbnailer::invalidate(path);
			return true;
		}
	}

	let deg_str = degrees.to_string();
	let path_str = path.to_string_lossy();
	if let Ok(status) = std::process::Command::new("magick")
		.args([path_str.as_ref(), "-rotate", &deg_str, path_str.as_ref()])
		.status()
	{
		if status.success() {
			crate::thumbnailer::invalidate(path);
			return true;
		}
	} else if let Ok(status) = std::process::Command::new("convert")
		.args([path_str.as_ref(), "-rotate", &deg_str, path_str.as_ref()])
		.status()
	{
		if status.success() {
			crate::thumbnailer::invalidate(path);
			return true;
		}
	}

	false
}
