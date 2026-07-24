//  Created by gchibeni.

import Cocoa
import FinderSync
import Foundation
import AppKit

class FinderSync: FIFinderSync {
    
    // MARK: - Initialization
    
    /// Initialize settings manager and watch folders.
    override init() {
        super.init()
        _ = SettingsManager.shared
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }
    
    // MARK: - Toolbar Item

    override var toolbarItemName: String { "Tooly" }

    override var toolbarItemToolTip: String { "Tooly actions for the selection or current folder." }

    /// Use the containing app's icon so the toolbar item always matches it.
    override var toolbarItemImage: NSImage {
        if let appURL = containingAppURL() {
            // Prefer the bundled glyph: template rendering only keeps the
            // alpha channel, and the system app icon is an opaque squircle.
            let glyphURL = appURL.appendingPathComponent("Contents/Resources/icon.png")
            let image = NSImage(contentsOf: glyphURL)
                ?? NSWorkspace.shared.icon(forFile: appURL.path)
            let fitted = aspectFitImage(image, size: 19)
            // Render as template so it adapts to the toolbar theme,
            // matching the app's menu bar icon.
            fitted.isTemplate = true
            return fitted
        }
        return NSImage(systemSymbolName: "hammer", accessibilityDescription: "Tooly") ?? NSImage()
    }

    /// Context resolved when the toolbar menu was opened, used as fallback in
    /// locations where Finder Sync gets no callbacks (File Provider volumes).
    private var toolbarSelection: [URL] = []
    private var toolbarTarget: URL?

    // MARK: - Construction

    /// Rebuild and return new context menu with dynamic items.
    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        print("Menu - Recreating menus")
        let menu = NSMenu(title: "")
        var groups: [String: NSMenu] = [:]
        let selected: [URL]
        if menuKind == .toolbarItemMenu {
            resolveToolbarContext()
            selected = toolbarSelection
        } else {
            toolbarSelection = []
            toolbarTarget = nil
            selected = FIFinderSyncController.default().selectedItemURLs() ?? []
        }
        
        createSeparator(menu, true)
        for orderedItem in SettingsManager.shared.itemOrder {
            if orderedItem == "%sprt%" { createSeparator(menu); continue }
            guard let item = SettingsManager.shared.menuItems[orderedItem] else { continue }
            // Check if item is enabled.
            if !item.enabled { continue }
            // Check target type.
            if !isTargetType(item, selected) { continue }
            // Create menu item.
            let menuItem = NSMenuItem(
                title: orderedItem,
                action: #selector(action(_:)),
                keyEquivalent: item.key
            )
            menuItem.representedObject = item
            menuItem.target = self
            
            // Change item icon.
            menuItem.image = getMenuIcon(item.iconType, item.icon)
            
            // Add item if no group.
            if item.group.isEmpty {
                menu.addItem(menuItem)
                continue
            }

            // Create sub and add item.
            let groupMenu: NSMenu
            if let existing = groups[item.group] {
                groupMenu = existing
            } else {
                let group = SettingsManager.shared.menuGroups[item.group] ?? MenuGroup(iconType: "", icon: "")
                let parentItem = NSMenuItem(title: item.group, action: nil, keyEquivalent: "")
                let submenu = NSMenu(title: item.group)
                parentItem.submenu = submenu
                parentItem.image = getMenuIcon(group.iconType, group.icon)
                menu.addItem(parentItem)
                groups[item.group] = submenu
                groupMenu = submenu
            }
            groupMenu.addItem(menuItem)
        }
        appendUninstallItem(menu, selected)
        return menu;
    }

    /// Append an "Uninstall Tooly" item when the selection is the app bundle
    /// this extension is running from.
    func appendUninstallItem(_ menu: NSMenu, _ selected: [URL]) {
        guard let appBundle = containingAppURL(),
              selected.count == 1,
              let selection = selected.first,
              selection.standardizedFileURL.path == appBundle.standardizedFileURL.path
        else { return }
        let item = NSMenuItem(
            title: "Uninstall",
            action: #selector(uninstallAction(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.image = getMenuIcon("symbol", "trash")
        menu.addItem(item)
    }

    /// Return the app bundle containing this extension.
    /// (tooly.app/Contents/PlugIns/tooly-findersync.appex → tooly.app)
    func containingAppURL() -> URL? {
        let url = Bundle.main.bundleURL
            .deletingLastPathComponent() // PlugIns
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() // tooly.app
        return url.pathExtension == "app" ? url : nil
    }

    /// Ask the main app to start its uninstall flow.
    @objc func uninstallAction(_ sender: NSMenuItem) {
        guard let url = URL(string: "tooly://uninstall") else { return }
        NSWorkspace.shared.open(url)
    }
    
    /// Return beauty icon  based on item type and path.
    /// - Parameters:
    ///   - type: Nature of icon: "app", "image" or "symbol".
    ///   - icon: Icon path or symbol name.
    func getMenuIcon(_ type:String, _ icon:String) -> NSImage? {
        var newImage: NSImage = NSImage();
        switch type {
        case "app":
            let appURL = URL(fileURLWithPath: icon)
            newImage = NSWorkspace.shared.icon(forFile: appURL.path)
            newImage.isTemplate = true
        case "image":
            newImage = NSImage(contentsOfFile: icon) ?? NSImage()
        case "symbol":
            let config = NSImage.SymbolConfiguration(paletteColors: [.textColor])
            newImage = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?.withSymbolConfiguration(config) ?? NSImage()
            newImage.isTemplate = true
        default:
            break
        }

        return aspectFitImage(newImage, size: 18)
    }
    
    /// Scales an icon uniformly to fit an aspect ratio.
    /// - Parameters:
    ///   - image: Image to be scaled.
    ///   - size: Desired max size.
    func aspectFitImage(_ image: NSImage, size: CGFloat) -> NSImage {
        let newImage = NSImage(size: NSSize(width: size, height: size))
        newImage.lockFocus()
        let imageSize = image.size
        let scale = min(size / imageSize.width, size / imageSize.height)
        let scaledSize = NSSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        let origin = NSPoint(
            x: (size - scaledSize.width) / 2,
            y: (size - scaledSize.height) / 2
        )
        image.draw(
            in: NSRect(origin: origin, size: scaledSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
        newImage.unlockFocus()
        newImage.isTemplate = image.isTemplate
        return newImage
    }
    
    /// Create a menu item separator.
    /// - Parameter header: Check if separator is a header.
    func createSeparator(_ menu: NSMenu, _ header: Bool = false) {
        if !SettingsManager.shared.separators { return }
        var item = NSMenuItem(title: "──", action: nil, keyEquivalent: "")
        if header { item = NSMenuItem(title: "─ Tooly", action: nil, keyEquivalent: "") }
        item.isEnabled = false
        menu.addItem(item)
    }
    
    // MARK: - Context Resolution

    /// Resolve the selection and current folder for the toolbar menu.
    /// Native Finder Sync calls work on regular volumes; inside File Provider
    /// folders (Dropbox, iCloud, OneDrive) they return nothing, so ask Finder
    /// itself via Apple Events. Falls back to the current folder when nothing
    /// is selected.
    func resolveToolbarContext() {
        let controller = FIFinderSyncController.default()
        var selection = controller.selectedItemURLs() ?? []
        var target = controller.targetedURL()
        if selection.isEmpty || target == nil {
            let queried = queryFinderContext()
            if selection.isEmpty { selection = queried.selection }
            if target == nil { target = queried.folder }
        }
        if selection.isEmpty, let folder = target {
            selection = [folder]
        }
        toolbarSelection = selection
        toolbarTarget = target
    }

    /// Ask Finder for the front window's folder and current selection.
    func queryFinderContext() -> (folder: URL?, selection: [URL]) {
        let script = """
        tell application "Finder"
            set folderPath to ""
            try
                set folderPath to POSIX path of (target of front window as alias)
            end try
            set output to folderPath
            repeat with f in (get selection)
                try
                    set output to output & linefeed & POSIX path of (f as alias)
                end try
            end repeat
            return output
        end tell
        """
        var error: NSDictionary?
        guard let result = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue else {
            if let error = error { print("Context - Finder query failed:", error) }
            return (nil, [])
        }
        // First line is always the folder (may be empty), the rest is the selection.
        let lines = result.components(separatedBy: "\n")
        let folder = lines.first.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        let selection = lines.dropFirst().filter { !$0.isEmpty }.map { URL(fileURLWithPath: $0) }
        return (folder, selection)
    }

    // MARK: - Checks

    func isTargetType(_ menuItem: MenuItem, _ selected: [URL]) -> Bool {
        switch menuItem.targetType {
        case "any":
            return true;
        case "folder":
            return hasFolderSelection(selected)
        case "file":
            return hasFileSelection(selected)
        default:
            let extensions: [String] = menuItem.targetType.split(separator: ",").map(String.init)
            return hasAnyExtension(selected, extensions);
        }
    }

    func hasFolderSelection(_ selected: [URL]) -> Bool {
        return selected.contains(where: { $0.hasDirectoryPath })
    }
    
    func hasFileSelection(_ selected: [URL]) -> Bool {
        return selected.contains(where: { !$0.hasDirectoryPath })
    }
    
    func hasAnyExtension(_ selected: [URL], _ extensions: [String]) -> Bool {
        return selected.contains(where: { url in
            extensions.contains(where: { url.pathExtension.lowercased() == $0.lowercased() })
        })
    }
    
    // MARK: - Actions
    
    /// Perform clicked menu item based on its action.
    @IBAction func action(_ sender: NSMenuItem) {
        guard let menuItem = SettingsManager.shared.menuItems[sender.title] else {
            print("Action - Not found!")
            return
        }
        print("\n" + menuItem.actionType + "(" + menuItem.key + "):" + menuItem.action)
        var items = FIFinderSyncController.default().selectedItemURLs() ?? []
        if items.isEmpty { items = toolbarSelection }
        let target = FIFinderSyncController.default().targetedURL()
            ?? toolbarTarget
            ?? FileManager.default.homeDirectoryForCurrentUser
        // Nothing selected anywhere: act on the current folder.
        if items.isEmpty { items = [target] }
        
        switch menuItem.actionType {
        case "copy":
            copyPaths(items)
        default:
            signalMainApp(menuItem, items, target)
        }
    }

    func runTerminal(_ menuItem: MenuItem, _ items: [URL], _ target: URL? = nil) {
        let cd = target != nil ? "cd \"\(target!.path)\"; " : ""
        let escapedCommand = menuItem.action.replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Terminal"
        activate
        do script "\(cd)\(escapedCommand)"
        end tell
        """

        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)

        if let error = error {
            print("AppleScript error:", error)
        }
    }
    
    func runShell(_ menuItem: MenuItem, _ items: [URL], _ target: URL? = nil) {
        let paths = items
        .map { "\"\($0.path)\"" }
        .joined(separator: " ")
        let command = menuItem.action
        let commandFormatted = menuItem.action
            .replacingOccurrences(of: "%selected", with: paths)
            .replacingOccurrences(of: "%folder", with: target?.path ?? "")
        
        print("Activated - Running command: " + command + "\n")
        
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", commandFormatted]
        task.launch()
    }
    
    func runApp(_ menuItem: MenuItem, _ items: [URL], _ target: URL? = nil) {
        let app = URL(fileURLWithPath: menuItem.action)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        print("Activated - Running app: " + app.lastPathComponent + "\n")
        NSWorkspace.shared.open(
            items,
            withApplicationAt: app,
            configuration: config,
            completionHandler: { app, error in
                if let error = error {
                    print("\n\nOpen failed:", error)
                    print("\n\n")
                    }
        })
    }
    
    func copyPaths(_ items: [URL]) {
        guard !items.isEmpty else { return }
        print("Activated - Copying paths\n")
        let paths = items.map { $0.path }.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(paths, forType: .string)
    }
    
    func writePayload(_ menuItem: MenuItem, _ items: [URL], _ target: URL?) throws {
        let payload = Payload(
            actionType: menuItem.actionType,
            action: menuItem.action,
            targetType: menuItem.targetType,
            items: items.map(\.path),
            target: target?.path
            )
        let url = SettingsManager.shared.payloadFile
        let data = try JSONEncoder().encode(payload)
        try data.write(to: url, options: .atomic)
    }
    
    func signalMainApp(_ menuItem: MenuItem, _ items: [URL], _ target: URL? = nil)
    {
        do {
            try writePayload(
                menuItem,
                items,
                target
            )
            var components = URLComponents()
            components.scheme = "tooly"
            components.host = "run"
            components.queryItems = [
                URLQueryItem(
                    name: "payload",
                    value: SettingsManager.shared.payloadFile.path()
                )
            ]
            
            guard let url = components.url else { return }
            NSWorkspace.shared.open(url)
            print(url.path())
        }
        catch {
            print("Signal - Failed to send payload:", error)
        }
    }
    
}
