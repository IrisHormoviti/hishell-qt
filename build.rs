fn main() {
	println!("cargo:rerun-if-changed=src/");
	println!("cargo:rerun-if-changed=build.rs");

	// SAFETY: build scripts are single-threaded
	unsafe { std::env::set_var("QMAKE", "qmake6"); }

	cxx_qt_build::CxxQtBuilder::new_qml_module(
		cxx_qt_build::QmlModule::new("Hishell")
	)
	.files(&["src/bridge.rs"])
	.build()
	.export();
}