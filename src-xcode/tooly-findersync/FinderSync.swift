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
    
    // MARK: - Construction
    
    /// Rebuild and return new context menu with dynamic items.
    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        print("Menu - Recreating menus")
        let menu = NSMenu(title: "")
        var groups: [String: NSMenu] = [:]
        let selected = FIFinderSyncController.default().selectedItemURLs() ?? []
        
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
        return menu;
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
        let target = FIFinderSyncController.default().targetedURL() ?? FileManager.default.homeDirectoryForCurrentUser
        let items = FIFinderSyncController.default().selectedItemURLs() ?? []
        
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
