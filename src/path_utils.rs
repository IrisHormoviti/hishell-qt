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

	/// Whether `text` resolves to something that exists, with `base` resolving
	/// relative text. Used to reject locations that cannot be navigated to; a
	/// file is a valid target because opening it shows its folder.
	path_exists: qt_method!(
		fn path_exists(&self, base: String, text: String) -> bool {
			let text = text.trim();
			if text.is_empty() {
				return false;
			}
			std::path::Path::new(&Self::resolve_spec(&base, text)).exists()
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

	/// Directory entries matching the last segment of `text`, for the location
	/// bar's completer. `base` resolves relative text. Returns a JSON array of
	/// `{name, path, suffix, is_dir}` where `path` can be put straight back into
	/// the text box and `suffix` is the part of it that is still missing; folders
	/// are listed first and get a trailing slash so typing can continue into them.
	complete_path: qt_method!(
		fn complete_path(&self, base: String, text: String, limit: i32) -> String {
			Self::complete(&base, &text, limit)
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

	fn complete(base: &str, text: &str, limit: i32) -> String {
		let text = text.trim();
		if text.is_empty() {
			return "[]".to_string();
		}
		let limit = limit.clamp(1, 64) as usize;

		// Split the text into the folder to list and the name prefix to match;
		// the display prefix keeps `~` and relative text as the user typed it.
		let (lookup_spec, display_prefix, prefix) = if text == "~" {
			("~/".to_string(), "~/".to_string(), String::new())
		} else if let Some(idx) = text.rfind('/') {
			let split = text[..=idx].to_string();
			(split.clone(), split, text[idx + 1..].to_string())
		} else {
			(String::new(), String::new(), text.to_string())
		};

		let lookup = Self::resolve_spec(base, &lookup_spec);
		let Ok(read) = std::fs::read_dir(&lookup) else {
			return "[]".to_string();
		};

		let prefix_lower = prefix.to_lowercase();
		let show_hidden = prefix.starts_with('.');
		let mut entries: Vec<(String, bool)> = Vec::new();
		for entry in read.flatten() {
			let name = entry.file_name().to_string_lossy().to_string();
			if !show_hidden && name.starts_with('.') {
				continue;
			}
			if !name.to_lowercase().starts_with(&prefix_lower) {
				continue;
			}
			entries.push((name, entry.path().is_dir()));
		}
		entries.sort_by(|a, b| {
			b.1.cmp(&a.1)
				.then_with(|| a.0.to_lowercase().cmp(&b.0.to_lowercase()))
		});
		entries.truncate(limit);

		let suggestions: Vec<serde_json::Value> = entries
			.iter()
			.map(|(name, is_dir)| {
				let rest: String = name.chars().skip(prefix.chars().count()).collect();
				let path = if *is_dir {
					format!("{}{}/", display_prefix, name)
				} else {
					format!("{}{}", display_prefix, name)
				};
				let suffix = if *is_dir { format!("{}/", rest) } else { rest };
				serde_json::json!({
					"name": name,
					"path": path,
					"suffix": suffix,
					"is_dir": is_dir,
				})
			})
			.collect();
		serde_json::Value::Array(suggestions).to_string()
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
