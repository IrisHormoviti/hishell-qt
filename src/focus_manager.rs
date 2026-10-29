use crate::gamepad::Input;
use once_cell::sync::Lazy;
use qmetaobject::{QUrl, QVariantList, prelude::*};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::Instant;

const FOCUS_BORDER_SVG: &str = include_str!("../theme/default/focus-border.svg");

/// File the host polls for the focused item, from `HISHELL_SESSION_FOCUS`.
/// Rewritten atomically on every change; the host (e.g. a top screen) renders
/// its icon and title.
fn focus_file() -> String {
	crate::session::focus_file()
}

static BORDER_SOURCES: Lazy<Mutex<HashMap<String, String>>> =
	Lazy::new(|| Mutex::new(HashMap::new()));

fn focus_border_svg() -> String {
	// Prefer the asset on disk so that edits show up without a rebuild, and
	// fall back to the copy baked into the binary for installed builds.
	let candidates = [
		PathBuf::from("theme/default/focus-border.svg"),
		PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("theme/default/focus-border.svg"),
	];
	for path in candidates {
		if let Ok(source) = fs::read_to_string(&path) {
			return source;
		}
	}

	FOCUS_BORDER_SVG.to_string()
}

/// The `<path>` element for one corner of the focus border, as SVG markup.
///
/// The border is drawn from the four `<path>` elements in the asset, in the
/// order they appear once `<defs>` is skipped: top-left, top-right,
/// bottom-right, bottom-left — the same order as [`CORNERS`]. Each element is
/// taken verbatim (its `d`, `transform`, fill and stroke as authored), so the
/// art can be filled or stroked and freely transformed; only the colour is
/// substituted. The constant [`CORNER_PATHS`] is used when the asset has no
/// usable outlines, so the border never disappears.
///
/// An asset may paint a whole group and leave the paths themselves bare. The
/// group is not part of the per-corner document, so that paint is moved onto
/// the path; without it the corner would come out unpainted.
fn corner_elements(source: &str) -> Vec<String> {
	let body = strip_defs(source);
	let group = group_paint(&body);
	let mut elements = Vec::new();
	let mut rest = body.as_str();
	while let Some(start) = rest.find("<path") {
		let after = &rest[start..];
		let Some(end) = after.find('>') else {
			break;
		};
		let element = &after[..end + 1];
		if element.contains("d=\"") {
			elements.push(inherit_paint(element, group.as_deref()));
		}
		rest = &after[end + 1..];
		if elements.len() == 4 {
			break;
		}
	}
	if elements.len() == 4 {
		elements
	} else {
		eprintln!(
			"hishell: the focus border asset has {} usable corners, drawing the default ones",
			elements.len()
		);
		CORNER_PATHS.iter().map(|s| s.to_string()).collect()
	}
}

/// The paint the first `<g>` of the document gives its paths, if it carries
/// one: the value of its `fill` or, failing that, its `stroke`.
fn group_paint(source: &str) -> Option<String> {
	let start = source.find("<g")?;
	let end = source[start..].find('>')? + start;
	let tag = &source[start..end];
	["fill", "stroke"]
		.into_iter()
		.find_map(|name| attribute(tag, name))
		.map(|value| value.to_string())
}

/// Give a path the paint of the group it was drawn in, when it carries none of
/// its own. The group is not part of the corner document, so the paint has to
/// travel with the path.
fn inherit_paint(element: &str, group: Option<&str>) -> String {
	let Some(group) = group else {
		return element.to_string();
	};
	if element.contains("fill=\"") || element.contains("stroke=\"") {
		return element.to_string();
	}
	element.replacen("<path", &format!("<path fill=\"{group}\""), 1)
}

/// The value of the named attribute in an element's opening tag.
fn attribute<'a>(tag: &'a str, name: &str) -> Option<&'a str> {
	let needle = format!(" {name}=\"");
	let start = tag.find(&needle)? + needle.len();
	let end = tag[start..].find('"')? + start;
	Some(&tag[start..end])
}

/// Whether the element already carries the named attribute. The name has to
/// match whole: `stroke-width` is not `stroke`.
fn has_attribute(element: &str, name: &str) -> bool {
	element.contains(&format!(" {name}=\""))
}

/// Drop the `<defs>...</defs>` section, where an editor keeps its named
/// gradients and path effects (they are not part of the drawing).
fn strip_defs(source: &str) -> String {
	let mut out = String::with_capacity(source.len());
	let mut rest = source;
	while let Some(start) = rest.find("<defs") {
		out.push_str(&rest[..start]);
		let after = &rest[start..];
		match after.find("</defs>") {
			Some(end) => rest = &after[end + "</defs>".len()..],
			None => return out,
		}
	}
	out.push_str(rest);
	out
}

/// Give a corner element the theme colour: an authored white/black fill or
/// stroke is replaced. An outline the asset left with no paint at all (a plain
/// `<path>` carrying only `d`, with the colour on a parent group) is stroked in
/// the colour instead, so both filled and stroked art follow the highlight.
fn paint(element: &str, color: &str) -> String {
	let text = recolour(element, color);
	let painted = text.contains("fill=\"")
		|| text.contains("stroke=\"")
		|| text.contains("fill:")
		|| text.contains("stroke:");
	if painted {
		return text;
	}
	// The outline carries no paint: stroke it in the colour instead. Only the
	// attributes the element does not already carry are added — a second
	// `stroke-width` would make the document invalid XML, Qt would refuse to
	// render it, and the border would disappear altogether.
	let mut extra = String::new();
	for (name, value) in [
		("fill", "none"),
		("stroke", color),
		("stroke-width", "7.5"),
		("stroke-linecap", "butt"),
		("stroke-linejoin", "bevel"),
	] {
		if !has_attribute(&text, name) {
			extra.push_str(&format!(" {name}=\"{value}\""));
		}
	}
	if extra.is_empty() {
		return text;
	}
	text.replacen("<path", &format!("<path{extra}"), 1)
}

/// The colour words an asset may paint with, longest first: `#ffffff` has to
/// be matched before `#fff`, or a white fill would be matched twice.
const COLOUR_WORDS: [&str; 6] = ["#ffffff", "#fff", "#000000", "#000", "white", "black"];

/// Replace every colour word in `text` with `color`.
///
/// The replacement is never looked at again, so a colour that is itself a
/// colour word — a white highlight — comes out as it went in, and not as the
/// nine-digit `#fffffffff` a second replacement would leave behind.
fn recolour(text: &str, color: &str) -> String {
	let mut out = String::with_capacity(text.len());
	let mut rest = text;
	loop {
		let mut hit: Option<(usize, usize)> = None;
		for word in COLOUR_WORDS {
			if let Some(start) = rest.find(word)
				&& hit.is_none_or(|(earliest, _)| start < earliest)
			{
				hit = Some((start, word.len()));
			}
		}
		let Some((start, len)) = hit else {
			out.push_str(rest);
			return out;
		};
		out.push_str(&rest[..start]);
		out.push_str(color);
		rest = &rest[start + len..];
	}
}

fn write_border_asset(color: &str) -> Option<String> {
	let color = if color.starts_with('#') && matches!(color.len(), 7 | 9) {
		color
	} else {
		"#ffffff"
	};

	let source = focus_border_svg();
	let directory = dirs::cache_dir()?.join("hishell");
	fs::create_dir_all(&directory).ok()?;

	// Keyed by content as well as colour, so editing the asset yields new files
	// and URLs, which also invalidates the image cache on the QML side.
	let digest = md5::compute(format!("{color}:{source}").as_bytes());
	let prefix = directory.join(format!("focus-border-{:x}", digest));

	// One document per corner, each a 32x32 viewBox of the quadrant holding a
	// single bracket. The QML side then draws four plain images at the corner
	// size. Clipping one raster into quadrants relied on sourceClipRect being in
	// the same coordinate space as the rasterised sourceSize, which is not the
	// case once the device pixel ratio is not 1 (e.g. under QT_SCALE_FACTOR): the
	// clip then only grabbed a fraction of the art and drew broken corners.
	let elements = corner_elements(&source);
	for (index, (x, y)) in CORNERS.iter().enumerate() {
		let path = prefix.with_file_name(format!(
			"{}-{}.svg",
			prefix.file_name().unwrap_or_default().to_string_lossy(),
			index
		));
		if !path.exists() {
			let element = paint(&elements[index], color);
			let corner = format!(
				"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\
				 <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"32\" height=\"32\" \
				 viewBox=\"{x} {y} 32 32\" fill=\"none\">\n\
				 {element}\n\
				 </svg>\n",
			);
			fs::write(&path, corner).ok()?;
		}
	}

	Some(format!("file://{}", prefix.to_string_lossy()))
}

/// Quadrant origin of each corner in the source document, in the order the QML
/// draws them: top-left, top-right, bottom-right, bottom-left.
const CORNERS: [(i32, i32); 4] = [(0, 0), (32, 0), (32, 32), (0, 32)];

/// The single bracket path of each corner, taken from the source document.
const CORNER_PATHS: [&str; 4] = [
	"M 8,27.744298 V 14 c 0,-4 2.000431,-6.0587208 6,-6 l 10.352255,0.1519897",
	"M 36.407692,8 H 50 c 4,0 5.977762,2.000062 6,6 l 0.07599,13.668303",
	"M 56,37.319628 V 50 c 0,4 -2,6 -6,6 H 36.255702",
	"M 24.048277,56 H 14 C 10,56 8,54 8,50 V 37.319627",
];

/// Focus state of one file view. A window hosts a pane per view, and each pane
/// keeps its own cursor so that only the pane the focus is in reacts.
#[derive(Clone, Default)]
struct Pane {
	paths: Vec<String>,
	// Visual grid cell of every path, set for free-placement views; empty for
	// the implicit row-major layouts.
	positions: Vec<(i32, i32)>,
	// Free-placement cursor cell (column, row). Free placement can have empty
	// cells, and with FocusEmptySlots the cursor may rest on one, so the cursor
	// is tracked by cell: `index` is the item occupying it, or -1 for an empty
	// cell. None outside free placement.
	cursor: Option<(i32, i32)>,
	// Extent of the free-placement grid, so empty cells can be navigated.
	grid_columns: i32,
	grid_rows: i32,
	// Whether the cursor may stop on an empty cell (FocusEmptySlots).
	empty_slots: bool,
	index: i32,
	active: bool,
	columns: i32,
	horizontal: bool,
	keyboard: bool,
	x: f64,
	y: f64,
	width: f64,
	height: f64,
}

impl Pane {
	fn count(&self) -> i32 {
		self.paths.len() as i32
	}

	/// Whether every path has a visual position to navigate by.
	fn has_positions(&self) -> bool {
		!self.positions.is_empty() && self.positions.len() == self.paths.len()
	}

	/// Item occupying a free-placement cell, or -1 when the cell is empty.
	fn item_at_cell(&self, column: i32, row: i32) -> i32 {
		self.positions
			.iter()
			.position(|&(c, r)| c == column && r == row)
			.map_or(-1, |index| index as i32)
	}

	/// The cursor cell in free placement, falling back to the focused item's.
	fn cursor_cell(&self) -> (i32, i32) {
		if let Some(cell) = self.cursor {
			return cell;
		}
		if self.has_positions() {
			let index = self.index.max(0) as usize;
			return self.positions.get(index).copied().unwrap_or((0, 0));
		}
		(0, 0)
	}

	/// The cursor is resting on an empty free-placement cell.
	fn on_empty_slot(&self) -> bool {
		self.has_positions() && self.empty_slots && self.index < 0 && self.cursor.is_some()
	}

	/// Point the cursor at a free-placement cell: focus the item there when one
	/// exists, otherwise rest on the empty cell.
	fn place_cursor(&mut self, column: i32, row: i32) {
		self.cursor = Some((column, row));
		self.index = self.item_at_cell(column, row);
		self.active = true;
	}

	/// Keep the cursor cell in step with the focused item.
	fn sync_cursor_to_index(&mut self) {
		if self.has_positions()
			&& self.index >= 0
			&& let Some(cell) = self.positions.get(self.index as usize)
		{
			self.cursor = Some(*cell);
		}
	}

	fn path(&self) -> String {
		if self.index < 0 {
			return String::new();
		}
		self.paths
			.get(self.index as usize)
			.cloned()
			.unwrap_or_default()
	}

	fn rows(&self) -> i32 {
		let count = self.count();
		if count == 0 {
			return 1;
		}
		if self.has_positions() {
			return self
				.positions
				.iter()
				.map(|(_, row)| row + 1)
				.max()
				.unwrap_or(1)
				.max(1);
		}
		let stride = self.columns.max(1);
		if self.horizontal {
			stride
		} else {
			(count + stride - 1) / stride
		}
	}

	fn grid_columns(&self) -> i32 {
		let count = self.count();
		if count == 0 {
			return 1;
		}
		if self.has_positions() {
			return self
				.positions
				.iter()
				.map(|(column, _)| column + 1)
				.max()
				.unwrap_or(1)
				.max(1);
		}
		let stride = self.columns.max(1);
		if self.horizontal {
			(count + stride - 1) / stride
		} else {
			stride
		}
	}

	fn row_column(&self) -> (i32, i32) {
		let count = self.count();
		if count == 0 {
			return (0, 0);
		}
		if self.has_positions() {
			// An empty-cell cursor has no index; report its cell.
			if let Some((column, row)) = self.cursor
				&& self.index < 0
			{
				return (row, column);
			}
			let index = self.index.clamp(0, count - 1);
			let (column, row) = self.positions[index as usize];
			return (row, column);
		}
		let stride = self.columns.max(1);
		let index = self.index.clamp(0, count - 1);
		if self.horizontal {
			(index % stride, index / stride)
		} else {
			(index / stride, index % stride)
		}
	}

	fn index_at(&self, row: i32, column: i32) -> i32 {
		let count = self.count();
		if count == 0 {
			return -1;
		}
		if self.has_positions() {
			// Enter at the item closest to the requested visual cell.
			let mut best = 0;
			let mut best_distance = i64::MAX;
			for (index, &(c, r)) in self.positions.iter().enumerate() {
				let distance = (r - row).abs() as i64 + (c - column).abs() as i64;
				if distance < best_distance {
					best_distance = distance;
					best = index as i32;
				}
			}
			return best;
		}
		let row = row.clamp(0, self.rows() - 1);
		let column = column.clamp(0, self.grid_columns() - 1);
		let stride = self.columns.max(1);
		let index = if self.horizontal {
			column * stride + row
		} else {
			row * stride + column
		};
		index.clamp(0, count - 1)
	}
}

#[derive(QObject, Default)]
pub struct FocusManager {
	base: qt_base_class!(trait QObject),

	// Mirror of the pane owning the focus, so QML bindings can stay simple.
	focus_active: qt_property!(bool; NOTIFY focus_changed),
	focused_index: qt_property!(i32; NOTIFY focus_changed),
	focused_path: qt_property!(String; NOTIFY focus_changed),
	item_count: qt_property!(i32; NOTIFY focus_changed),
	grid_columns: qt_property!(i32; NOTIFY focus_changed),
	// Free-placement cursor cell, exposed so QML can draw the focus border on an
	// empty cell (where there is no item to highlight).
	focus_on_empty: qt_property!(bool; NOTIFY focus_changed),
	focused_column: qt_property!(i32; NOTIFY focus_changed),
	focused_row: qt_property!(i32; NOTIFY focus_changed),
	focus_status: qt_property!(String; READ get_focus_status NOTIFY focus_changed),
	window: qt_property!(QVariant),
	view_focused: qt_property!(bool; NOTIFY focus_changed),
	current_pane: qt_property!(i32; NOTIFY focus_changed),
	/// True while a guest app owns the panels (the wrapper's suspend marker).
	/// ClamOS' launch transition: QML washes the window out to white and holds
	/// it until the app is on screen, then fades it out over the guest. The
	/// gamepad polling stops so the guest gets the buttons and no shell sounds
	/// leak into the game.
	suspended: qt_property!(bool; NOTIFY suspended_changed),
	/// True once the guest is on screen: QML fades its launch wash out over the
	/// guest and unmaps the window until it exits. Without the ClamOS wrapper
	/// neither marker ever exists and the shell behaves exactly as before.
	hidden: qt_property!(bool; NOTIFY suspended_changed),
	/// The guest's last bottom-screen frame, versioned so QML reloads it. On
	/// the way back from an app the shell shows it for a moment and fades to
	/// its own UI, so the panel never jumps. Empty when there is none.
	return_frame_url: qt_property!(QUrl; NOTIFY suspended_changed),
	/// Bumped whenever the set of items whose app is suspended changes, so QML
	/// re-evaluates the per-item "active" marks.
	active_revision: qt_property!(i32; NOTIFY suspended_changed),

	focus_changed: qt_signal!(),
	suspended_changed: qt_signal!(),
	accept_requested: qt_signal!(),
	cancel_requested: qt_signal!(),
	menu_requested: qt_signal!(),
	select_requested: qt_signal!(),
	directory_menu_requested: qt_signal!(),
	quit_requested: qt_signal!(),

	panes: Vec<(i32, Pane)>,
	next_id: i32,
	current: i32,
	// Last document published to the top screen, for change detection.
	published_focus: String,
	// Saved focus to re-apply once a file view loads it, and whether the saved
	// session has already been consulted (only the shell's own first view
	// restores it).
	pending_focus: Option<String>,
	restore_loaded: bool,
	// Items whose app is currently suspended, refreshed when the session
	// markers change (which is exactly when the set can change).
	active_items: Vec<String>,
	// Whether a launched app has taken the gamepad (the input-grab marker), for
	// change detection; the shell then drops pad input but keeps drawing.
	input_grabbed: bool,
	// Last active-set revision read from the host, and whether it has ever been
	// read. The first poll must query even when the host starts with an empty
	// set, so persisted suspended entries are marked at boot.
	active_marker: String,
	active_loaded: bool,

	register_pane: qt_method!(
		fn register_pane(&mut self) -> i32 {
			self.next_id += 1;
			let id = self.next_id;
			self.panes.push((id, Pane::default()));
			if self.current == 0 {
				self.current = id;
			}
			self.sync();
			id
		}
	),

	release_pane: qt_method!(
		fn release_pane(&mut self, id: i32) {
			self.panes.retain(|(pane_id, _)| *pane_id != id);
			if self.current == id {
				self.current = self.panes.first().map_or(0, |(pane_id, _)| *pane_id);
			}
			self.sync();
		}
	),

	set_pane_items: qt_method!(
		fn set_pane_items(&mut self, id: i32, paths: QVariantList, columns: i32) {
			let Some(entry) = self.panes.iter().position(|(pane_id, _)| *pane_id == id) else {
				return;
			};

			let previous_path = self.panes[entry].1.path();
			let was_active = self.panes[entry].1.active;

			let mut list = Vec::new();
			for path in &paths {
				let value = path.to_qstring().to_string();
				if !value.is_empty() {
					list.push(value);
				}
			}

			let pane = &mut self.panes[entry].1;
			pane.paths = list;
			pane.columns = columns.max(1);

			if pane.paths.is_empty() {
				pane.active = false;
				pane.index = -1;
				pane.cursor = None;
			} else {
				let count = pane.count();
				let was_empty = pane.index < 0 && pane.cursor.is_some();
				let preserved = pane.paths.iter().position(|path| *path == previous_path);
				pane.index = match preserved {
					Some(index) => index as i32,
					None if was_empty => -1,
					None => pane.index.clamp(0, count - 1),
				};
				pane.active = was_active;
				if pane.index >= 0 {
					pane.sync_cursor_to_index();
				}
			}

			self.sync();
		}
	),

	set_pane_columns: qt_method!(
		fn set_pane_columns(&mut self, id: i32, columns: i32) {
			let Some(pane) = self.pane_mut(id) else {
				return;
			};
			let columns = columns.max(1);
			if pane.columns == columns {
				return;
			}
			pane.columns = columns;
			self.sync();
		}
	),

	set_pane_positions: qt_method!(
		fn set_pane_positions(&mut self, id: i32, positions_json: String) {
			let Some(pane) = self.pane_mut(id) else {
				return;
			};
			pane.positions.clear();
			if positions_json.is_empty() {
				return;
			}
			if let Ok(value) = serde_json::from_str::<serde_json::Value>(&positions_json)
				&& let Some(entries) = value.as_array()
			{
				for entry in entries {
					let column =
						entry.get("c").and_then(|value| value.as_i64()).unwrap_or(0) as i32;
					let row = entry.get("r").and_then(|value| value.as_i64()).unwrap_or(0) as i32;
					pane.positions.push((column, row));
				}
			}

			if pane.index >= 0 {
				pane.sync_cursor_to_index();
			} else if let Some((column, row)) = pane.cursor {
				// An empty-cell cursor follows the grid when it shrinks.
				pane.cursor = Some((
					column.clamp(0, (pane.grid_columns - 1).max(0)),
					row.clamp(0, (pane.grid_rows - 1).max(0)),
				));
			}
		}
	),

	set_pane_grid: qt_method!(
		fn set_pane_grid(&mut self, id: i32, columns: i32, rows: i32) {
			let Some(pane) = self.pane_mut(id) else {
				return;
			};
			pane.grid_columns = columns.max(1);
			pane.grid_rows = rows.max(1);
			if let Some((column, row)) = pane.cursor {
				pane.cursor = Some((
					column.min(pane.grid_columns - 1),
					row.min(pane.grid_rows - 1),
				));
			}
			self.sync();
		}
	),

	set_pane_empty_slots: qt_method!(
		fn set_pane_empty_slots(&mut self, id: i32, enabled: bool) {
			let Some(pane) = self.pane_mut(id) else {
				return;
			};
			if pane.empty_slots == enabled {
				return;
			}
			pane.empty_slots = enabled;
			if enabled {
				pane.sync_cursor_to_index();
			} else if pane.index < 0 {
				// Turning empty slots off while resting on one: fall back to the
				// first item.
				pane.index = if pane.count() > 0 { 0 } else { -1 };
				pane.sync_cursor_to_index();
			}
			self.sync();
		}
	),

	set_pane_horizontal: qt_method!(
		fn set_pane_horizontal(&mut self, id: i32, horizontal: bool) {
			if let Some(pane) = self.pane_mut(id) {
				pane.horizontal = horizontal;
			}
		}
	),

	set_pane_geometry: qt_method!(
		fn set_pane_geometry(&mut self, id: i32, x: f64, y: f64, width: f64, height: f64) {
			if let Some(pane) = self.pane_mut(id) {
				pane.x = x;
				pane.y = y;
				pane.width = width;
				pane.height = height;
			}
		}
	),

	set_pane_keyboard: qt_method!(
		fn set_pane_keyboard(&mut self, id: i32, keyboard: bool) {
			if let Some(pane) = self.pane_mut(id) {
				pane.keyboard = keyboard;
			}
			self.sync();
		}
	),

	activate_pane: qt_method!(
		fn activate_pane(&mut self, id: i32) {
			if self.pane(id).is_none() {
				return;
			}
			self.current = id;
			if let Some(pane) = self.pane_mut(id) {
				pane.keyboard = true;
			}
			self.sync();
		}
	),

	/// Persist the cursor for the next start. Called after the cursor stops
	/// moving, not on every step: the session file is a disk write.
	persist_focus: qt_method!(
		fn persist_focus(&self) {
			crate::session::save_focus(&self.focused_path);
		}
	),

	/// Publish the focused item for the top screen. Called a moment after the
	/// cursor settles: the document needs the item's title and icon, which are
	/// not free, and the top screen polls at 200 ms anyway.
	publish_focus_now: qt_method!(
		fn publish_focus_now(&mut self) {
			self.publish_focus();
		}
	),

	/// Re-read the wrapper's active/suspended items now. Used after Quit,
	/// where the host's active-revision marker may not exist at all (a host
	/// that only ever reports one set would otherwise keep the glow forever).
	refresh_active_items: qt_method!(
		fn refresh_active_items(&mut self) {
			self.active_items = crate::launch::active_items();
			self.active_revision = self.active_revision.wrapping_add(1);
			self.suspended_changed();
		}
	),

	set_pane_focus_path: qt_method!(
		fn set_pane_focus_path(&mut self, id: i32, path: String) -> bool {
			let found = self
				.pane(id)
				.and_then(|pane| pane.paths.iter().position(|entry| *entry == path));
			match found {
				Some(index) => {
					self.set_index(id, index as i32);
					true
				}
				None => false,
			}
		}
	),

	set_pane_active: qt_method!(
		fn set_pane_active(&mut self, id: i32, active: bool) {
			if let Some(pane) = self.pane_mut(id) {
				pane.active = active;
				if pane.index < 0 && pane.count() > 0 {
					pane.index = 0;
				}
			}
			self.sync();
		}
	),

	clear_pane: qt_method!(
		fn clear_pane(&mut self, id: i32) {
			if let Some(pane) = self.pane_mut(id) {
				pane.active = false;
				pane.index = -1;
				pane.cursor = None;
			}
			self.sync();
		}
	),

	focus_first: qt_method!(
		fn focus_first(&mut self) {
			let id = self.current;
			let index = self.pane(id).and_then(|pane| {
				if pane.has_positions() {
					visual_edge(&pane.positions, true)
				} else if pane.count() > 0 {
					Some(0)
				} else {
					None
				}
			});
			if let Some(index) = index {
				self.set_index(id, index as i32);
			}
		}
	),

	focus_last: qt_method!(
		fn focus_last(&mut self) {
			let id = self.current;
			let index = self.pane(id).and_then(|pane| {
				if pane.has_positions() {
					visual_edge(&pane.positions, false)
				} else if pane.count() > 0 {
					Some(pane.count() as usize - 1)
				} else {
					None
				}
			});
			if let Some(index) = index {
				self.set_index(id, index as i32);
			}
		}
	),

	move_focus: qt_method!(
		fn move_focus(&mut self, direction: String) -> bool {
			self.step(direction.as_str())
		}
	),

	/// Whether the item has an app that is currently suspended — the file view
	/// marks those. QML re-evaluates this when `active_revision` changes.
	is_item_active: qt_method!(
		fn is_item_active(&self, path: String) -> bool {
			let path = path.to_string();
			self.active_items.iter().any(|item| *item == path)
		}
	),

	poll_gamepad: qt_method!(
		fn poll_gamepad(&mut self) {
			// While a guest owns the panels the shell is suspended: report the
			// state (QML washes to white, then fades out and unmaps on the hide
			// marker) and stop consuming the buttons, so the app gets them and
			// no shell sounds leak into the game.
			let suspended = crate::session::suspended();
			let hidden = crate::session::hidden();
			let grabbed = crate::session::input_grabbed();
			let return_frame = bottom_shot_url();
			if suspended != self.suspended
				|| hidden != self.hidden
				|| grabbed != self.input_grabbed
				|| return_frame != self.return_frame_url
			{
				let was_paused = self.suspended || self.hidden || self.input_grabbed;
				self.suspended = suspended;
				self.hidden = hidden;
				self.input_grabbed = grabbed;
				self.return_frame_url = return_frame;
				self.suspended_changed();

				// Coming back from a guest: everything pressed while it owned
				// the panels is stale, and a button still held at the moment of
				// the hand-back must not be treated as a fresh press. Drop it
				// all, or the app that was just closed launches again.
				if was_paused && !(suspended || hidden || grabbed) {
					crate::gamepad::discard();
				}
			}
			// The host bumps this whenever its suspended set changes (and the
			// compositor touches it at boot when it restores entries). The
			// first poll always runs so a shell that starts after a reboot
			// marks the persisted entries without waiting for a marker change.
			let active_marker = crate::session::active_revision();
			if !self.active_loaded || active_marker != self.active_marker {
				self.active_loaded = true;
				self.active_marker = active_marker;
				let active = crate::launch::active_items();
				if active != self.active_items {
					self.active_items = active;
					self.active_revision += 1;
					self.suspended_changed();
				}
			}
			if suspended || hidden || grabbed {
				// The app owns the buttons; do not let presses pile up for the
				// shell to replay when it returns.
				crate::gamepad::discard();
				return;
			}

			let Some(input) = crate::gamepad::poll() else {
				return;
			};
			if !self.view_focused {
				if let Some(key) = qt_key(input) {
					crate::kde_bridge::send_key(key);
				}
				return;
			}

			match input {
				Input::Up | Input::Down | Input::Left | Input::Right => {
					let direction = String::from(input.as_str());
					self.step(direction.as_str());
				}
				Input::Accept => self.accept_requested(),
				Input::Cancel => self.cancel_requested(),
				Input::Menu => self.menu_requested(),
				Input::Select => self.select_requested(),
				Input::Directory => self.directory_menu_requested(),
				Input::Quit => self.quit_requested(),
			}
		}
	),

	border_source: qt_method!(
		fn border_source(&self, color: String) -> String {
			let color = color.to_string();
			if let Ok(cache) = BORDER_SOURCES.lock()
				&& let Some(source) = cache.get(&color)
			{
				return source.clone();
			}

			let source = write_border_asset(&color).unwrap_or_default();
			if let Ok(mut cache) = BORDER_SOURCES.lock() {
				cache.insert(color, source.clone());
			}
			source
		}
	),
}

impl FocusManager {
	fn pane(&self, id: i32) -> Option<&Pane> {
		self.panes
			.iter()
			.find(|(pane_id, _)| *pane_id == id)
			.map(|(_, pane)| pane)
	}

	fn pane_mut(&mut self, id: i32) -> Option<&mut Pane> {
		self.panes
			.iter_mut()
			.find(|(pane_id, _)| *pane_id == id)
			.map(|(_, pane)| pane)
	}

	/// Copies the focused pane into the mirrored properties and notifies QML.
	fn sync(&mut self) {
		// The saved session is consulted once, before any view has items: the
		// saved item is then re-applied by the first pane that loads it, no
		// matter when the pane registers or its model arrives.
		if !self.restore_loaded {
			self.restore_loaded = true;
			if self.panes.iter().all(|(_, pane)| pane.paths.is_empty()) {
				self.pending_focus = crate::session::startup_focus();
			}
		}
		if let Some(pending) = self.pending_focus.clone() {
			let found = self
				.panes
				.iter_mut()
				.find(|(_, pane)| pane.paths.iter().any(|path| *path == pending));
			if let Some((id, pane)) = found {
				let index = pane
					.paths
					.iter()
					.position(|path| *path == pending)
					.unwrap_or(0);
				pane.index = index as i32;
				pane.active = true;
				self.current = *id;
				self.pending_focus = None;
			}
		}

		let current = self.current;
		let keyboard = self.panes.iter().any(|(_, pane)| pane.keyboard);

		let (active, index, path, count, columns, column, row, on_empty) = match self.pane(current)
		{
			Some(pane) => {
				let on_empty = pane.on_empty_slot();
				let (column, row) = if on_empty {
					pane.cursor.map_or((-1, -1), |(c, r)| (c, r))
				} else {
					(-1, -1)
				};
				(
					pane.active && (pane.index >= 0 || on_empty),
					pane.index,
					pane.path(),
					pane.count(),
					pane.columns.max(1),
					column,
					row,
					on_empty,
				)
			}
			None => (false, -1, String::new(), 0, 1, -1, -1, false),
		};

		self.focus_active = active;
		self.focused_index = index;
		self.focused_path = path;
		self.item_count = count;
		self.grid_columns = columns;
		self.focus_on_empty = on_empty;
		self.focused_column = column;
		self.focused_row = row;
		self.current_pane = current;
		self.view_focused = keyboard;

		let signal_start = Instant::now();
		self.focus_changed();
		let signal_time = signal_start.elapsed();
		if crate::file_manager::perf_mode() == 5 {
			eprintln!(
				"hishell-perf: sync signal {} path {}",
				signal_time.as_micros(),
				self.focused_path
			);
		}
	}

	/// Publishes the focused item for the top screen: title and icon, resolved
	/// the same way the model resolves them (`directory::get_item_title` /
	/// `get_icon`), so both screens always agree. The document is compared as a
	/// whole, so a thumbnail finishing in the background republishes too, and
	/// the file is only rewritten when something actually changed. An empty
	/// focus publishes empty fields, which the top screen shows as no card.
	fn publish_focus(&mut self) {
		let path = self.focused_path.clone();
		let (title, icon, comment, banner) = if path.is_empty() {
			(String::new(), String::new(), String::new(), None)
		} else {
			// Use a thumbnail that already exists (the file view requests the
			// visible ones). Requesting one here queued a new job on every
			// cursor move, which competed with the shell while the user was
			// stepping through a folder; a miss keeps the themed icon.
			let thumbnail = crate::thumbnailer::result_for(&path);
			let icon = thumbnail.unwrap_or_else(|| crate::directory::get_icon(&path));
			let banner = crate::topscreen::banner_for(Path::new(&path), &icon);
			(
				crate::directory::get_item_title(Path::new(&path)),
				icon,
				crate::directory::get_item_comment(Path::new(&path)),
				banner,
			)
		};
		let document = serde_json::json!({
			"title": title,
			"comment": comment,
			"icon": icon,
			"path": path,
			"model": banner.as_ref().map(|banner| banner.model.as_str()).unwrap_or(""),
			"model_icon_texture": banner
				.as_ref()
				.and_then(|banner| banner.icon_texture.as_deref())
				.unwrap_or(""),
			"model_icon": banner
				.as_ref()
				.and_then(|banner| banner.icon_art.as_deref())
				.unwrap_or(""),
			"model_scale": banner.as_ref().map_or(1.0, |banner| banner.scale),
			"model_animate": banner.as_ref().map_or(true, |banner| banner.animate),
		})
		.to_string();
		if document == self.published_focus {
			return;
		}
		self.published_focus = document.clone();

		let target = focus_file();
		if target.is_empty() {
			return;
		}
		if let Some(parent) = Path::new(&target).parent() {
			let _ = fs::create_dir_all(parent);
		}
		// Write-and-rename so a poll never sees a half-written file.
		let temporary = PathBuf::from(format!("{target}.tmp"));
		if fs::write(&temporary, document).is_ok() {
			let _ = fs::rename(&temporary, target);
		}
	}

	/// Nearest pane lying on the given side of the one the focus is leaving.
	fn neighbour(&self, from_id: i32, from: &Pane, direction: &str) -> Option<i32> {
		let overlaps = |a: f64, a_end: f64, b: f64, b_end: f64| a < b_end - 1.0 && b < a_end - 1.0;
		let from_x_end = from.x + from.width;
		let from_y_end = from.y + from.height;
		let mut best: Option<(f64, i32)> = None;

		for (id, pane) in &self.panes {
			if *id == from_id || pane.count() == 0 {
				continue;
			}
			let x_end = pane.x + pane.width;
			let y_end = pane.y + pane.height;

			let (eligible, gap, here, there) = match direction {
				"left" => (
					x_end <= from.x + 1.0 && overlaps(pane.y, y_end, from.y, from_y_end),
					from.x - x_end,
					from.y + from.height / 2.0,
					pane.y + pane.height / 2.0,
				),
				"right" => (
					pane.x >= from_x_end - 1.0 && overlaps(pane.y, y_end, from.y, from_y_end),
					pane.x - from_x_end,
					from.y + from.height / 2.0,
					pane.y + pane.height / 2.0,
				),
				"up" => (
					y_end <= from.y + 1.0 && overlaps(pane.x, x_end, from.x, from_x_end),
					from.y - y_end,
					from.x + from.width / 2.0,
					pane.x + pane.width / 2.0,
				),
				"down" => (
					pane.y >= from_y_end - 1.0 && overlaps(pane.x, x_end, from.x, from_x_end),
					pane.y - from_y_end,
					from.x + from.width / 2.0,
					pane.x + pane.width / 2.0,
				),
				_ => continue,
			};

			if !eligible {
				continue;
			}
			// Prefer the pane best aligned with the one being left, then the
			// smallest gap.
			let distance = (there - here).abs() * 1000.0 + gap.abs();
			if best.is_none_or(|(best_distance, _)| distance < best_distance) {
				best = Some((distance, *id));
			}
		}

		best.map(|(_, id)| id)
	}

	fn set_index(&mut self, id: i32, index: i32) {
		let Some(pane) = self.pane_mut(id) else {
			return;
		};
		let count = pane.count();
		if count == 0 {
			return;
		}
		pane.index = index.clamp(0, count - 1);
		pane.active = true;
		pane.sync_cursor_to_index();
		self.sync();
	}

	/// Moves the cursor inside the focused pane, handing the focus over to a
	/// neighbouring pane once the cursor cannot move any further.
	fn step(&mut self, direction: &str) -> bool {
		let current_id = self.current;
		let Some(pane) = self.pane(current_id).cloned() else {
			return false;
		};
		let count = pane.count();
		if count == 0 {
			return false;
		}

		if !pane.active {
			// The first directional input reveals the focus where it already
			// sits instead of moving it right away.
			if pane.on_empty_slot() {
				let (column, row) = pane.cursor_cell();
				if let Some(entry) = self.pane_mut(current_id) {
					entry.place_cursor(column, row);
				}
				self.sync();
				return true;
			}
			let index = pane.index.max(0);
			self.set_index(current_id, index);
			return true;
		}

		let stride = pane.columns.max(1);
		let index = pane.index.clamp(0, count - 1);

		// Free placement with empty slots moves cell by cell, so the cursor can
		// rest on an empty cell. Falling off the grid hands off to a neighbour
		// below, the same as any other grid edge.
		let free_empty = pane.has_positions() && pane.empty_slots;
		if free_empty {
			let (column, row) = pane.cursor_cell();
			let (next_column, next_row) = match direction {
				"right" => (column + 1, row),
				"left" => (column - 1, row),
				"down" => (column, row + 1),
				"up" => (column, row - 1),
				_ => (column, row),
			};
			if next_column >= 0
				&& next_row >= 0
				&& next_column < pane.grid_columns
				&& next_row < pane.grid_rows
				&& (next_column, next_row) != (column, row)
			{
				if let Some(entry) = self.pane_mut(current_id) {
					entry.place_cursor(next_column, next_row);
				}
				self.sync();
				return true;
			}
		}

		let target = if free_empty {
			index
		} else if pane.has_positions() {
			nearest_in_direction(&pane.positions, index as usize, direction)
				.map_or(index, |target| target as i32)
		} else if pane.horizontal {
			// Items fill a column first, then move on to the next column.
			let row = index % stride;
			let column = index / stride;
			match direction {
				"down" => {
					if row + 1 < stride && index + 1 < count {
						index + 1
					} else {
						index
					}
				}
				"up" => {
					if row > 0 {
						index - 1
					} else {
						index
					}
				}
				"right" => {
					if index + stride < count {
						index + stride
					} else {
						index
					}
				}
				"left" => {
					if column > 0 {
						index - stride
					} else {
						index
					}
				}
				_ => index,
			}
		} else {
			// Items fill a row first, then move on to the next row.
			let row = index / stride;
			let column = index % stride;
			match direction {
				"right" => {
					if column + 1 < stride && index + 1 < count {
						index + 1
					} else {
						index
					}
				}
				"left" => {
					if column > 0 {
						index - 1
					} else {
						index
					}
				}
				"down" => {
					if index + stride < count {
						index + stride
					} else {
						index
					}
				}
				"up" => {
					if row > 0 {
						index - stride
					} else {
						index
					}
				}
				_ => index,
			}
		};

		if target != index {
			if let Some(entry) = self.pane_mut(current_id) {
				entry.index = target;
				entry.sync_cursor_to_index();
			}
			self.sync();
			return true;
		}

		let Some(neighbour_id) = self.neighbour(current_id, &pane, direction) else {
			return false;
		};
		let Some(neighbour) = self.pane(neighbour_id).cloned() else {
			return false;
		};

		let (row, column) = pane.row_column();
		let entry = match direction {
			"right" => neighbour.index_at(row, 0),
			"left" => neighbour.index_at(row, neighbour.grid_columns() - 1),
			"down" => neighbour.index_at(0, column),
			"up" => neighbour.index_at(neighbour.rows() - 1, column),
			_ => 0,
		};

		self.current = neighbour_id;
		if let Some(pane) = self.pane_mut(neighbour_id) {
			pane.index = entry.max(0);
			pane.active = true;
		}
		self.sync();
		true
	}

	fn get_focus_status(&self) -> String {
		// Only read by external introspection; QML does not use it. Building
		// this JSON on every cursor step was pure overhead, so it is built on
		// demand instead.
		let status = serde_json::json!({
			"active": self.focus_active,
			"index": self.focused_index,
			"path": self.focused_path,
			"count": self.item_count,
			"columns": self.grid_columns,
			"pane": self.current_pane,
		});
		serde_json::to_string(&status).unwrap_or_default()
	}
}

/// The host's return frame (the app's last bottom-screen frame) as a `file://`
/// URL carrying an mtime version, so QML reloads it after every app (the path
/// itself never changes). Empty when the host has not written one.
fn bottom_shot_url() -> QUrl {
	let path = crate::session::return_frame_path();
	if path.is_empty() {
		return QUrl::from(QString::from(""));
	}
	let Ok(metadata) = fs::metadata(&path) else {
		return QUrl::from(QString::from(""));
	};
	let version = metadata
		.modified()
		.ok()
		.and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
		.map(|elapsed| elapsed.as_millis())
		.unwrap_or(0);
	QUrl::from(QString::from(format!("file://{path}?v={version}")))
}

/// Nearest item in the given direction from `index`, by visual grid position.
/// Items closer to the movement axis win when the forward distance is similar.
fn nearest_in_direction(positions: &[(i32, i32)], index: usize, direction: &str) -> Option<usize> {
	let (column, row) = positions[index];
	let mut best: Option<(i64, usize)> = None;
	for (candidate, &(c, r)) in positions.iter().enumerate() {
		if candidate == index {
			continue;
		}
		let (forward, aside) = match direction {
			"right" => (c - column, (r - row).abs()),
			"left" => (column - c, (r - row).abs()),
			"down" => (r - row, (c - column).abs()),
			"up" => (row - r, (c - column).abs()),
			_ => return None,
		};
		if forward <= 0 {
			continue;
		}
		let score = forward as i64 + aside as i64 * 3;
		if best.is_none_or(|(best_score, _)| score < best_score) {
			best = Some((score, candidate));
		}
	}
	best.map(|(_, candidate)| candidate)
}

/// Index of the item at the top-left (or bottom-right) of the visual grid.
fn visual_edge(positions: &[(i32, i32)], first: bool) -> Option<usize> {
	let mut best: Option<(i32, i32, usize)> = None;
	for (index, &(column, row)) in positions.iter().enumerate() {
		let better = match best {
			None => true,
			Some((best_row, best_column, _)) => {
				if first {
					(row, column) < (best_row, best_column)
				} else {
					(row, column) > (best_row, best_column)
				}
			}
		};
		if better {
			best = Some((row, column, index));
		}
	}
	best.map(|(_, _, index)| index)
}

fn qt_key(input: Input) -> Option<i32> {
	const KEY_ESCAPE: i32 = 0x0100_0000;
	const KEY_RETURN: i32 = 0x0100_0004;
	const KEY_LEFT: i32 = 0x0100_0012;
	const KEY_UP: i32 = 0x0100_0013;
	const KEY_RIGHT: i32 = 0x0100_0014;
	const KEY_DOWN: i32 = 0x0100_0015;
	const KEY_SPACE: i32 = 0x20;

	match input {
		Input::Up => Some(KEY_UP),
		Input::Down => Some(KEY_DOWN),
		Input::Left => Some(KEY_LEFT),
		Input::Right => Some(KEY_RIGHT),
		Input::Accept => Some(KEY_RETURN),
		Input::Cancel => Some(KEY_ESCAPE),
		Input::Select => Some(KEY_SPACE),
		Input::Menu | Input::Directory | Input::Quit => None,
	}
}

#[cfg(test)]
mod tests {
	use super::{CORNER_PATHS, corner_elements, paint, recolour};

	/// A corner element as an asset that paints a group and leaves the paths
	/// bare, and that carries a stroke width of its own.
	const GROUP_PAINTED: &str = "<path d=\"m0 27.381v-9.7788z\" stroke-width=\"2.0252\"/>";

	fn count(text: &str, needle: &str) -> usize {
		text.matches(needle).count()
	}

	#[test]
	fn a_stroked_outline_never_gets_a_second_stroke_width() {
		// A second stroke-width makes the document invalid XML, and Qt then
		// refuses to render it: the border disappears altogether.
		let element = paint(GROUP_PAINTED, "#28b478");
		assert_eq!(count(&element, "stroke-width="), 1, "{element}");
	}

	#[test]
	fn a_painted_path_keeps_its_own_paint() {
		let element = paint("<path fill=\"#fff\" d=\"m0 0z\"/>", "#28b478");
		assert!(element.contains("fill=\"#28b478\""), "{element}");
		assert!(!element.contains("stroke="), "{element}");
	}

	#[test]
	fn a_white_highlight_stays_one_colour() {
		// "#fff" is a prefix of "#ffffff": replacing both in turn left the
		// nine-digit "#fffffffff", which is not a colour.
		let element = paint("<path fill=\"#ffffff\" d=\"m0 0z\"/>", "#ffffff");
		assert!(element.contains("fill=\"#ffffff\""), "{element}");
		assert!(!element.contains("ffffffff"), "{element}");
	}

	#[test]
	fn a_group_that_paints_its_paths_paints_them_still() {
		let source = "<g fill=\"#fff\"><path d=\"m0 0z\"/><path d=\"m1 1z\"/>\
			<path d=\"m2 2z\"/><path d=\"m3 3z\"/></g>";
		let elements = corner_elements(source);
		assert_eq!(elements.len(), 4);
		for element in elements {
			assert!(element.contains("fill=\"#fff\""), "{element}");
		}
	}

	#[test]
	fn an_asset_without_four_corners_falls_back_to_the_default_ones() {
		let elements = corner_elements("<path d=\"m0 0z\"/>");
		assert_eq!(elements, CORNER_PATHS);
	}

	#[test]
	fn recolouring_leaves_everything_else_alone() {
		assert_eq!(recolour("d=\"m0 0z\"", "#28b478"), "d=\"m0 0z\"");
		assert_eq!(recolour("fill=\"black\"", "#28b478"), "fill=\"#28b478\"");
	}
}
