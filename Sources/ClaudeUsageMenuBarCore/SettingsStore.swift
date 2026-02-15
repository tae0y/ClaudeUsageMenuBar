import Foundation

public struct AppSettings: Codable, Sendable {
    public var dailyTokenLimit: Int?
    public var weeklyTokenLimit: Int?
    public var lastSnapshot: PersistedSnapshot?

    public init(dailyTokenLimit: Int? = nil, weeklyTokenLimit: Int? = nil, lastSnapshot: PersistedSnapshot? = nil) {
        self.dailyTokenLimit = dailyTokenLimit
        self.weeklyTokenLimit = weeklyTokenLimit
        self.lastSnapshot = lastSnapshot
    }
}

public struct PersistedSnapshot: Codable, Sendable {
    public var dailyTokens: Int
    public var weeklyTokens: Int
    public var fetchedAt: Date
    public var sourceDescription: String

    public init(dailyTokens: Int, weeklyTokens: Int, fetchedAt: Date, sourceDescription: String) {
        self.dailyTokens = dailyTokens
        self.weeklyTokens = weeklyTokens
        self.fetchedAt = fetchedAt
        self.sourceDescription = sourceDescription
    }
}

public final class SettingsStore {
    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(appSupportDirName: String = "ClaudeUsageMenuBar") {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        let dir = base.appendingPathComponent(appSupportDirName, isDirectory: true)
        self.url = dir.appendingPathComponent("settings.json", isDirectory: false)

        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        // Best-effort: create directory.
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: url) else {
            return AppSettings()
        }
        return (try? decoder.decode(AppSettings.self, from: data)) ?? AppSettings()
    }

    public func save(_ settings: AppSettings) throws {
        let data = try encoder.encode(settings)
        try data.write(to: url, options: [.atomic])
    }

    public func settingsURL() -> URL {
        url
    }
}
