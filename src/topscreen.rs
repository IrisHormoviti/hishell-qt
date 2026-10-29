//! Top-screen 3D banners.
//!
//! The top panel is a separate 1024x768 display, so it can show something the
//! lower file view cannot: a slowly turning 3D model of the item under the
//! cursor, the way the 3DS HOME menu shows a game's model.
//!
//! The model is data, never shell logic. A desktop entry may carry a
//! `[Topscreen]` group:
//!
//! ```ini
//! [Topscreen]
//! Model=@models/nitnendo-ds-card/nintendo-ds-card.glb
//! IconTexture=icon
//! IconArt=/home/.cache/hishell/descriptors/<hash>.png
//! Scale=1.0
//! Animate=true
//! ```
//!
//! The same group works in a folder's `.directory`, in an application's
//! `.desktop`, and in a `Type=File` descriptor (the generated entry the ROM
//! generators write). `Model` may be a normal path, a `file://` URL, or the
//! `@models/` alias, which searches `clam/models` under the XDG data
//! directories. A relative path is resolved against the item's own directory.
//! `IconArt` is optional: it overrides the file-view icon as the image written
//! into the model's icon material. A generated DS entry uses it for the bare
//! 32x32 banner art, while the file view keeps the cartridge SVG.
//!
//! An item without its own group can still get a model from a **MIME map**:
//! one desktop entry per content type under `hishell/topscreen` in the XDG data
//! directories. The `inode/directory` map is only used for a directory whose
//! own icon is the generic `folder`; a place with a specific icon (a settings
//! section, a mounted card, a custom folder icon) keeps that 2D icon.
//!
//! ```ini
//! [Desktop Entry]
//! Type=Topscreen
//! MimeType=inode/directory;
//!
//! [Topscreen]
//! Model=@models/folder/folder.glb
//! ```
//!
//! The item's own `[Topscreen]` wins over the MIME map. This module resolves
//! the model, chooses the material that receives the item's icon, and hands the
//! result to the top screen through `focus.json`; it does not draw anything.

use std::collections::HashMap;
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};

use crate::config_parser::{ConfigParser, ConfigValue};

/// The `[Topscreen]` keys.
#[derive(Clone, Debug, Default)]
struct Spec {
	model: Option<String>,
	icon_texture: Option<String>,
	icon_art: Option<String>,
	scale: Option<f64>,
	animate: Option<bool>,
}

impl Spec {
	fn is_empty(&self) -> bool {
		self.model.is_none()
			&& self.icon_texture.is_none()
			&& self.icon_art.is_none()
			&& self.scale.is_none()
			&& self.animate.is_none()
	}
}

/// A MIME map entry and the directory it came from (for relative models).
#[derive(Clone, Debug)]
struct Mapping {
	spec: Spec,
	source: PathBuf,
}

/// The resolved banner the top screen draws.
#[derive(Clone, Debug, PartialEq)]
pub struct Banner {
	/// Absolute path to the model file.
	pub model: String,
	/// The material or mesh node that receives the item's icon. `None` means
	/// the model's own `icon` convention.
	pub icon_texture: Option<String>,
	/// The image to write into that material, when the item's file-view icon
	/// is not the image the model should show. A generated DS descriptor uses
	/// this for the 32x32 banner art: the file view gets the cartridge SVG,
	/// while the model gets the bare icon.
	pub icon_art: Option<String>,
	/// Extra scale multiplier applied after the top screen fits the model.
	pub scale: f64,
	/// Whether the top screen should turn the model slowly.
	pub animate: bool,
}

/// Read the banner for `path`, if its entry or MIME has one. `icon` is the
/// item's file-view icon, already resolved by the caller: it decides whether a
/// directory gets the generic folder model.
pub fn banner_for(path: &Path, icon: &str) -> Option<Banner> {
	let direct = direct_spec(path);
	// Only a plain directory gets the folder model. A place with its own icon
	// (System Settings, Wi-Fi, Downloads, a custom .directory icon) keeps that
	// 2D icon instead of turning into a generic folder. A [Topscreen] group on
	// the item still wins, so a place can opt into a model explicitly.
	let mapping = if path.is_dir() && !folder_uses_model(icon) {
		None
	} else {
		mapping_for(&mime_for(path))
	};
	if direct.is_none() && mapping.is_none() {
		return None;
	}

	let direct_spec = direct.as_ref();
	let mapping_spec = mapping.as_ref().map(|entry| &entry.spec);

	// The model's origin decides how a relative path is resolved. A model in
	// the item's own entry belongs to the item's folder; a MIME map's model
	// belongs to the mapping file's folder (or, normally, `@models/`). A
	// missing model in the item's entry falls back to its MIME map.
	let direct_model = direct_spec
		.and_then(|spec| spec.model.as_deref())
		.and_then(|value| resolve_asset(value, crate::config::base_dir(path)));
	let mapped_model = mapping_spec
		.and_then(|spec| spec.model.as_deref())
		.and_then(|value| {
			resolve_asset(
				value,
				mapping
					.as_ref()
					.and_then(|entry| entry.source.parent())
					.unwrap_or(Path::new(".")),
			)
		});
	let model = direct_model.or(mapped_model)?;

	let icon_texture = match direct_spec
		.and_then(|spec| spec.icon_texture.clone())
		.or_else(|| mapping_spec.and_then(|spec| spec.icon_texture.clone()))
	{
		Some(value) if value.eq_ignore_ascii_case("none") => None,
		// A name that matches an image/texture in the model is resolved to the
		// material that uses it. Anything else is left as a material or mesh
		// node name for the top screen to match directly.
		Some(value) => match material_for_texture(Path::new(&model), &value) {
			// A named image is resolved to the zero-based material index. The
			// top screen flattens the imported material list in file order, so
			// this works even when the importer drops object names.
			Some(index) => Some(format!("#{index}")),
			None => Some(value),
		},
		None => material_for_texture(Path::new(&model), "icon").map(|index| format!("#{index}")),
	};
	// The model's icon material normally receives the file-view icon. A
	// generator can name the bare art instead: the file view keeps a composed
	// SVG (a cartridge with the art in its frame), while the model label gets
	// the art itself.
	let icon_art = direct_spec
		.and_then(|spec| spec.icon_art.as_deref())
		.and_then(|value| resolve_asset(value, crate::config::base_dir(path)))
		.or_else(|| {
			mapping_spec
				.and_then(|spec| spec.icon_art.as_deref())
				.and_then(|value| {
					resolve_asset(
						value,
						mapping
							.as_ref()
							.and_then(|entry| entry.source.parent())
							.unwrap_or(Path::new(".")),
					)
				})
		});
	let scale = direct_spec
		.and_then(|spec| spec.scale)
		.or_else(|| mapping_spec.and_then(|spec| spec.scale))
		.unwrap_or(1.0);
	let animate = direct_spec
		.and_then(|spec| spec.animate)
		.or_else(|| mapping_spec.and_then(|spec| spec.animate))
		.unwrap_or(true);

	Some(Banner {
		model,
		icon_texture,
		icon_art,
		scale,
		animate,
	})
}

/// Whether a directory should get the generic folder model. Only the plain
/// `folder` icon does; every specific place icon (`user-home`, `folder-download`,
/// `preferences-system`, a custom image, ...) keeps its own 2D icon.
fn folder_uses_model(icon: &str) -> bool {
	icon == "folder"
}

/// The `[Topscreen]` group from the item's own entry: its `.directory`, its
/// `.desktop`, or the descriptor that describes the file. The on-disk entry
/// wins over a descriptor, exactly as it does for the item's name and icon.
fn direct_spec(path: &Path) -> Option<Spec> {
	if let Some(entry) = crate::config::entry_path(path) {
		if let Some(spec) = spec_from_file(&entry) {
			return Some(spec);
		}
	}
	if let Some(descriptor) = crate::directory_descriptor::lookup(path) {
		if let Some(spec) = spec_from_file(&descriptor.source) {
			return Some(spec);
		}
	}
	None
}

fn spec_from_file(file: &Path) -> Option<Spec> {
	let (sections, _) = ConfigParser::parse_file(file);
	spec_from_sections(&sections)
}

fn spec_from_sections(sections: &HashMap<String, HashMap<String, ConfigValue>>) -> Option<Spec> {
	let section = sections.get("Topscreen")?;
	let spec = Spec {
		model: string(section, "Model"),
		icon_texture: string(section, "IconTexture"),
		icon_art: string(section, "IconArt"),
		scale: number(section, "Scale"),
		animate: boolean(section, "Animate"),
	};
	(!spec.is_empty()).then_some(spec)
}

fn string(section: &HashMap<String, ConfigValue>, key: &str) -> Option<String> {
	match section.get(key)? {
		ConfigValue::String(value) => Some(value.trim().to_string()).filter(|v| !v.is_empty()),
		ConfigValue::Number(value) => Some(value.to_string()),
		_ => None,
	}
}

fn number(section: &HashMap<String, ConfigValue>, key: &str) -> Option<f64> {
	match section.get(key)? {
		ConfigValue::Number(value) => Some(*value),
		ConfigValue::String(value) => value.trim().parse::<f64>().ok(),
		_ => None,
	}
}

fn boolean(section: &HashMap<String, ConfigValue>, key: &str) -> Option<bool> {
	match section.get(key)? {
		ConfigValue::Boolean(value) => Some(*value),
		ConfigValue::String(value) => match value.trim().to_ascii_lowercase().as_str() {
			"1" | "true" | "yes" | "on" => Some(true),
			"0" | "false" | "no" | "off" => Some(false),
			_ => None,
		},
		_ => None,
	}
}

/// Resolve an asset: `@models/...`, a `file://` URL or a path relative to
/// `base`. Both a model and an explicit icon-art image go through this.
fn resolve_asset(value: &str, base: &Path) -> Option<String> {
	let value = value.trim();
	if value.is_empty() {
		return None;
	}

	let path = if value == "@models" {
		model_roots().into_iter().find(|path| path.is_dir())?
	} else if let Some(rest) = value.strip_prefix("@models/") {
		model_roots()
			.into_iter()
			.map(|root| root.join(rest))
			.find(|path| path.is_file())?
	} else if let Some(rest) = value.strip_prefix("file://") {
		PathBuf::from(percent_decode(rest))
	} else {
		let path = PathBuf::from(value);
		if path.is_absolute() {
			path
		} else {
			base.join(path)
		}
	};

	path.is_file().then(|| path.to_string_lossy().to_string())
}

/// The material that uses the model texture (image) called `wanted`.
///
/// A model author names the label image in Blender; the material that samples
/// it may be called anything, and the glTF importer does not expose the image
/// name on the Qt `Texture` object. Read the glTF JSON and translate the
/// texture name to the material name the top screen can address.
fn material_for_texture(model: &Path, wanted: &str) -> Option<usize> {
	let json = read_model_json(model)?;
	let images = json.get("images").and_then(serde_json::Value::as_array)?;
	let image_indices: Vec<usize> = images
		.iter()
		.enumerate()
		.filter_map(|(index, image)| {
			image
				.get("name")
				.and_then(serde_json::Value::as_str)
				.is_some_and(|name| name.eq_ignore_ascii_case(wanted))
				.then_some(index)
		})
		.collect();
	if image_indices.is_empty() {
		return None;
	}

	let textures = json.get("textures").and_then(serde_json::Value::as_array)?;
	let texture_indices: Vec<usize> = textures
		.iter()
		.enumerate()
		.filter_map(|(index, texture)| {
			let source = texture.get("source")?.as_u64()? as usize;
			image_indices.contains(&source).then_some(index)
		})
		.collect();
	if texture_indices.is_empty() {
		return None;
	}

	let materials = json.get("materials").and_then(serde_json::Value::as_array)?;
	for (material_index, material) in materials.iter().enumerate() {
		let Some(index) = material
			.get("pbrMetallicRoughness")
			.and_then(|pbr| pbr.get("baseColorTexture"))
			.and_then(|texture| texture.get("index"))
			.and_then(serde_json::Value::as_u64)
		else {
			continue;
		};
		if texture_indices.contains(&(index as usize)) {
			return Some(material_index);
		}
	}
	None
}

/// The JSON of a `.glb` (binary glTF) or `.gltf` file.
fn read_model_json(path: &Path) -> Option<serde_json::Value> {
	if path
		.extension()
		.and_then(|ext| ext.to_str())
		.is_some_and(|ext| ext.eq_ignore_ascii_case("gltf"))
	{
		let text = fs::read_to_string(path).ok()?;
		return serde_json::from_str(&text).ok();
	}

	let mut file = fs::File::open(path).ok()?;
	let mut header = [0u8; 12];
	file.read_exact(&mut header).ok()?;
	if &header[0..4] != b"glTF" {
		return None;
	}
	let mut chunk = [0u8; 8];
	file.read_exact(&mut chunk).ok()?;
	let length = u32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]) as usize;
	let kind = u32::from_le_bytes([chunk[4], chunk[5], chunk[6], chunk[7]]);
	if kind != 0x4e4f_534a {
		return None;
	}
	let mut json = vec![0u8; length];
	file.read_exact(&mut json).ok()?;
	serde_json::from_slice(&json).ok()
}

fn percent_decode(text: &str) -> String {
	let bytes = text.as_bytes();
	let mut out = Vec::with_capacity(bytes.len());
	let mut i = 0;
	while i < bytes.len() {
		if bytes[i] == b'%' && i + 2 < bytes.len() {
			let high = (bytes[i + 1] as char).to_digit(16);
			let low = (bytes[i + 2] as char).to_digit(16);
			if let (Some(high), Some(low)) = (high, low) {
				out.push((high * 16 + low) as u8);
				i += 3;
				continue;
			}
		}
		out.push(bytes[i]);
		i += 1;
	}
	String::from_utf8_lossy(&out).into_owned()
}

/// The data directories in search order: the user's first, then the system's.
fn data_dirs() -> Vec<PathBuf> {
	let mut dirs = Vec::new();
	if let Some(dir) = dirs::data_dir() {
		dirs.push(dir);
	}
	let value = std::env::var("XDG_DATA_DIRS")
		.unwrap_or_else(|_| "/usr/local/share:/usr/share".to_string());
	for part in value.split(':').filter(|part| !part.is_empty()) {
		dirs.push(PathBuf::from(part));
	}
	dirs
}

fn model_roots() -> Vec<PathBuf> {
	data_dirs()
		.into_iter()
		.map(|dir| dir.join("clam").join("models"))
		.collect()
}

/// The content type used to choose a MIME map.
fn mime_for(path: &Path) -> String {
	if path.is_dir() {
		return "inode/directory".to_string();
	}
	crate::kde_bridge::mime_type(&path.to_string_lossy()).unwrap_or_else(|| {
		mime_guess::from_path(path)
			.first_or_octet_stream()
			.essence_str()
			.to_string()
	})
}

/// The first MIME map in `hishell/topscreen` that names this content type.
fn mapping_for(mime: &str) -> Option<Mapping> {
	for dir in data_dirs()
		.into_iter()
		.map(|dir| dir.join("hishell").join("topscreen"))
	{
		let Ok(entries) = fs::read_dir(&dir) else {
			continue;
		};
		let mut files: Vec<PathBuf> = entries
			.flatten()
			.map(|entry| entry.path())
			.filter(|path| {
				path.extension()
					.is_some_and(|ext| ext.eq_ignore_ascii_case("desktop"))
			})
			.collect();
		files.sort();
		for file in files {
			let (sections, _) = ConfigParser::parse_file(&file);
			let Some(entry) = sections.get("Desktop Entry") else {
				continue;
			};
			let Some(types) = string(entry, "MimeType") else {
				continue;
			};
			if !types
				.split(';')
				.map(str::trim)
				.any(|pattern| mime_matches(pattern, mime))
			{
				continue;
			}
			let Some(spec) = spec_from_sections(&sections) else {
				continue;
			};
			if spec.model.is_none() {
				continue;
			}
			return Some(Mapping { spec, source: file });
		}
	}
	None
}

fn mime_matches(pattern: &str, mime: &str) -> bool {
	if pattern == mime {
		return true;
	}
	if let Some(prefix) = pattern.strip_suffix("/*") {
		return mime.starts_with(&format!("{prefix}/"));
	}
	false
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn a_topscreen_group_is_read() {
		let dir =
			std::env::temp_dir().join(format!("hishell-topscreen-spec-{}", std::process::id()));
		fs::create_dir_all(&dir).unwrap();
		let entry = dir.join("game.desktop");
		fs::write(
			&entry,
			"[Desktop Entry]\nType=File\nPath=/tmp/game.nds\n\n[Topscreen]\n\
			 Model=@models/card/card.glb\nIconTexture=label\n\
			 IconArt=/tmp/card-art.png\nScale=1.5\nAnimate=false\n",
		)
		.unwrap();

		let spec = spec_from_file(&entry).unwrap();
		assert_eq!(spec.model.as_deref(), Some("@models/card/card.glb"));
		assert_eq!(spec.icon_texture.as_deref(), Some("label"));
		assert_eq!(spec.icon_art.as_deref(), Some("/tmp/card-art.png"));
		assert_eq!(spec.scale, Some(1.5));
		assert_eq!(spec.animate, Some(false));

		fs::remove_dir_all(dir).unwrap();
	}

	#[test]
	fn only_the_generic_folder_gets_the_folder_model() {
		assert!(folder_uses_model("folder"));
		assert!(!folder_uses_model("user-home"));
		assert!(!folder_uses_model("folder-download"));
		assert!(!folder_uses_model("preferences-system"));
		assert!(!folder_uses_model("file:///home/me/.icons/folder.png"));
	}

	#[test]
	fn an_entry_without_the_group_has_no_spec() {
		let dir =
			std::env::temp_dir().join(format!("hishell-topscreen-empty-{}", std::process::id()));
		fs::create_dir_all(&dir).unwrap();
		let entry = dir.join("game.desktop");
		fs::write(&entry, "[Desktop Entry]\nType=File\nPath=/tmp/game.nds\n").unwrap();

		assert!(spec_from_file(&entry).is_none());

		fs::remove_dir_all(dir).unwrap();
	}

	#[test]
	fn mime_patterns_match_exactly_and_by_wildcard() {
		assert!(mime_matches("inode/directory", "inode/directory"));
		assert!(!mime_matches("inode/directory", "application/octet-stream"));
		assert!(mime_matches(
			"application/*",
			"application/vnd.nintendo.nitro.rom"
		));
		assert!(!mime_matches("application/*", "inode/directory"));
	}

	#[test]
	fn percent_encoded_file_urls_are_decoded() {
		assert_eq!(percent_decode("card%20model.glb"), "card model.glb");
		assert_eq!(percent_decode("plain.glb"), "plain.glb");
	}

	#[test]
	fn a_texture_name_resolves_to_its_material() {
		let dir = std::env::temp_dir().join(format!(
			"hishell-topscreen-texture-{}",
			std::process::id()
		));
		fs::create_dir_all(&dir).unwrap();
		let glb = dir.join("card.glb");
		let json = br#"{
			"images": [{"name": "icon"}, {"name": "shell"}],
			"textures": [{"source": 0}, {"source": 1}],
			"materials": [
				{"name": "label", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}},
				{"name": "body", "pbrMetallicRoughness": {"baseColorTexture": {"index": 1}}}
			]
		}"#;
		let mut bytes = Vec::new();
		bytes.extend_from_slice(b"glTF");
		bytes.extend_from_slice(&2u32.to_le_bytes());
		let total = 12 + 8 + json.len() as u32;
		bytes.extend_from_slice(&total.to_le_bytes());
		bytes.extend_from_slice(&(json.len() as u32).to_le_bytes());
		bytes.extend_from_slice(&0x4e4f_534au32.to_le_bytes());
		bytes.extend_from_slice(json);
		fs::write(&glb, bytes).unwrap();

		assert_eq!(material_for_texture(&glb, "icon"), Some(0));
		assert_eq!(material_for_texture(&glb, "missing"), None);

		fs::remove_dir_all(dir).unwrap();
	}

	#[test]
	fn a_mime_map_resolves_the_shipped_ds_model() {
		let root = std::env::temp_dir().join(format!(
			"hishell-topscreen-map-{}",
			std::process::id()
		));
		let map_dir = root.join("hishell").join("topscreen");
		let model_dir = root.join("clam").join("models").join("nitnendo-ds-card");
		fs::create_dir_all(&map_dir).unwrap();
		fs::create_dir_all(&model_dir).unwrap();
		fs::write(model_dir.join("nintendo-ds-card.glb"), b"glTF").unwrap();
		fs::write(
			map_dir.join("nintendo-ds.desktop"),
			"[Desktop Entry]\nType=Topscreen\n\
			 MimeType=application/x-nintendo-ds-rom;\n\n[Topscreen]\n\
			 Model=@models/nitnendo-ds-card/nintendo-ds-card.glb\n",
		)
		.unwrap();

		let previous = std::env::var_os("XDG_DATA_HOME");
		// SAFETY: this test owns the variable for its duration and is the only
		// test that reads the MIME map.
		unsafe { std::env::set_var("XDG_DATA_HOME", &root) };
		let mapping = mapping_for("application/x-nintendo-ds-rom");
		let resolved = mapping.and_then(|mapping| {
			let model = mapping.spec.model.as_deref()?;
			resolve_asset(model, mapping.source.parent()?)
		});
		match previous {
			Some(value) => unsafe { std::env::set_var("XDG_DATA_HOME", value) },
			None => unsafe { std::env::remove_var("XDG_DATA_HOME") },
		}

		let resolved = resolved.expect("the DS MIME map resolves a model");
		assert!(resolved.ends_with("nintendo-ds-card.glb"), "{resolved}");
		fs::remove_dir_all(root).unwrap();
	}
}
