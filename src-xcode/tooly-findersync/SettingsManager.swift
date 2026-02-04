//  Created by gchibeni.

import Foundation

// MARK: - Structs

struct MenuSettings: Codable {
    let order: [String]
    let groups: [String: MenuGroup]
    let items: [String: MenuItem]
    let separators: Bool
}

struct MenuGroup: Codable {
    let iconType: String
    let icon: String
}

struct MenuItem: Codable {
    let group: String
    let targetType: String
    let iconType: String
    let icon: String
    let actionType: String
    let action: String
    let key: String
    let enabled: Bool
}

struct Payload: Codable {
    let actionType: String
    let action: String
    let targetType: String
    let items: [String]
    let target: String?
}

// MARK: - Classes

class SettingsManager {

    /// Settings Manager static instance.
    static let shared = SettingsManager()

    private(set) var menuItems: [String: MenuItem] = [:]
    private(set) var menuGroups: [String: MenuGroup] = [:]
    private(set) var itemOrder: [String] = []
    private(set) var separators: Bool = true
    private(set) var settingsFile: URL
    private(set) var payloadFile: URL
    private var source: DispatchSourceFileSystemObject?
    private let appFolder: String = "Tooly"

    /// Initialize manager.
    init() {
        print("Init - Initializing manager instance")
        
        let libraryURL = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first!

        let appSupportURL = libraryURL
            .appendingPathComponent("Application Support")
            .appendingPathComponent(appFolder)
        
        try? FileManager.default.createDirectory(
            at: appSupportURL,
            withIntermediateDirectories: true,
            attributes: nil)
        
        settingsFile = appSupportURL.appendingPathComponent("settings.json")
        payloadFile = appSupportURL.appendingPathComponent("payload.json")
        print("Init - Fetched settings URL: " + settingsFile.path())
        loadSettings()
        watchSettings()
    }
    
    /// Load and decode settings file.
    func loadSettings() {
        print("Load - Decoding settings file")
        guard let data = try? Data(contentsOf: settingsFile) else {
            print("Load - Failed to decode settings file")
            return
        }
        let decoder = JSONDecoder()
        if let settings = try? decoder.decode(MenuSettings.self, from: data) {
            menuItems = settings.items
            menuGroups = settings.groups
            itemOrder = settings.order
            separators = settings.separators
            print("Load - Settings file decoded")
        }
    }

    /// Start watching the settings file for changes.
    func watchSettings() {
        print("Watch - Started watching settings file")
        let fileDescriptor = open(settingsFile.path, O_EVTONLY)
        guard fileDescriptor != -1 else { return }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: DispatchQueue.global()
        )

        source?.setEventHandler { [weak self] in
            self?.loadSettings()
        }

        source?.setCancelHandler {
            close(fileDescriptor)
        }

        source?.resume()
    }
}
