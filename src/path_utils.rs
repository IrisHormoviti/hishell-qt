use qmetaobject::prelude::*;

#[derive(QObject, Default)]
pub struct PathUtils {
	base: qt_base_class!(trait QObject),
	window: qt_property!(QVariant),

	get_segments: qt_method!(
		fn get_segments(&self, path: String) -> String {
			let p = path.trim();
			if p.is_empty() || p == "." {
				return "/".to_string();
			}
			let p = if p.ends_with('/') && p.len() > 1 {
				&p[..p.len() - 1]
			} else {
				p
			};
			p.split('/')
				.filter(|s| !s.is_empty())
				.collect::<Vec<_>>()
				.join("\n")
		}
	),

	path_for_index: qt_method!(
		fn path_for_index(&self, current_path: String, idx: i32) -> String {
			let p = current_path.trim();
			if p.is_empty() || p == "." {
				return "/".to_string();
			}
			let p = if p.ends_with('/') && p.len() > 1 {
				&p[..p.len() - 1]
			} else {
				p
			};
			let parts: Vec<&str> = p.split('/').filter(|s| !s.is_empty()).collect();
			if (idx as usize) < parts.len() {
				format!("/{}", parts[..=idx as usize].join("/"))
			} else {
				current_path
			}
		}
	),

	folder_name: qt_method!(
		fn folder_name(&self, path: String) -> String {
			let path = path.trim();
			if path.is_empty() || path == "/" || path == "." {
				return "/".to_string();
			}
			let path = if path.ends_with('/') && path.len() > 1 {
				&path[..path.len() - 1]
			} else {
				path
			};
			let name = path.split('/').next_back().unwrap_or("/");
			if name.is_empty() {
				"/".to_string()
			} else {
				name.to_string()
			}
		}
	),

	normalize_path: qt_method!(
		fn normalize_path(&self, path: String) -> String {
			Self::normalize(path)
		}
	),

	parent_path: qt_method!(
		fn parent_path(&self, path: String) -> String {
			let p = std::path::Path::new(path.trim());
			if let Some(parent) = p.parent() {
				parent.to_string_lossy().to_string()
			} else {
				"/".to_string()
			}
		}
	),

	/// Resolve a layout entry against the folder the window is showing: `~` and
	/// `~/sub` expand against the home directory, absolute paths are kept as-is,
	/// and anything else joins the base. `.` and `..` segments are collapsed.
	resolve_path: qt_method!(
		fn resolve_path(&self, base: String, spec: String) -> String {
			Self::resolve_spec(&base, &spec)
		}
	),
}

impl PathUtils {
	fn normalize(path: String) -> String {
		let p = path.trim();
		if p.is_empty() {
			return ".".to_string();
		}
		if p == "/" {
			return "/".to_string();
		}
		if p.ends_with('/') && p.len() > 1 {
			p[..p.len() - 1].to_string()
		} else {
			p.to_string()
		}
	}

	fn resolve_spec(base: &str, spec: &str) -> String {
		let spec = spec.trim();
		let base = base.trim();

		// Before the window's folder is known a relative entry is passed through
		// untouched, so the panes pick it up once the base is set.
		if base.is_empty() && !spec.starts_with('/') && !spec.starts_with('~') {
			return spec.to_string();
		}

		let joined = if spec == "~" || spec.starts_with("~/") {
			match dirs::home_dir().map(|home| home.to_string_lossy().to_string()) {
				Some(home) if spec == "~" => home,
				Some(home) => format!("{}/{}", home, &spec[2..]),
				None => spec.to_string(),
			}
		} else if spec.starts_with('/') {
			spec.to_string()
		} else {
			format!("{}/{}", base, spec)
		};

		let mut parts: Vec<&str> = Vec::new();
		for part in joined.split('/') {
			match part {
				"" | "." => {}
				".." => {
					parts.pop();
				}
				other => parts.push(other),
			}
		}
		format!("/{}", parts.join("/"))
	}
}
