use tauri::{AppHandle, Manager, WebviewUrl, WebviewWindowBuilder};

use crate::get_app_handle;

// region: Windows

pub fn open_main() {
    let app = get_app_handle();
    // Check if main window already exists.
    if let Some(window) = app.get_webview_window("main") {
        println!("Window - Showing main window.");
        window.show().unwrap();
        window.set_focus().ok();
        return;
    }

    println!("Window - Creating main window.");
    // Create main window.
    let window = WebviewWindowBuilder::new(
        app.app_handle(),
        "main",
        WebviewUrl::App("index.html".into()),
    )
    .title("Tooly")
    .inner_size(400.0, 600.0)
    .resizable(false)
    .visible(false)
    //.decorations(false)
    .build()
    .expect("Window - Failed to create main window");
    window.show().unwrap();
}

pub fn open_tray() {
    let app = get_app_handle();
    println!("Window - Creating tray window.");
    // TODO: Create tray window.
}

pub fn open_find_and_replace() {
    let app = get_app_handle();
    println!("Window - Creating find and replace window.");
    // TODO: Create find and replace window.
}

// endregion
