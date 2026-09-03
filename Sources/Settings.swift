import Foundation

struct Settings: Codable {
    var apiKey: String = ""
    var autoCopy: Bool = true
    var playSound: Bool = true
    var zipFolders: Bool = true
}

enum ConfigStore {
    static let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Hack Club CDN", isDirectory: true)
    static let file = dir.appendingPathComponent("config.json")

    static func load() -> Settings {
        guard let data = try? Data(contentsOf: file),
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return settings
    }

    static func save(_ settings: Settings) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: file, options: [.atomic])
        // The API key lives in here, so keep it readable only by this user.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
