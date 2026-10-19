import Foundation

/// A named snapshot of one set of displays: their arrangement, and optionally the windows on them.
public struct SavedLayout: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var created: Date
    public var displays: [DisplayState]
    /// nil for an arrangement-only layout.
    public var windows: [WindowState]?

    public init(id: UUID = UUID(), name: String, created: Date = Date(), displays: [DisplayState], windows: [WindowState]? = nil) {
        self.id = id
        self.name = name
        self.created = created
        self.displays = displays
        self.windows = windows
    }

    /// Identifies the set of displays, regardless of how they're arranged.
    public var setup: String { SavedLayout.setup(of: displays) }

    public static func setup(of displays: [DisplayState]) -> String {
        displays.map(\.key).sorted().joined(separator: "|")
    }
}

/// Everything Monitor Minder stores, in one human-readable JSON file.
public struct Config: Codable, Equatable, Sendable {
    public var version = 1
    /// Names the user gave displays, by display key.
    public var displayNames: [String: String] = [:]
    public var layouts: [SavedLayout] = []
    /// Restore the remembered layout when a set of displays connects or wakes.
    public var autoRestore = true
    /// The layout last saved or applied for each display setup, which auto-restore and drift
    /// checks compare against.
    public var lastUsed: [String: UUID] = [:]

    public init() {}

    // Every field is optional on decode, so hand-edited or older files still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        displayNames = try c.decodeIfPresent([String: String].self, forKey: .displayNames) ?? [:]
        layouts = try c.decodeIfPresent([SavedLayout].self, forKey: .layouts) ?? []
        autoRestore = try c.decodeIfPresent(Bool.self, forKey: .autoRestore) ?? true
        lastUsed = try c.decodeIfPresent([String: UUID].self, forKey: .lastUsed) ?? [:]
    }

    public func layouts(for setup: String) -> [SavedLayout] { layouts.filter { $0.setup == setup } }
}

/// Reads and writes the config file at
/// `~/Library/Application Support/MonitorMinder/config.json`, or at `$MONITOR_MINDER_CONFIG`.
public struct ConfigStore: Sendable {
    public let url: URL

    public init(url: URL = ConfigStore.defaultURL) { self.url = url }

    public static var defaultURL: URL {
        if let path = ProcessInfo.processInfo.environment["MONITOR_MINDER_CONFIG"], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "MonitorMinder/config.json")
    }

    /// A missing file is an empty config, not an error.
    public func load() throws -> Config {
        guard FileManager.default.fileExists(atPath: url.path) else { return Config() }
        return try Self.decode(Data(contentsOf: url))
    }

    public func save(_ config: Config) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encode(config).write(to: url, options: .atomic)
    }

    public static func encode(_ config: Config) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(config)
    }

    public static func decode(_ data: Data) throws -> Config {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Config.self, from: data)
    }
}
