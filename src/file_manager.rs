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
