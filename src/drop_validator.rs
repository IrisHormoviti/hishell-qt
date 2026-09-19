use crate::bridge::ffi::{DropValidator, QString, QStringList, QVariant};

#[derive(Default)]
pub struct DropValidatorRust {
	pub window: QVariant,
}

impl DropValidatorRust {
	pub fn is_drop_valid(&self, target_path: &QString, source_paths: &QStringList) -> bool {
		let target_str = target_path.to_string();
		if target_str.is_empty() || source_paths.is_empty() {
			return false;
		}
		let source_list: Vec<String> = source_paths
			.iter()
			.map(|v| v.to_string())
			.collect();

		if source_list.is_empty() {
			return false;
		}

		let norm_target = Self::normalize(&target_str);

		for src in source_list {
			if src.is_empty() {
				continue;
			}
			let src_norm = Self::normalize(&src);
			let src_stripped = src_norm.strip_prefix("file://").unwrap_or(&src_norm);
			let src_stripped = Self::normalize(src_stripped);

			let last_slash = src_stripped.rfind('/');
			let src_parent = match last_slash {
				Some(0) => "/",
				Some(pos) => &src_stripped[..pos],
				None => "",
			};

			if norm_target == src_parent {
				return false;
			}

			if norm_target == src_stripped
				|| norm_target.starts_with(&format!("{}/", src_stripped))
			{
				return false;
			}
		}

		true
	}

	fn normalize(path: &str) -> String {
		let p = path.trim();
		if p.is_empty() || p == "." {
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
