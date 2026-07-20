import Foundation

/// A user-visible notification about something the watcher considers important.
public struct ChangeNotification: Sendable {
    public let title: String
    public let reason: String
    public let date: Date

    public init(title: String, reason: String, date: Date = .now) {
        self.title = title
        self.reason = reason
        self.date = date
    }
}

/// Abstraction over "get the user's attention". The primary implementation
/// blinks the Caps Lock LED; alternatives (system banner, sound, external
/// lights) can be substituted or composed without touching the watcher.
public protocol ChangeNotifier: Sendable {
    /// Whether this notifier can currently deliver (e.g. LED found + permission granted).
    func isAvailable() async -> Bool
    func notify(_ notification: ChangeNotification) async
}

/// Fans a notification out to every available notifier; falls back to the
/// first notifier if none report availability so events are never dropped silently.
public struct CompositeNotifier: ChangeNotifier {
    private let notifiers: [any ChangeNotifier]

    public init(_ notifiers: [any ChangeNotifier]) {
        precondition(!notifiers.isEmpty, "CompositeNotifier needs at least one notifier")
        self.notifiers = notifiers
    }

    public func isAvailable() async -> Bool {
        for notifier in notifiers where await notifier.isAvailable() {
            return true
        }
        return false
    }

    public func notify(_ notification: ChangeNotification) async {
        var delivered = false
        for notifier in notifiers where await notifier.isAvailable() {
            await notifier.notify(notification)
            delivered = true
        }
        if !delivered {
            await notifiers[0].notify(notification)
        }
    }
}
