use std::fs;
use tauri::{ActivationPolicy, App, AppHandle, Manager, WebviewUrl, WindowEvent};
use tauri_plugin_deep_link::DeepLinkExt;
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons};
use tauri_plugin_global_shortcut::{
    Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutEvent, ShortcutState,
};

// region: Variables

// endregion

// region: Initialization

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let mut builder = tauri::Builder::default().plugin(tauri_plugin_clipboard_manager::init());

    // Initialize single instance plugin.
    builder = builder.plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
        // Redirect arguments from other instances to original instance.
        handle_reopen(app, _args);
    }));

    // Initialize deep-link plugin (tooly://).
    builder = builder.plugin(tauri_plugin_deep_link::init());

    // Initialize dialog plugin.
    builder = builder.plugin(tauri_plugin_dialog::init());

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
        // Set app policy (Make it not show on dock/taskbar).
        set_policy(app, ActivationPolicy::Accessory);
        // Register all shortcuts (Make them dynamic).
        register_shortcuts(app);
        // Handle execution.
        let args: Vec<String> = std::env::args().collect();
        handle_execution(app.app_handle(), args);
        // Confirm execution.
        println!("App started successfully");
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

/// Handle execution logic, arguments and deep-links.
fn handle_execution(app: &AppHandle, _args: Vec<String>) {
    // Check if it is first time running app.
    if is_first_run(app) {
        println!("Execution - First time running application.");
        open_main(app);
    }

    // Check if app was called via url and handle it.
    app.deep_link().on_open_url(|event| {
        for url in event.urls() {
            println!("URL: {}", url);
        }
    });
    // TODO: Finish.
}

/// Register all global shortcuts.
fn register_shortcuts(app: &mut App) {
    // TODO: Make shortcuts dynamic via config.
    let ctrl_n_shortcut = Shortcut::new(Some(Modifiers::CONTROL), Code::KeyN);
    app.global_shortcut().register(ctrl_n_shortcut).unwrap();
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

/// Handle app reopen event and single instance arguments.
fn handle_reopen(app: &AppHandle, _args: Vec<String>) {
    let _answer = app
        .dialog()
        .message("Tauri is Awesome")
        .title("Tauri is Awesome")
        .buttons(MessageDialogButtons::OkCancelCustom(
            "Absolutely".to_string(),
            "Totally".to_string(),
        ))
        .blocking_show();
}

/// Set application activation policy (macOS only).
fn set_policy(app: &mut App, policy: ActivationPolicy) {
    #[cfg(target_os = "macos")]
    {
        app.set_activation_policy(policy);
    }
}

// endregion

// region: Windows

pub fn open_main(app: &AppHandle) {
    // TODO: Create and open main window here.
    tauri::WebviewWindowBuilder::new(
        app,
        "main", // label
        WebviewUrl::App("index.html".into()),
    )
    .title("My App")
    .visible(true) // important for background apps
    .build()
    .unwrap();
    println!("OPEN MAIN WINDOW");
}

// endregion
