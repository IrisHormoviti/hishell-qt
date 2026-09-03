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
}
