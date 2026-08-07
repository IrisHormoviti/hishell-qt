use qmetaobject::prelude::*;
use std::fs;
use std::path::Path;

#[derive(QObject, Default)]
pub struct FileManager {
	base: qt_base_class!(trait QObject),

	copy_file: qt_method!(
		fn copy_file(&self, source: QString, dest: QString) -> bool {
			fs::copy(source.to_string(), dest.to_string()).is_ok()
		}
	),

	duplicate_file: qt_method!(
		fn duplicate_file(&self, source: QString) -> bool {
			let p = source.to_string();
			let path = Path::new(&p);
			if let (Some(parent), Some(stem), Some(ext)) =
				(path.parent(), path.file_stem(), path.extension())
			{
				let new_name = format!("{}_copy.{}", stem.to_string_lossy(), ext.to_string_lossy());
				let dest = parent.join(new_name);
				fs::copy(&p, &dest).is_ok()
			} else {
				false
			}
		}
	),

	new_folder: qt_method!(
		fn new_folder(&self, parent: QString) -> bool {
			let parent_string = parent.to_string();
			let parent_path = Path::new(&parent_string);
			if !parent_path.is_dir() {
				return false;
			}

			let base_name = "New Folder";
			let mut candidate = parent_path.join(base_name);
			if candidate.exists() {
				let mut created = false;
				for idx in 1..100 {
					let next = parent_path.join(format!("{} {}", base_name, idx));
					if !next.exists() {
						candidate = next;
						created = true;
						break;
					}
				}
				if !created {
					return false;
				}
			}

			fs::create_dir(&candidate).is_ok()
		}
	),

	new_text_file: qt_method!(
		fn new_text_file(&self, parent: QString) -> bool {
			let parent_string = parent.to_string();
			let parent_path = Path::new(&parent_string);
			if !parent_path.is_dir() {
				return false;
			}

			let base_name = "New Text File";
			let mut candidate = parent_path.join(format!("{}.txt", base_name));
			if candidate.exists() {
				let mut created = false;
				for idx in 1..100 {
					let next = parent_path.join(format!("{} {}.txt", base_name, idx));
					if !next.exists() {
						candidate = next;
						created = true;
						break;
					}
				}
				if !created {
					return false;
				}
			}

			std::fs::File::create(&candidate).is_ok()
		}
	),

	create_link: qt_method!(
		fn create_link(&self, source: QString, dest: QString) -> bool {
			#[cfg(unix)]
			{
				std::os::unix::fs::symlink(source.to_string(), dest.to_string()).is_ok()
			}
			#[cfg(not(unix))]
			{
				false
			}
		}
	),
}
