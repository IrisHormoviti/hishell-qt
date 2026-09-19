use cxx_qt_lib::QString;

pub struct PathUtilsRust {
	pub window: cxx_qt_lib::QVariant,
}

impl Default for PathUtilsRust {
	fn default() -> Self {
		Self { window: cxx_qt_lib::QVariant::default() }
	}
}

impl PathUtilsRust {
	pub fn get_segments(&self, path: &QString) -> QString {
		let p = path.to_string();
		let p = p.trim();
		if p.is_empty() || p == "." {
			return QString::from("/");
		}
		let p = if p.ends_with('/') && p.len() > 1 { &p[..p.len() - 1] } else { p };
		let result = p.split('/').filter(|s| !s.is_empty()).collect::<Vec<_>>().join("\n");
		QString::from(result.as_str())
	}

	pub fn path_for_index(&self, current_path: &QString, idx: i32) -> QString {
		let p = current_path.to_string();
		let p = p.trim();
		if p.is_empty() || p == "." {
			return QString::from("/");
		}
		let p = if p.ends_with('/') && p.len() > 1 { &p[..p.len() - 1] } else { p };
		let parts: Vec<&str> = p.split('/').filter(|s| !s.is_empty()).collect();
		if (idx as usize) < parts.len() {
			let result = format!("/{}", parts[..=idx as usize].join("/"));
			QString::from(result.as_str())
		} else {
			current_path.clone()
		}
	}

	pub fn folder_name(&self, path: &QString) -> QString {
		let path_str = path.to_string();
		let path = path_str.trim();
		if path.is_empty() || path == "/" || path == "." {
			return QString::from("/");
		}
		let path = if path.ends_with('/') && path.len() > 1 { &path[..path.len() - 1] } else { path };
		let name = path.split('/').next_back().unwrap_or("/");
		if name.is_empty() { QString::from("/") } else { QString::from(name) }
	}

	pub fn normalize_path(&self, path: &QString) -> QString {
		let p = path.to_string();
		let p = p.trim();
		if p.is_empty() {
			return QString::from(".");
		}
		if p == "/" {
			return QString::from("/");
		}
		let result = if p.ends_with('/') && p.len() > 1 { p[..p.len() - 1].to_string() } else { p.to_string() };
		QString::from(result.as_str())
	}

	pub fn parent_path(&self, path: &QString) -> QString {
		let p_str = path.to_string();
		let p = std::path::Path::new(p_str.trim());
		if let Some(parent) = p.parent() {
			QString::from(parent.to_string_lossy().as_ref())
		} else {
			QString::from("/")
		}
	}
}
