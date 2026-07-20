import Foundation

/// Observable lifecycle state of a `PageWatcher`, suitable for direct display in UI.
public enum WatcherStatus: Sendable, Equatable {
    case idle
    /// The classifier (LLM) is being prepared; progress is 0...1 while the
    /// model file is downloading, `nil` while it is loading into memory.
    case preparingModel(progress: Double?)
    case watching(lastChecked: Date?)
    /// A change was detected and is being evaluated by the classifier.
    case evaluating
    /// The user was just notified.
    case notified(reason: String, at: Date)
    case error(String)
}

extension WatcherStatus {
    /// Short human-readable description used by the apps' status rows.
    public var displayText: String {
        switch self {
        case .idle:
            return "Idle"
        case .preparingModel(let progress):
            if let progress {
                return "Downloading model… \(Int(progress * 100))%"
            }
            return "Loading model…"
        case .watching(let lastChecked):
            if let lastChecked {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                formatter.dateStyle = .none
                return "Watching — last check \(formatter.string(from: lastChecked))"
            }
            return "Watching"
        case .evaluating:
            return "Change detected — evaluating…"
        case .notified(let reason, _):
            return "Notified: \(reason)"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}
