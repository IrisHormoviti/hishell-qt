//! The shipping frontend's view of the core action registry.
//!
//! `ActionManager.qml` keeps the menu widgets and their behaviour, but the
//! question of which actions apply to the current target is answered here: the
//! adapter mirrors the target directory, cursor, and selection into a core
//! [`Engine`] and returns the serialized [`ActionSpec`] list from
//! `Engine::actions`. Invoking an action dispatches `Command::Invoke` and turns
//! the resulting prompts, frontend requests, and job events back into signals
//! the QML side already knows how to render.

use std::path::{Path, PathBuf};

use hishell::action::descriptor;
use hishell::{
	ActionId, ActionRequest, Command, Effect, Engine, FocusCommand, FrontendRequest, MenuKind,
	PaneId, Prompt, Target,
};
use qmetaobject::prelude::*;

#[derive(QObject, Default)]
pub struct CoreActions {
	base: qt_base_class!(trait QObject),

	engine: Option<Engine>,
	location: String,

	/// A file operation submitted by `invoke` finished. `ok` is false when any
	/// path failed; the counts are what `JobOutcome` reports.
	job_finished: qt_signal!(id: String, ok: bool, succeeded: i32, failed: i32),
	/// The engine asked for the folder to be read again.
	reload_requested: qt_signal!(),
	/// The engine resolved an activation to another folder.
	navigate_requested: qt_signal!(path: String),
	/// Rename needs the frontend's text dialog.
	rename_requested: qt_signal!(path: String, suggested: String),
	/// Open With needs the frontend's application chooser.
	open_with_requested: qt_signal!(path: String),
	/// Destroy needs the frontend's irreversible-delete confirmation.
	destroy_requested: qt_signal!(paths_json: String),
	/// A `Type=Number` control needs its value dialog.
	number_requested: qt_signal!(path: String),
	/// The core has no launcher for this path; the frontend opens it.
	open_path_requested: qt_signal!(path: String),
	/// The View options sheet belongs to the frontend.
	view_settings_requested: qt_signal!(),
	/// The execution wrapper held a launch for confirmation.
	launch_confirmation_requested: qt_signal!(launch_id: String, warning: String),
	/// An action the core does not implement yet; the QML handler finishes it.
	frontend_action_requested: qt_signal!(id: String),
	/// An invocation failed before it produced an effect.
	action_failed: qt_signal!(id: String, message: String),

	/// Mirror the frontend's target into the core engine. Opening the
	/// engine is deferred until the first menu so a window start never
	/// pays for a second scan.
	sync: qt_method!(
		fn sync(&mut self, directory: String, focus: String, selection_json: String) -> bool {
			if directory.is_empty() {
				return false;
			}
			let path = PathBuf::from(&directory);
			if !path.is_dir() {
				return false;
			}
			if self.engine.is_none() || self.location != directory {
				match Engine::open(&path) {
					Ok(engine) => {
						self.engine = Some(engine);
						self.location = directory;
					}
					Err(error) => {
						self.action_failed(String::from("sync"), error.to_string());
						return false;
					}
				}
			}
			let Some(engine) = self.engine.as_mut() else {
				return false;
			};
			if !focus.is_empty() {
				let _ = engine.dispatch(Command::Focus(FocusCommand::Set {
					pane: PaneId(0),
					path: PathBuf::from(&focus),
				}));
			}
			let selected: Vec<String> = serde_json::from_str(&selection_json).unwrap_or_default();
			let ids: Vec<hishell::ItemId> = selected
				.iter()
				.filter_map(|path| engine.item_at(Path::new(path)).map(|item| item.id))
				.collect();
			let _ = engine.dispatch(Command::ClearSelection);
			if let Some((first, rest)) = ids.split_first() {
				let _ = engine.dispatch(Command::SelectOnly(*first));
				for id in rest {
					let _ = engine.dispatch(Command::ToggleSelection(*id));
				}
			}
			true
		}
	),

	/// Serialize the actions the core offers for one menu and target.
	actions_json: qt_method!(
		fn actions_json(&self, menu: String, target: String) -> String {
			let Some(engine) = &self.engine else {
				return String::from("[]");
			};
			let Some(menu) = menu_kind(&menu) else {
				return String::from("[]");
			};
			let Some(target) = target_kind(&target) else {
				return String::from("[]");
			};
			let actions: Vec<serde_json::Value> = engine
				.actions(&ActionRequest { menu, target })
				.into_iter()
				.map(|spec| {
					let descriptor = descriptor(spec.id);
					serde_json::json!({
						"id": spec.id.as_str(),
						"group": spec.group.id.0,
						"order": spec.group.order,
						"enabled": spec.enabled,
						"visible": spec.visible,
						"checked": spec.checked,
						"disabledReason": spec.disabled_reason.map(|reason| format!("{reason:?}")),
						"icon": descriptor.map(|descriptor| descriptor.icon_name).unwrap_or(""),
						"shortcut": descriptor
							.and_then(|descriptor| descriptor.default_shortcut)
							.unwrap_or(""),
						"i18n": descriptor.map(|descriptor| descriptor.i18n_key).unwrap_or(""),
					})
				})
				.collect();
			serde_json::to_string(&actions).unwrap_or_else(|_| String::from("[]"))
		}
	),

	/// Dispatch a core action and translate its effects into signals.
	invoke: qt_method!(
		fn invoke(&mut self, id: String) -> String {
			let Some(action) = ActionId::from_str(&id) else {
				self.action_failed(id, String::from("unknown action"));
				return String::from("{\"ok\":false}");
			};
			let Some(engine) = self.engine.as_mut() else {
				self.action_failed(id, String::from("no engine"));
				return String::from("{\"ok\":false}");
			};
			match engine.dispatch(Command::Invoke(action)) {
				Ok(outcome) => {
					let job = outcome.job.is_some();
					self.translate_effects(outcome.effects);
					serde_json::json!({ "ok": true, "job": job }).to_string()
				}
				Err(error) => {
					self.action_failed(id, error.to_string());
					String::from("{\"ok\":false}")
				}
			}
		}
	),

	/// Pump the engine's job pool and forward its events.
	poll: qt_method!(
		fn poll(&mut self) {
			let effects = self.engine.as_mut().map(|engine| engine.tick().effects);
			if let Some(effects) = effects {
				self.translate_effects(effects);
			}
		}
	),

	/// Rescan the mirrored folder, e.g. after the frontend changed it.
	refresh: qt_method!(
		fn refresh(&mut self) {
			let effects = self
				.engine
				.as_mut()
				.and_then(|engine| engine.dispatch(Command::Reload).ok())
				.map(|outcome| outcome.effects);
			if let Some(effects) = effects {
				self.translate_effects(effects);
			}
		}
	),

	location_path: qt_method!(
		fn location_path(&self) -> String {
			self.location.clone()
		}
	),
}

impl CoreActions {
	fn translate_effects(&mut self, effects: Vec<Effect>) {
		let mut reload = false;
		for effect in effects {
			match effect {
				Effect::Reload(_) => reload = true,
				Effect::Navigate(plan) => {
					self.navigate_requested(plan.to.to_string_lossy().into_owned());
				}
				Effect::Job(event) => match event {
					hishell::JobEvent::Started { .. } | hishell::JobEvent::Progress { .. } => {}
					hishell::JobEvent::Finished { id, outcome } => {
						reload = true;
						self.job_finished(
							id.0.to_string(),
							outcome.failed.is_empty(),
							outcome.succeeded.len() as i32,
							outcome.failed.len() as i32,
						);
					}
					hishell::JobEvent::Cancelled { .. } => reload = true,
				},
				Effect::Prompt(prompt) => self.translate_prompt(prompt),
				Effect::Frontend(request) => self.translate_frontend(request),
				Effect::Launch(outcome) => {
					if let hishell::LaunchOutcome::NeedsConfirmation { id, warning } = outcome {
						self.launch_confirmation_requested(
							id.0.to_string(),
							warning.item.to_string_lossy().into_owned(),
						);
					}
				}
				Effect::LaunchEvent(_) | Effect::FocusActivate(_) => {}
				_ => {}
			}
		}
		if reload {
			self.reload_requested();
		}
	}

	fn translate_prompt(&mut self, prompt: Prompt) {
		match prompt {
			Prompt::Rename { path, suggested } => {
				self.rename_requested(path.to_string_lossy().into_owned(), suggested);
			}
			Prompt::Destroy { paths } => {
				let paths: Vec<String> = paths
					.iter()
					.map(|path| path.to_string_lossy().into_owned())
					.collect();
				self.destroy_requested(
					serde_json::to_string(&paths).unwrap_or_else(|_| String::from("[]")),
				);
			}
			Prompt::OpenWith { path } => {
				self.open_with_requested(path.to_string_lossy().into_owned());
			}
			Prompt::Launch { id, warning } => {
				self.launch_confirmation_requested(
					id.0.to_string(),
					warning.item.to_string_lossy().into_owned(),
				);
			}
			Prompt::Number { path } => {
				self.number_requested(path.to_string_lossy().into_owned());
			}
		}
	}

	fn translate_frontend(&mut self, request: FrontendRequest) {
		match request {
			FrontendRequest::Action(action) => {
				self.frontend_action_requested(action.as_str().to_string());
			}
			FrontendRequest::OpenPath(path) => {
				self.open_path_requested(path.to_string_lossy().into_owned());
			}
			FrontendRequest::ViewSettings => self.view_settings_requested(),
			FrontendRequest::EditPath => {
				self.frontend_action_requested(String::from("edit-path"));
			}
			FrontendRequest::ShowShortcuts => {
				self.frontend_action_requested(String::from("show-shortcuts"));
			}
			FrontendRequest::ContextMenu => {
				self.frontend_action_requested(String::from("context-menu"));
			}
		}
	}
}

fn menu_kind(name: &str) -> Option<MenuKind> {
	match name {
		"main" => Some(MenuKind::Main),
		"context" => Some(MenuKind::Context),
		"edit" => Some(MenuKind::Edit),
		"new" => Some(MenuKind::New),
		"folder" => Some(MenuKind::FolderMenu),
		"view" => Some(MenuKind::View),
		"selection" => Some(MenuKind::SelectionBar),
		_ => None,
	}
}

fn target_kind(name: &str) -> Option<Target> {
	match name {
		"location" => Some(Target::Location),
		"focus" => Some(Target::Focus),
		"selection" => Some(Target::Selection),
		"auto" => Some(Target::Auto),
		_ => None,
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn the_adapter_serializes_core_actions_for_the_target() {
		let root =
			std::env::temp_dir().join(format!("hishell-core-actions-{}", std::process::id()));
		let _ = std::fs::remove_dir_all(&root);
		std::fs::create_dir_all(&root).unwrap();
		let file = root.join("a.txt");
		std::fs::write(&file, b"x").unwrap();

		let mut actions = CoreActions::default();
		assert!(actions.sync(
			root.to_string_lossy().into_owned(),
			file.to_string_lossy().into_owned(),
			String::from("[]"),
		));

		let focus = actions.actions_json(String::from("context"), String::from("auto"));
		assert!(focus.contains("\"id\":\"rename\""), "{focus}");
		assert!(focus.contains("\"id\":\"trash\""), "{focus}");
		assert!(focus.contains("\"enabled\":true"), "{focus}");

		let location = actions.actions_json(String::from("context"), String::from("location"));
		assert!(location.contains("\"id\":\"new-folder\""), "{location}");
		assert!(location.contains("\"id\":\"refresh\""), "{location}");
		assert!(!location.contains("\"id\":\"rename\""), "{location}");

		let missing = actions.actions_json(String::from("nope"), String::from("auto"));
		assert_eq!(missing, "[]");

		std::fs::remove_dir_all(root).unwrap();
	}
}
