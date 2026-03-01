use crate::get_app_handle;
use tauri::{
    AppHandle, Manager, TitleBarStyle, WebviewUrl, WebviewWindow, WebviewWindowBuilder,
    WindowEvent, Wry,
};
use tauri_plugin_positioner::{Position, WindowExt};

// region: Windows

pub fn open_main() {
    // Create main window.
    let _window = create("main", "Tooly", "index.html", |config| {
        config
            .inner_size(400.0, 600.0)
            .resizable(false)
            .visible(false)
            //.traffic_light_position(Position::Logical(LogicalPosition { x: 12.0, y: 150.0 }))
            .title_bar_style(TitleBarStyle::Overlay)
            .hidden_title(true)
            .transparent(true)
            .decorations(true)
            .skip_taskbar(true)
    });
}

pub fn open_tray() {
    if hide("tray") {
        return;
    }
    // TODO: Create tray window.
    let _window = create("tray", "Tooly", "index.html", |config| {
        config
            .inner_size(200.0, 300.0)
            .resizable(false)
            .decorations(false)
            .skip_taskbar(true)
            .visible_on_all_workspaces(true)
            .always_on_top(true)
    });
    // Reposition show and focus.
    let _ = _window.move_window(Position::TrayCenter);
}

pub fn open_find_and_replace() {
    // TODO: Create find and replace window.
    let _window = create("far", "Find and Replace", "index.html", |config| config);
}

// endregion

// region: Utils

/// Create a new window if not already created and show it.
pub fn create<F>(id: &str, title: &str, url: &str, config: F) -> WebviewWindow
where
    F: FnOnce(WebviewWindowBuilder<Wry, AppHandle>) -> WebviewWindowBuilder<Wry, AppHandle>,
{
    // Fetch app handle.
    let app = get_app_handle();
    // Check if window already exists.
    if let Some(window) = app.get_webview_window(id) {
        println!("Window - Showing '{}' window.", id);
        window.show().ok();
        window.set_focus().ok();
        return window;
    }
    println!("Window - Creating '{}' window.", id);
    let builder =
        WebviewWindowBuilder::new(app.app_handle(), id, WebviewUrl::App(url.into())).title(title);
    let builder = config(builder);
    let window = builder
        .build()
        .expect(&format!("Window - Failed to create '{}' window.", id));
    window.show().ok();
    window.set_focus().ok();
    window
}

// Hide window if already visible.
pub fn hide(id: &str) -> bool {
    // Fetch app handle.
    let app = get_app_handle();
    // Check if window already exists.
    if let Some(window) = app.get_webview_window(id) {
        if !window.is_visible().unwrap_or(false) {
            return false;
        }
        println!("Window - Hiding '{}' window.", id);
        window.hide().ok();
        return true;
    }
    false
}

// endregion
