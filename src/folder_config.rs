use crate::config_parser::{ConfigParser, ConfigValue};
use qmetaobject::prelude::*;

#[derive(QObject, Default)]
pub struct FolderConfig {
	base: qt_base_class!(trait QObject),

	top_layout: qt_property!(QString; NOTIFY config_changed),
	middle_layout: qt_property!(QString; NOTIFY config_changed),
	bottom_layout: qt_property!(QString; NOTIFY config_changed),
	header_layout: qt_property!(QString; NOTIFY config_changed),

	grid_size: qt_property!(i32; NOTIFY config_changed),
	show_dotfiles: qt_property!(bool; NOTIFY config_changed),
	arbitrary_placement: qt_property!(bool; NOTIFY config_changed),
	arbitrary_positions: qt_property!(QString; NOTIFY config_changed),

	config_changed: qt_signal!(),

	load: qt_method!(
		fn load(&mut self, path: QString) {
			let path_str = path.to_string();
			let cfg_path = std::path::Path::new(&path_str).join(".meta");
			let parsed = ConfigParser::parse_file(&cfg_path);

			self.top_layout = "[]".into();
			self.middle_layout = "[]".into();
			self.bottom_layout = "[]".into();
			self.header_layout = "[\"toolkit/PathBar\", \"toolkit/Spacer\", \"toolkit/MenuBar\"]".into();

			self.grid_size = 64;
			self.show_dotfiles = false;
			self.arbitrary_placement = false;
			self.arbitrary_positions = "{}".into();

			if let Some(layout) = parsed.get("LAYOUT") {
				if let Some(ConfigValue::Array(arr)) = layout.get("Top") {
					self.top_layout = ConfigValue::Array(arr.clone()).to_json_string().into();
				}
				if let Some(ConfigValue::Array(arr)) = layout.get("Middle") {
					self.middle_layout = ConfigValue::Array(arr.clone()).to_json_string().into();
				}
				if let Some(ConfigValue::Array(arr)) = layout.get("Bottom") {
					self.bottom_layout = ConfigValue::Array(arr.clone()).to_json_string().into();
				}
				if let Some(ConfigValue::Array(arr)) = layout.get("Header") {
					self.header_layout = ConfigValue::Array(arr.clone()).to_json_string().into();
				}
			}

			if let Some(view) = parsed.get("VIEW") {
				if let Some(ConfigValue::Number(n)) = view.get("GridSize") {
					self.grid_size = *n as i32;
				}
				if let Some(ConfigValue::Boolean(b)) = view.get("ShowDotfiles") {
					self.show_dotfiles = *b;
				}
				if let Some(ConfigValue::Boolean(b)) = view.get("ArbitraryPlacement") {
					self.arbitrary_placement = *b;
				}
				if let Some(ConfigValue::Dictionary(dict)) = view.get("ArbitraryPlacementPositions")
				{
					self.arbitrary_positions = ConfigValue::Dictionary(dict.clone())
						.to_json_string()
						.into();
				}
			}

			self.config_changed();
		}
	),
}
