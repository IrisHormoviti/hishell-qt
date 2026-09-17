use std::path::Path;
use std::process::Command;

pub fn open_file_with_portal(path: &Path) -> bool {
	let abs = std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
	let uri = format!("file://{}", abs.to_string_lossy());

	if let Ok(mut child) = Command::new("gdbus")
		.args([
			"call",
			"--session",
			"--dest",
			"org.freedesktop.portal.Desktop",
			"--object-path",
			"/org/freedesktop/portal/desktop",
			"--method",
			"org.freedesktop.portal.OpenURI.OpenURI",
			"",
			&uri,
			"{'ask': <true>}",
		])
		.spawn()
	{
		if let Ok(status) = child.wait() {
			if status.success() {
				return true;
			}
		}
	}

	if let Ok(mut child) = Command::new("busctl")
		.args([
			"--user",
			"call",
			"org.freedesktop.portal.Desktop",
			"/org/freedesktop/portal/desktop",
			"org.freedesktop.portal.OpenURI",
			"OpenURI",
			"ssa{sv}",
			"",
			&uri,
			"1",
			"ask",
			"b",
			"true",
		])
		.spawn()
	{
		if let Ok(status) = child.wait() {
			if status.success() {
				return true;
			}
		}
	}

	false
}
