use std::collections::HashMap;
use std::fs;
use std::path::Path;

#[derive(Debug, Clone)]
pub enum ConfigValue {
	String(String),
	Number(f64),
	Boolean(bool),
	Array(Vec<ConfigValue>),
	Dictionary(HashMap<String, ConfigValue>),
	Vector2(f64, f64),
}

impl ConfigValue {
	pub fn to_json_string(&self) -> String {
		match self {
			ConfigValue::String(s) => format!("\"{}\"", s.replace('"', "\\\"")),
			ConfigValue::Number(n) => n.to_string(),
			ConfigValue::Boolean(b) => {
				if *b {
					"true".to_string()
				} else {
					"false".to_string()
				}
			}
			ConfigValue::Array(arr) => {
				let items: Vec<String> = arr.iter().map(|v| v.to_json_string()).collect();
				format!("[{}]", items.join(","))
			}
			ConfigValue::Dictionary(dict) => {
				let items: Vec<String> = dict
				.iter()
				.map(|(k, v)| format!("\"{}\":{}", k, v.to_json_string()))
				.collect();
				format!("{{{}}}", items.join(","))
			}
			ConfigValue::Vector2(x, y) => {
				// Represent Vector2 as an object {x: ..., y: ...}
				format!("{{\"x\":{},\"y\":{}}}", x, y)
			}
		}
	}
}

pub struct ConfigParser;

impl ConfigParser {
	pub fn parse_files(paths: &[&Path]) -> HashMap<String, HashMap<String, ConfigValue>> {
		let mut combined = HashMap::new();
		for path in paths {
			for (section, items) in Self::parse_file(path) {
				combined
				.entry(section)
				.or_insert_with(HashMap::new)
				.extend(items);
			}
		}
		combined
	}

	pub fn parse_file(path: &Path) -> HashMap<String, HashMap<String, ConfigValue>> {
		let mut config = HashMap::new();
		if let Ok(content) = fs::read_to_string(path) {
			let mut current_section = "".to_string();
			let mut section_map = HashMap::new();

			for line in content.lines() {
				let line = line.trim();
				if line.is_empty() || line.starts_with(';') || line.starts_with('#') {
					continue;
				}

				if line.starts_with('[') && line.ends_with(']') {
					if !current_section.is_empty() {
						config.insert(current_section.clone(), section_map.clone());
					}
					current_section = line[1..line.len() - 1].to_string();
					section_map.clear();
				} else if let Some(idx) = line.find('=') {
					let key = line[..idx].trim().to_string();
					let val_str = line[idx + 1..].trim();
					section_map.insert(key, Self::parse_value(val_str));
				}
			}
			if !current_section.is_empty() {
				config.insert(current_section, section_map);
			}
		}
		config
	}

	pub fn set_value(path: &Path, section: &str, key: &str, value: &str) {
		let content = fs::read_to_string(path).unwrap_or_default();
		let mut out = String::new();
		let mut in_section = false;
		let mut replaced = false;

		for line in content.lines() {
			let trimmed = line.trim();

			if trimmed.starts_with('[') && trimmed.ends_with(']') {
				if in_section && !replaced {
					out.push_str(&format!("{}={}\n", key, value));
					replaced = true;
				}
				in_section = trimmed == format!("[{}]", section);
			} else if in_section && trimmed.starts_with(key) {
				if let Some((k, _)) = trimmed.split_once('=') {
					if k.trim() == key {
						out.push_str(&format!("{}={}\n", key, value));
						replaced = true;
						continue;
					}
				}
			}

			out.push_str(line);
			out.push('\n');
		}

		if !replaced {
			if !in_section {
				out.push_str(&format!("\n[{}]\n", section));
			}
			out.push_str(&format!("{}={}\n", key, value));
		}

		if let Some(parent) = path.parent() {
			let _ = fs::create_dir_all(parent);
		}

		if let Err(e) = fs::write(path, out) {
			eprintln!("Failed to save config: {}", e);
		}
	}

	fn parse_value(s: &str) -> ConfigValue {
		let s = s.trim();
		if s == "true" {
			ConfigValue::Boolean(true)
		} else if s == "false" {
			ConfigValue::Boolean(false)
		} else if s.starts_with('"') && s.ends_with('"') {
			ConfigValue::String(s[1..s.len() - 1].to_string())
		} else if s.starts_with('[') && s.ends_with(']') {
			let inner = &s[1..s.len() - 1];
			// Simple split by comma for demo purposes.
			// Real parser would handle nested structures.
			let items = Self::split_comma(inner);
			ConfigValue::Array(items.into_iter().map(|i| Self::parse_value(&i)).collect())
		} else if s.starts_with('{') && s.ends_with('}') {
			let inner = &s[1..s.len() - 1];
			let items = Self::split_comma(inner);
			let mut dict = HashMap::new();
			for item in items {
				// handle either "key": value or key=value
				if let Some(idx) = item.find(':').or_else(|| item.find('=')) {
					let k = item[..idx].trim();
					let v = item[idx + 1..].trim();
					let key_str = if k.starts_with('"') && k.ends_with('"') {
						k[1..k.len() - 1].to_string()
					} else {
						k.to_string()
					};
					dict.insert(key_str, Self::parse_value(v));
				}
			}
			ConfigValue::Dictionary(dict)
		} else if s.starts_with('(') && s.ends_with(')') {
			let inner = &s[1..s.len() - 1];
			let parts: Vec<&str> = inner.split(',').collect();
			if parts.len() == 2 {
				let x = parts[0].trim().parse::<f64>().unwrap_or(0.0);
				let y = parts[1].trim().parse::<f64>().unwrap_or(0.0);
				ConfigValue::Vector2(x, y)
			} else {
				ConfigValue::String(s.to_string())
			}
		} else if let Ok(n) = s.parse::<f64>() {
			ConfigValue::Number(n)
		} else {
			ConfigValue::String(s.to_string())
		}
	}

	fn split_comma(s: &str) -> Vec<String> {
		let mut result = Vec::new();
		let mut current = String::new();
		let mut depth_array = 0;
		let mut depth_dict = 0;
		let mut depth_vec = 0;
		let mut in_string = false;

		for c in s.chars() {
			match c {
				'"' => in_string = !in_string,
				'[' if !in_string => depth_array += 1,
				']' if !in_string => depth_array -= 1,
				'{' if !in_string => depth_dict += 1,
				'}' if !in_string => depth_dict -= 1,
				'(' if !in_string => depth_vec += 1,
				')' if !in_string => depth_vec -= 1,
				',' if !in_string && depth_array == 0 && depth_dict == 0 && depth_vec == 0 => {
					result.push(current.trim().to_string());
					current.clear();
					continue;
				}
				_ => {}
			}
			current.push(c);
		}
		if !current.trim().is_empty() {
			result.push(current.trim().to_string());
		}
		result
	}
}
