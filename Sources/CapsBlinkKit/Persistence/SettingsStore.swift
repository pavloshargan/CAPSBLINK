import Foundation

/// Thin, typed wrapper over `UserDefaults` for the page-watcher settings.
public struct SettingsStore: @unchecked Sendable {
    public static let defaultInterval: TimeInterval = 60

    /// Default instruction, tuned for live sports pages but editable by the
    /// user so any page can be watched (Settings → "What to watch for").
    public static let defaultWatchInstruction = """
        Notify about meaningful updates a fan following this page would care about: \
        a score change, a goal or point scored, a match starting or finishing, \
        a status change (halftime, overtime, cancelled), or important breaking news.
        """

    private let defaults: UserDefaults

    private enum Key {
        static let urlString = "watch.urlString"
        static let interval = "watch.intervalSeconds"
        static let instruction = "watch.instruction"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var urlString: String {
        get { defaults.string(forKey: Key.urlString) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: Key.urlString) }
    }

    public var interval: TimeInterval {
        get {
            let value = defaults.double(forKey: Key.interval)
            return value >= 5 ? value : Self.defaultInterval
        }
        nonmutating set { defaults.set(newValue, forKey: Key.interval) }
    }

    public var watchInstruction: String {
        get {
            let value = defaults.string(forKey: Key.instruction) ?? ""
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? Self.defaultWatchInstruction
                : value
        }
        nonmutating set { defaults.set(newValue, forKey: Key.instruction) }
    }

    public func resetWatchInstruction() {
        defaults.removeObject(forKey: Key.instruction)
    }
}
