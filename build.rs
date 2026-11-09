use std::env;
use std::path::PathBuf;
use std::process::Command;

fn qmake_query(key: &str) -> String {
	let qmake = env::var("QMAKE").unwrap_or_else(|_| String::from("qmake6"));
	let output = Command::new(qmake)
		.arg("-query")
		.arg(key)
		.output()
		.expect("run qmake6 -query");
	String::from_utf8_lossy(&output.stdout).trim().to_string()
}

fn main() {
	let headers = qmake_query("QT_INSTALL_HEADERS");
	let libexecs = qmake_query("QT_INSTALL_LIBEXECS");
	let moc = PathBuf::from(libexecs).join("moc");
	let out = PathBuf::from(env::var("OUT_DIR").unwrap());
	let moc_out = out.join("moc_draghelper.cpp");

	let moc_status = Command::new(&moc)
		.arg("native/draghelper.h")
		.arg("-o")
		.arg(&moc_out)
		.arg(format!("-I{}", headers))
		.arg("-Inative")
		.status()
		.expect("run moc");
	assert!(moc_status.success(), "moc failed");

	cc::Build::new()
		.cpp(true)
		.std("c++17")
		.include(&headers)
		.include(format!("{headers}/QtQuick"))
		.include("native")
		.files(["native/draghelper.cpp", moc_out.to_str().unwrap()])
		.compile("hishell_drag");

	println!("cargo:rustc-link-lib=Qt6Quick");
	println!("cargo:rerun-if-changed=native/draghelper.h");
	println!("cargo:rerun-if-changed=native/draghelper.cpp");
	println!("cargo:rerun-if-changed=build.rs");
}
