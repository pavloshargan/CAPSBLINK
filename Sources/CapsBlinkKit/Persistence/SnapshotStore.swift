import Foundation

/// The last extracted text of a watched page.
public struct PageSnapshot: Codable, Sendable {
    public let text: String
    public let contentHash: String
    public let capturedAt: Date

    public init(text: String, capturedAt: Date = .now) {
        self.text = text
        self.contentHash = ChangeDetector.contentHash(text)
        self.capturedAt = capturedAt
    }
}

/// Persists one snapshot per URL under Application Support, so relaunching
/// the app keeps its baseline instead of re-learning the page (and never
/// notifies about changes it already saw).
public struct SnapshotStore: Sendable {
    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("CapsBlink/Snapshots", isDirectory: true)
    }

    private func fileURL(for url: URL) -> URL {
        directory.appendingPathComponent(ChangeDetector.contentHash(url.absoluteString) + ".json")
    }

    public func load(for url: URL) -> PageSnapshot? {
        guard let data = try? Data(contentsOf: fileURL(for: url)) else { return nil }
        return try? JSONDecoder().decode(PageSnapshot.self, from: data)
    }

    public func save(_ snapshot: PageSnapshot, for url: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL(for: url), options: .atomic)
    }

    public func clear(for url: URL) {
        try? FileManager.default.removeItem(at: fileURL(for: url))
    }
}
