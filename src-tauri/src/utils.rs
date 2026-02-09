use crate::windows;
use percent_encoding::percent_decode_str;
use serde::Deserialize;
use std::os::unix::fs::PermissionsExt;
use std::process::{Command, Stdio};
use std::time::Duration;
use std::{env, fs, path::Path, thread};
use tauri::Url;
use wait_timeout::ChildExt;

// region: Variables

const SCRIPT_TIMEOUT: u64 = 120;

// endregion

// region: Structs

#[derive(Debug, Deserialize, Clone)]
struct Payload {
    target: String,
    #[serde(rename = "targetType")]
    target_type: String,
    items: Vec<String>,
    action: String,
    #[serde(rename = "actionType")]
    action_type: String,
}

// endregion

// region: Execution & Commands

/// Handle command execution from urls parameters.
pub fn execute_url(url: &Url) {
    let mut current_command = String::new();
    let mut current_payload = String::new();
    // Fetch command from url.
    if let Some(command) = url.host_str() {
        current_command = command.to_string();
    }
    // Fetch payload from url query parameters.
    if let Some(payload) = url.query_pairs().find(|(k, _)| k == "payload") {
        current_payload =
            percent_decode_str(&percent_decode_str(&payload.1.to_string()).decode_utf8_lossy())
                .decode_utf8_lossy()
                .to_string();
    }
    // Perform command specific actions.
    match current_command.as_str() {
        "run" => run_command(&current_command, &current_payload),
        _ => println!("Execution - Unknown command: {}", current_command),
    }
}

/// Decode instructions from payload and run commands.
fn run_command(command: &str, payload: &str) {
    println!(
        "Command ({}) - Running with payload: '{}'",
        command, payload
    );

    let info = match load_payload(payload) {
        Ok(p) => p,
        Err(e) => {
            eprintln!("Command ({}) - Failed to load payload: {e}", command);
            return;
        }
    };

    match info.action_type.as_str() {
        "create" => action_create(&info),
        "app" => action_app(&info, false),
        "shortcut" => action_app(&info, true),
        "terminal" => action_terminal(&info),
        "script" => async_action_script(&info),
        "replace" => action_find_and_replace(&info),
        _ => {
            eprintln!(
                "Command ({}) - Unknown action type: {}",
                command, info.action_type
            );
        }
    }
}

// endregion

// region: Menu Actions

// Create file with name and content.
fn action_create(info: &Payload) {
    let parts: Vec<&str> = info.action.split('|').collect();
    let file_name = parts.get(0).unwrap_or(&"New File.txt");
    let file_content = parts.get(1).unwrap_or(&"");

    let target_path = Path::new(&info.target);
    let mut new_file_path = target_path.join(file_name);
    let mut counter = 1;

    while new_file_path.exists() {
        let file_stem = target_path
            .join(Path::new(file_name).file_stem().unwrap())
            .to_string_lossy()
            .to_string();
        let extension = Path::new(file_name)
            .extension()
            .map(|ext| format!(".{}", ext.to_string_lossy()))
            .unwrap_or_default();
        new_file_path = target_path.join(format!("{} ({}){}", file_stem, counter, extension));
        counter += 1;
    }

    match fs::write(&new_file_path, file_content) {
        Ok(_) => println!(
            "Action (create) - Created file '{}' in '{}'.",
            new_file_path.file_name().unwrap().to_string_lossy(),
            target_path.display()
        ),
        Err(e) => eprintln!(
            "Action (create) - Failed to create file in '{}': {}",
            target_path.display(),
            e
        ),
    }
    // TODO: Add support for windows & linux.
}

/// Run selected files with app.
fn action_app(info: &Payload, is_shortcut: bool) {
    let mut command = Command::new("");
    #[cfg(target_os = "macos")]
    {
        command = Command::new("open");
        command.arg("-a").arg(&info.action);
    }

    #[cfg(target_os = "windows")]
    {
        command = Command::new("cmd");
        command.args(["/C", "start", "", &info.action]);
    }

    #[cfg(target_os = "linux")]
    {
        command = Command::new("xdg-open");
        command.arg(&info.action);
    }

    if !is_shortcut {
        // ! This needs to be tested on Windows.
        for item in &info.items {
            command.arg(item);
        }
    }

    match command.spawn() {
        Ok(_) => println!("Action (app) - Launched app '{}'", info.action),
        Err(e) => eprintln!("Action (app) - Failed to launch app: {e}"),
    }
}

/// Run terminal command with selected files as arguments.
fn action_terminal(info: &Payload) {
    // Create a temporary script file.
    let temp_dir = env::temp_dir();
    let script_path = temp_dir.join("tooly.command");

    // Execute terminal for MacOS or Linux.
    #[cfg(not(target_os = "windows"))]
    {
        // Prepare the items as escaped arguments for the shell command.
        let items = info
            .items
            .iter()
            .map(|s| format!("'{}'", s.replace("'", "'\\''")))
            .collect::<Vec<_>>()
            .join(" ");
        // Prepare the script content.
        let script_content = format!(
            "#!/bin/bash\n\
            clear; cd \"{path}\"; set -- {args}; {script}\n\
            echo \"\nProcess finished. Press Enter to close.\"\n\
            read; clear",
            path = info.target,
            args = items,
            script = info.action
        );
        // Write script to file.
        fs::write(&script_path, script_content).ok();
        // Allow file to be executable.
        fs::set_permissions(&script_path, fs::Permissions::from_mode(0o755)).ok();
        #[cfg(target_os = "macos")]
        {
            // Execute script with default MacOS application or terminal.
            Command::new("open").arg(&script_path).spawn().ok();
        }
        #[cfg(target_os = "linux")]
        {
            // Execute script with default Linux application or terminal.
            Command::new("xdg-open").arg(&script_path).spawn().ok();
        }
    }

    // Execute terminal for Windows.
    #[cfg(target_os = "windows")]
    {
        // Prepare the items as separate arguments for the shell command.
        let items: Vec<&str> = info.items.iter().map(|s| s.as_str()).collect();
        // Prepare the script content.
        let script_content = format!(
            "@echo off\r\n\
            cls & cd /d \"{path}\" & {script}\r\n\
            echo Process finished. Press Enter to close.\r\n\
            pause >nul & cls\r\n",
            path = info.target,
            script = info.action
        );
        // Write script to file.
        fs::write(&script_path, script_content).ok();
        // Execute script with default Windows application or terminal.
        let script_path_str = script_path.to_string_lossy().to_string();
        let mut cmd_args = vec!["/C", "start", "cmd", "/K", &script_path_str];
        cmd_args.extend(items);
        Command::new("cmd").args(cmd_args).spawn().ok();
    }
}

/// Execute script with selected file as arguments.
fn async_action_script(info: &Payload) {
    // Run the script in a separate thread to avoid blocking & hanging.
    let info_clone: Payload = info.clone();
    thread::spawn(move || {
        action_script(&info_clone);
    });
}

/// Execute script with selected file as arguments with timeout protection and non-blocking execution.
fn action_script(info: &Payload) {
    let mut command;
    // Start cmd script with arguments from info..
    #[cfg(target_os = "windows")]
    {
        command = Command::new("cmd");
        command
            .arg("/C")
            .arg(&info.action)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());

        for item in &info.items {
            cmd.arg(item);
        }
    }
    // Start bash script with arguments from info.
    #[cfg(not(target_os = "windows"))]
    {
        command = Command::new("bash");
        command
            .arg("--noprofile")
            .arg("--norc")
            .arg("-c")
            .arg(&info.action)
            .arg("--")
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        for item in &info.items {
            command.arg(item);
        }
    }
    // Start script execution.
    let mut child = match command.spawn() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("Command (script) - Failed to execute script: {e}");
            return;
        }
    };
    // Start timeout protection to avoid hanging processes and ensure non-blocking execution.
    let timeout = Duration::from_secs(SCRIPT_TIMEOUT);
    match child.wait_timeout(timeout) {
        // Execution if it finished in time.
        Ok(Some(_status)) => {
            // Command exited → collect output
            let output = child.wait_with_output().unwrap();
            let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
            if !stdout.is_empty() {
                println!("Command (script) - Output: {}", stdout);
            }
            if !stderr.is_empty() {
                eprintln!("Command (script) - Error: {}", stderr);
            }
        }
        // Execution if timed out.
        Ok(None) => {
            // Kill the process and its children to prevent hanging.
            child.kill().ok();
            eprintln!("Command (script) - Execution took too long (timeout).");
        }
        // Execution if an error occurred while waiting.
        Err(e) => {
            eprintln!("Command (script) - Failed while waiting for command: {e}");
        }
    }
}

/// Find and replace in selected files names.
fn action_find_and_replace(info: &Payload) {
    // TODO: Implement find and replace in file names for macOS, windows and linux.
    windows::open_find_and_replace();
}

// endregion

// region: Utils

fn load_payload(path: &str) -> Result<Payload, Box<dyn std::error::Error>> {
    let json = fs::read_to_string(Path::new(path))?;
    let payload: Payload = serde_json::from_str(&json)?;
    Ok(payload)
}

// endregion
