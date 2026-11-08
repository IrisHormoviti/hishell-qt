use qmetaobject::prelude::*;

#[derive(QObject, Default)]
pub struct PathUtils {
	base: qt_base_class!(trait QObject),
	window: qt_property!(QVariant),

	get_segments: qt_method!(
		fn get_segments(&self, path: String) -> String {
			hishell::path::segments(&path)
		}
	),

	path_for_index: qt_method!(
		fn path_for_index(&self, current_path: String, idx: i32) -> String {
			hishell::path::path_for_index(&current_path, idx)
		}
	),

	folder_name: qt_method!(
		fn folder_name(&self, path: String) -> String {
			hishell::path::folder_name(&path)
		}
	),

	normalize_path: qt_method!(
		fn normalize_path(&self, path: String) -> String {
			hishell::path::normalize(&path)
		}
	),

	navigation_plan: qt_method!(
		fn navigation_plan(&self, from: String, to: String) -> String {
			hishell::path::navigation_plan(&from, &to)
		}
	),

	parent_path: qt_method!(
		fn parent_path(&self, path: String) -> String {
			hishell::path::parent(&path)
		}
	),

	path_exists: qt_method!(
		fn path_exists(&self, base: String, text: String) -> bool {
			hishell::path::exists(&base, &text)
		}
	),

	resolve_path: qt_method!(
		fn resolve_path(&self, base: String, spec: String) -> String {
			hishell::path::resolve(&base, &spec)
		}
	),

	complete_path: qt_method!(
		fn complete_path(&self, base: String, text: String, limit: i32) -> String {
			hishell::path::complete(&base, &text, limit)
		}
	),
}
