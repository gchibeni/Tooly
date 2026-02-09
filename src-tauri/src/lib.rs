use std::{fs, sync::Mutex};
use tauri::{ActivationPolicy, App, AppHandle, Manager, Url, WindowEvent};
use tauri_plugin_deep_link::DeepLinkExt;
use tauri_plugin_global_shortcut::{
    Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutEvent, ShortcutState,
};
mod utils;
mod windows;
use once_cell::sync::OnceCell;

// region: Variables

static APP_HANDLE: OnceCell<Mutex<AppHandle>> = OnceCell::new();

pub fn get_app_handle() -> std::sync::MutexGuard<'static, AppHandle> {
    APP_HANDLE.get().unwrap().lock().unwrap()
}

// endregion

// region: Initialization

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let mut builder = tauri::Builder::default();

    // Initialize single instance plugin.
    builder = builder.plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
        // Redirect arguments from other instances to original instance.
        handle_reopen(app, _args);
    }));

    // Initialize deep-link plugin (tooly://).
    builder = builder.plugin(tauri_plugin_deep_link::init());

    // Initialize dialog plugin.
    builder = builder.plugin(tauri_plugin_dialog::init());

    // Initialize shell plugin.
    builder = builder.plugin(tauri_plugin_shell::init());

    // Initialize clipboard manager plugin.
    builder = builder.plugin(tauri_plugin_clipboard_manager::init());

    // Initialize global shortcut plugin.
    builder = builder.plugin(
        tauri_plugin_global_shortcut::Builder::new()
            .with_handler(move |_app, shortcut, event| {
                // Initialize shortcut handler.
                handle_shortcuts(shortcut, event);
            })
            .build(),
    );

    builder = builder.setup(|app| {
        // Set global app handle.
        APP_HANDLE
            .set(Mutex::new(app.app_handle().to_owned()))
            .unwrap();
        // Set app policy (Make it not show on dock/taskbar).
        set_policy(app, ActivationPolicy::Accessory);
        // Register all shortcuts (Make them dynamic).
        register_shortcuts(app);
        // Handle execution.
        let args: Vec<String> = std::env::args().collect();
        handle_execution(app.app_handle(), args);
        println!("Execution - App started successfully.");
        Ok(())
    });

    // Initialize window event handler.
    builder = builder.on_window_event(|window, event| {
        if let WindowEvent::CloseRequested { api, .. } = event {
            api.prevent_close();
            window.hide().unwrap();
        }
    });

    // Finalize build and run.
    builder
        .build(tauri::generate_context!())
        .expect("Error - Could not build/run application.")
        .run(|app, event| match event {
            tauri::RunEvent::Reopen { .. } => {
                // Handle app reopen event.
                handle_reopen(app, vec![]);
            }
            tauri::RunEvent::Opened { urls } => {
                for url in urls {
                    handle_url(url);
                }
            }
            _ => {}
        });
}

// endregion

// region: Handlers

/// Check if it is first time running the application.
fn is_first_run(app: &AppHandle) -> bool {
    let dir = app.path().app_data_dir().unwrap();
    let path = dir.join("config.json");
    if path.exists() {
        return false;
    }
    fs::create_dir_all(&dir).unwrap();
    fs::write(&path, "{}").unwrap();
    true
}

/// Handle execution logic and arguments.
fn handle_execution(app: &AppHandle, _args: Vec<String>) {
    // Check if it is first time running app.
    if is_first_run(app) {
        println!("Execution - First time running application.");
        windows::open_main();
    }
}

/// Handle app reopen event and single instance arguments.
fn handle_reopen(app: &AppHandle, _args: Vec<String>) {
    println!("Execution - App reopened (Arguments: '{:?}')", _args);
    windows::open_main();
}

/// Handle urls from deep-link plugin.
fn handle_url(url: Url) {
    println!("Execution - Opened via URL.");
    utils::execute_url(&url);
}

/// Handle global shortcut events.
fn handle_shortcuts(shortcut: &Shortcut, event: ShortcutEvent) {
    match event.state() {
        ShortcutState::Pressed => {
            println!("Shortcut ({:?}) Pressed!", shortcut);
        }
        ShortcutState::Released => {
            println!("Shortcut ({:?}) Released!", shortcut);
        }
    }
}

/// Register all global shortcuts.
fn register_shortcuts(app: &mut App) {
    // TODO: Make shortcuts dynamic via config.
    let ctrl_n_shortcut = Shortcut::new(Some(Modifiers::CONTROL), Code::KeyN);
    app.global_shortcut().register(ctrl_n_shortcut).unwrap();
}

/// Set application activation policy (macOS only).
fn set_policy(app: &mut App, policy: ActivationPolicy) {
    #[cfg(target_os = "macos")]
    {
        app.set_activation_policy(policy);
    }
}

// endregion
