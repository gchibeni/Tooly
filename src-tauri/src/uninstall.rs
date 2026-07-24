use std::process::Command;
use std::{env, fs, path::PathBuf};
use tauri::AppHandle;
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons};

// region: Constants

#[cfg(target_os = "macos")]
const FINDERSYNC_ID: &str = "com.gchibeni.tooly.findersync";
const FINDERSYNC_PROCESS: &str = "tooly-findersync";

// endregion

// region: Commands

/// Ask for confirmation, stop all Tooly processes and move the app to trash.
#[tauri::command]
pub fn uninstall_tooly(app: AppHandle) {
    trigger_uninstall(&app);
}

/// Start the uninstall flow on its own thread (the confirmation dialog blocks
/// and must not run on the main thread).
pub fn trigger_uninstall(app: &AppHandle) {
    let app = app.clone();
    std::thread::spawn(move || run_uninstall(app));
}

fn run_uninstall(app: AppHandle) {
    // Find the .app bundle (not available in dev builds).
    let Some(bundle) = bundle_path() else {
        eprintln!("Uninstall - No app bundle found (dev build?), aborting.");
        return;
    };
    // Ask the user for confirmation.
    let confirmed = app
        .dialog()
        .message("This will quit Tooly, remove its Finder extension and move the app to the Trash.")
        .title("Uninstall Tooly")
        .buttons(MessageDialogButtons::OkCancelCustom(
            "Uninstall".to_string(),
            "Cancel".to_string(),
        ))
        .blocking_show();
    if !confirmed {
        println!("Uninstall - Cancelled by user.");
        return;
    }
    println!("Uninstall - Removing '{}'.", bundle.display());
    // Stop the Finder Sync extension so the bundle is no longer "in use".
    stop_extension();
    // Trash the bundle and clean settings once this process exits.
    if let Err(e) = spawn_cleanup(&bundle) {
        eprintln!("Uninstall - Failed to start cleanup: {e}");
        return;
    }
    // Quit so the bundle can be moved to the trash.
    app.exit(0);
}

// endregion

// region: Utils

/// Return the .app bundle containing the running executable, if any.
fn bundle_path() -> Option<PathBuf> {
    let exe = env::current_exe().ok()?;
    exe.ancestors()
        .find(|p| p.extension().map_or(false, |e| e == "app"))
        .map(PathBuf::from)
}

/// Re-enable the Finder Sync extension in case a previous uninstall (or the
/// user) marked it as ignored in pluginkit.
pub fn ensure_extension_enabled() {
    #[cfg(target_os = "macos")]
    {
        Command::new("pluginkit")
            .args(["-e", "use", "-i", FINDERSYNC_ID])
            .status()
            .ok();
    }
}

/// Add the Tooly toolbar item to Finder's saved toolbar layout so users get
/// it without dragging it in manually. Runs on first launch only; relaunches
/// Finder when the layout actually changed.
pub fn ensure_toolbar_item() {
    #[cfg(target_os = "macos")]
    {
        let script = format!(
            r#"
            ObjC.import('Foundation');
            const domain = 'com.apple.finder';
            const key = 'NSToolbar Configuration Browser';
            const item = '{id}';
            const fallback = [
                'com.apple.finder.BACK', 'com.apple.finder.SWCH', 'NSToolbarSpaceItem',
                'com.apple.finder.ARNG', 'NSToolbarSpaceItem', 'com.apple.finder.SHAR',
                'com.apple.finder.LABL', 'com.apple.finder.ACTN', 'NSToolbarSpaceItem',
                'com.apple.finder.SRCH'
            ];
            const ud = $.NSUserDefaults.alloc.initWithSuiteName($(domain));
            const nat = ud.objectForKey($(key));
            const mdict = (nat && !nat.isNil()) ? nat.mutableCopy : $.NSMutableDictionary.alloc.init;
            let marr;
            const natArr = mdict.objectForKey($('TB Item Identifiers'));
            const defArr = mdict.objectForKey($('TB Default Item Identifiers'));
            if (natArr && !natArr.isNil()) {{ marr = natArr.mutableCopy; }}
            else if (defArr && !defArr.isNil()) {{ marr = defArr.mutableCopy; }}
            else {{ marr = $.NSMutableArray.alloc.init; for (const s of fallback) marr.addObject($(s)); }}
            let result = 'present';
            if (!marr.containsObject($(item))) {{
                marr.insertObjectAtIndex($(item), Math.min(1, marr.count));
                mdict.setObjectForKey(marr, $('TB Item Identifiers'));
                ud.setObjectForKey(mdict, $(key));
                ud.synchronize;
                result = 'added';
            }}
            result;
            "#,
            id = FINDERSYNC_ID
        );
        let output = Command::new("osascript")
            .args(["-l", "JavaScript", "-e", &script])
            .output();
        match output {
            Ok(out) if String::from_utf8_lossy(&out.stdout).trim() == "added" => {
                println!("Install - Toolbar item added, relaunching Finder.");
                Command::new("killall").arg("Finder").status().ok();
            }
            Ok(_) => println!("Install - Toolbar item already present."),
            Err(e) => eprintln!("Install - Failed to configure toolbar item: {e}"),
        }
    }
}

/// Disable and kill the Finder Sync extension.
fn stop_extension() {
    #[cfg(target_os = "macos")]
    {
        Command::new("pluginkit")
            .args(["-e", "ignore", "-i", FINDERSYNC_ID])
            .status()
            .ok();
        Command::new("pkill")
            .args(["-x", FINDERSYNC_PROCESS])
            .status()
            .ok();
    }
}

/// Spawn a detached script that waits for this process to exit, moves the
/// bundle to the trash and removes settings. The script runs from the temp
/// directory so it does not keep the bundle busy itself.
fn spawn_cleanup(bundle: &std::path::Path) -> std::io::Result<()> {
    let script_path = env::temp_dir().join("tooly-uninstall.sh");
    let script = format!(
        "#!/bin/bash\n\
        PID=\"$1\"; BUNDLE=\"$2\"\n\
        for _ in $(seq 1 150); do kill -0 \"$PID\" 2>/dev/null || break; sleep 0.2; done\n\
        kill -9 \"$PID\" 2>/dev/null\n\
        pkill -x '{process}' 2>/dev/null\n\
        NAME=\"$(basename \"$BUNDLE\")\"\n\
        DEST=\"$HOME/.Trash/$NAME\"\n\
        [ -e \"$DEST\" ] && DEST=\"$HOME/.Trash/${{NAME%.app}} $(date +%s).app\"\n\
        mv \"$BUNDLE\" \"$DEST\"\n\
        rm -rf \"$HOME/Library/Application Support/Tooly\"\n\
        rm -rf \"$HOME/Library/Application Support/com.gchibeni.tooly\"\n\
        rm -f \"$0\"\n",
        process = FINDERSYNC_PROCESS
    );
    fs::write(&script_path, script)?;
    Command::new("/bin/bash")
        .arg(&script_path)
        .arg(std::process::id().to_string())
        .arg(bundle.as_os_str())
        .spawn()?;
    Ok(())
}

// endregion
