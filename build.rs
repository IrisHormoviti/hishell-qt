fn main() {
	let mut config = cpp_build::Config::new();

	let qt_lib = pkg_config::probe_library("Qt6Core")
	.or_else(|_| pkg_config::probe_library("Qt5Core"))
	.expect("Could not find QtCore via pkg-config");

	for path in qt_lib.include_paths {
		config.include(path);
	}

	config.flag("-std=c++17");
	config.build("src/main.rs");
}
