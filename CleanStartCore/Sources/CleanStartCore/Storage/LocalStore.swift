import Foundation

/// Persists Codable values as JSON files in a local directory.
///
/// Nothing is ever synced or transmitted. On iOS, files are written with data
/// protection so they are encrypted while the device is locked after boot, and
/// the directory is excluded from iCloud/iTunes backups.
public final class LocalStore: @unchecked Sendable {
    public let directory: URL
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL) {
        self.directory = directory
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    /// `Application Support/CleanStart` inside the app sandbox.
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("CleanStart", isDirectory: true)
    }

    public func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    public func save<T: Encodable>(_ value: T, key: String) throws {
        lock.lock(); defer { lock.unlock() }
        try ensureDirectory()
        let data = try encoder.encode(value)
        #if os(iOS)
        try data.write(to: url(for: key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url(for: key), options: [.atomic])
        #endif
    }

    public func remove(key: String) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: url(for: key))
    }

    /// Deletes every file CleanStart stored. Used by "Delete all local data".
    public func removeAll() throws {
        lock.lock(); defer { lock.unlock() }
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    public func storedKeys() -> [String] {
        lock.lock(); defer { lock.unlock() }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return files.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
    }

    private func url(for key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }

    private func ensureDirectory() throws {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        var dir = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        #endif
    }
}

/// Keys for everything CleanStart stores, listed in Settings › Privacy.
public enum StoreKey {
    public static let habitLog = "habit-log"
    public static let accountability = "accountability"
    public static let verificationHistory = "verification-history"
    public static let workChecklist = "work-checklist"
    public static let preferences = "preferences"
}
