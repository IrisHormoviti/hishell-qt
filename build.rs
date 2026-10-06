use regex::Regex;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use walkdir::WalkDir;

struct QmlProperty {
	name: String,
	prop_type: String,
	is_readonly: bool,
}

struct QmlSignal {
	name: String,
}

struct QmlMethod {
	name: String,
	args: Vec<(String, String)>,
	return_type: String,
}

struct QmlComponent {
	name: String,
	properties: Vec<QmlProperty>,
	signals: Vec<QmlSignal>,
	methods: Vec<QmlMethod>,
}

fn build_kde_bridge() {
	use std::env;

	let qt_include = env::var("DEP_QT_INCLUDE_PATH")
		.expect("DEP_QT_INCLUDE_PATH is missing; qttypes must be a dependency");
	let mut build = cc::Build::new();
	build.cpp(true).std("c++20").pic(true);
	for flag in env::var("DEP_QT_COMPILE_FLAGS")
		.expect("DEP_QT_COMPILE_FLAGS is missing; qttypes must be a dependency")
		.split_terminator(';')
	{
		if !flag.is_empty() && !flag.starts_with("-std=") {
			build.flag(flag);
		}
	}
	build.include(&qt_include);
	for module in ["QtCore", "QtGui", "QtDBus"] {
		let module_dir = Path::new(&qt_include).join(module);
		if module_dir.is_dir() {
			build.include(module_dir);
		}
	}
	let out_dir = env::var("OUT_DIR").expect("OUT_DIR is missing");
	build.include(&out_dir);

	for component in ["KService", "KIO", "KIOCore", "KIOGui", "KCoreAddons"] {
		let include_dir = format!("/usr/include/KF6/{component}");
		if !Path::new(&include_dir).is_dir() {
			panic!(
				"KDE Frameworks 6 headers not found at {include_dir}.\n\
				Install the KF6 development packages to build hishell-qt:\n\
				\u{20} Arch:   sudo pacman -S kservice kio\n\
				\u{20} Debian: sudo apt install libkf6service-dev libkf6kio-dev libkf6coreaddons-dev\n\
				\u{20} Fedora: sudo dnf install kf6-kservice-devel kf6-kio-devel kf6-kcoreaddons-devel"
			);
		}
		build.include(&include_dir);
	}

	let moc = find_moc();
	let moc_output = format!("{out_dir}/moc_kde_bridge.cpp");
	let status = Command::new(&moc)
		.args(["src/kde_bridge.cpp", "-o", &moc_output])
		.status()
		.unwrap_or_else(|error| panic!("Failed to run {}: {error}", moc.display()));
	if !status.success() {
		panic!("moc failed on src/kde_bridge.cpp");
	}

	build.file("src/kde_bridge.cpp");
	build.compile("hishell_kde_bridge");

	for lib in [
		"KF6Service",
		"KF6KIOGui",
		"KF6KIOCore",
		"KF6CoreAddons",
		"Qt6DBus",
	] {
		println!("cargo:rustc-link-lib={lib}");
	}
	println!("cargo:rerun-if-changed=src/kde_bridge.cpp");
}

fn find_moc() -> PathBuf {
	if let Ok(moc) = std::env::var("MOC") {
		let path = PathBuf::from(moc);
		if path.is_file() {
			return path;
		}
	}
	if let Ok(output) = Command::new("qmake6")
		.args(["-query", "QT_INSTALL_LIBEXECS"])
		.output()
	{
		if output.status.success() {
			let text = String::from_utf8_lossy(&output.stdout);
			let base = PathBuf::from(text.trim());
			for candidate in [base.join("moc"), base.join("libexec").join("moc")] {
				if candidate.is_file() {
					return candidate;
				}
			}
		}
	}
	for candidate in ["/usr/lib/qt6/moc", "/usr/lib/qt6/libexec/moc"] {
		let path = PathBuf::from(candidate);
		if path.is_file() {
			return path;
		}
	}
	panic!(
		"moc (Qt Meta-Object Compiler) not found. Install the Qt6 development tools \
		(qt6-base / qt6-base-dev) or set the MOC environment variable"
	);
}

fn main() {
	let output_path = "Hishell/plugins.qmltypes";

	println!("cargo:rerun-if-changed=src/");
	println!("cargo:rerun-if-changed=build.rs");

	build_kde_bridge();

	// Specifically match structs deriving QObject
	let struct_re = Regex::new(
		r"#\[derive\([^)]*QObject[^)]*\)\]\s*(?:#\[[^\]]+\]\s*)*(?:pub\s+)?struct\s+([A-Za-z0-9_]+)",
	)
	.unwrap();

	// Match properties defined inside qt_property!(...)
	let property_re = Regex::new(
		r"([a-zA-Z0-9_]+)\s*:\s*qt_property!\s*\(\s*([a-zA-Z0-9_<>]+)(?:\s*;([^)]*))?\)",
	)
	.unwrap();

	// Match signals defined inside qt_signal!(...)
	let signal_re = Regex::new(r"([a-zA-Z0-9_]+)\s*:\s*qt_signal!\s*\(").unwrap();

	// Specifically match methods defined inside qt_method!(...)
	let method_re = Regex::new(
		r"qt_method!\s*\(\s*(?:pub\s+)?fn\s+([a-zA-Z0-9_]+)\s*\(\s*&(?:mut\s+)?self(?:,\s*([^)]*))?\s*\)(?:\s*->\s*([a-zA-Z0-9_<>]+))?",
	)
	.unwrap();

	let mut components = Vec::new();

	for entry in WalkDir::new("src").into_iter().filter_map(|e| e.ok()) {
		if entry.path().extension().and_then(|s| s.to_str()) != Some("rs") {
			continue;
		}

		let content = match fs::read_to_string(entry.path()) {
			Ok(c) => c,
			Err(_) => continue,
		};

		let struct_name = match struct_re.captures(&content) {
			Some(cap) => cap[1].to_string(),
			None => continue,
		};

		let mut properties = Vec::new();
		for cap in property_re.captures_iter(&content) {
			let field_name = cap[1].to_string();
			let raw_type = cap[2].trim();
			let rest = cap.get(3).map_or("", |m| m.as_str());

			let mut name = field_name;
			if let Some(alias_pos) = rest.find("ALIAS") {
				let alias_part = rest[alias_pos + 5..].trim();
				let alias_name = alias_part.split_whitespace().next().unwrap_or("");
				if !alias_name.is_empty() {
					name = alias_name.to_string();
				}
			}

			let is_readonly = !rest.contains("WRITE");
			let prop_type = match raw_type {
				"QString" | "String" | "&str" => "string",
				"bool" => "bool",
				"i32" | "u32" | "i64" | "u64" | "usize" | "isize" => "int",
				"f32" | "f64" => "double",
				"QVariantList" => "QVariantList",
				"QVariant" => "QVariant",
				other => other,
			}
			.to_string();

			properties.push(QmlProperty {
				name,
				prop_type,
				is_readonly,
			});
		}

		let mut signals = Vec::new();
		for cap in signal_re.captures_iter(&content) {
			let name = cap[1].to_string();
			signals.push(QmlSignal { name });
		}

		let mut methods = Vec::new();
		for cap in method_re.captures_iter(&content) {
			let name = cap[1].to_string();
			let raw_args = cap.get(2).map_or("", |m| m.as_str());
			let return_type = cap
				.get(3)
				.map_or("void".to_string(), |m| match m.as_str().trim() {
					"QString" | "String" => "string".to_string(),
					"bool" => "bool".to_string(),
					"i32" | "u32" => "int".to_string(),
					"f64" | "f32" => "double".to_string(),
					other => other.to_string(),
				});

			let mut args = Vec::new();
			let cleaned_args = raw_args.replace('\n', " ").replace('\t', " ");
			if !cleaned_args.trim().is_empty() {
				for arg_pair in cleaned_args.split(',') {
					let parts: Vec<&str> = arg_pair.split(':').collect();
					if parts.len() == 2 {
						let arg_name = parts[0].trim().trim_start_matches('_').to_string();
						let arg_type = match parts[1].trim() {
							"QString" | "String" | "&str" => "string",
							"bool" => "bool",
							"i32" | "u32" | "i64" | "u64" | "usize" | "isize" => "int",
							"f32" | "f64" => "double",
							"QVariantList" => "QVariantList",
							"QVariant" => "QVariant",
							_ => "var",
						};
						args.push((arg_name, arg_type.to_string()));
					}
				}
			}

			methods.push(QmlMethod {
				name,
				args,
				return_type,
			});
		}

		components.push(QmlComponent {
			name: struct_name,
			properties,
			signals,
			methods,
		});
	}

	let mut qmltypes = String::from("import QtQuick.tooling 1.2\n\nModule {\n");

	for comp in components {
		qmltypes.push_str("\tComponent {\n");
		qmltypes.push_str(&format!("\t\tname: \"{}\"\n", comp.name));
		qmltypes.push_str("\t\tprototype: \"QObject\"\n");
		qmltypes.push_str(&format!("\t\texports: [\"Hishell/{} 1.0\"]\n", comp.name));
		qmltypes.push_str("\t\texportMetaObjectRevisions: [256]\n\n");

		for prop in comp.properties {
			if prop.is_readonly {
				qmltypes.push_str(&format!(
					"\t\tProperty {{ name: \"{}\"; type: \"{}\"; isReadonly: true }}\n",
					prop.name, prop.prop_type
				));
			} else {
				qmltypes.push_str(&format!(
					"\t\tProperty {{ name: \"{}\"; type: \"{}\" }}\n",
					prop.name, prop.prop_type
				));
			}
		}

		for signal in comp.signals {
			qmltypes.push_str(&format!("\t\tSignal {{ name: \"{}\" }}\n", signal.name));
		}

		for method in comp.methods {
			qmltypes.push_str("\t\tMethod {\n");
			qmltypes.push_str(&format!("\t\t\tname: \"{}\"\n", method.name));
			qmltypes.push_str(&format!("\t\t\ttype: \"{}\"\n", method.return_type));

			for (arg_name, arg_type) in method.args {
				qmltypes.push_str(&format!(
					"\t\t\tParameter {{ name: \"{}\"; type: \"{}\" }}\n",
					arg_name, arg_type
				));
			}

			qmltypes.push_str("\t\t}\n");
		}

		qmltypes.push_str("\t}\n");
	}

	qmltypes.push_str("}\n");

	if let Some(parent) = Path::new(output_path).parent() {
		fs::create_dir_all(parent).expect("Failed to create QML module directory");
	}

	fs::write(output_path, qmltypes).expect("Failed to write plugins.qmltypes");
}
