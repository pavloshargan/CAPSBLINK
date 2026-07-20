import Foundation

/// The classifier's verdict on a detected change.
public struct ChangeAssessment: Sendable, Equatable {
    public let shouldNotify: Bool
    public let reason: String

    public init(shouldNotify: Bool, reason: String) {
        self.shouldNotify = shouldNotify
        self.reason = reason
    }
}

/// Everything a classifier needs to judge a change.
public struct ChangeContext: Sendable {
    public let url: URL
    public let change: DetectedChange
    /// User-configurable description of what counts as a meaningful update
    /// (e.g. "score changes in a football match").
    public let watchInstruction: String

    public init(url: URL, change: DetectedChange, watchInstruction: String) {
        self.url = url
        self.change = change
        self.watchInstruction = watchInstruction
    }
}

/// Decides whether a detected change deserves a notification.
/// The LLM-backed implementation lives in `CapsBlinkLlama`; this protocol
/// keeps `CapsBlinkKit` free of inference dependencies and lets tests (or
/// model-less builds) substitute a deterministic implementation.
public protocol ChangeClassifier: Sendable {
    func assess(_ context: ChangeContext) async throws -> ChangeAssessment
}

/// Fallback used when no model is available: notifies on any substantive
/// diff. Better to over-notify than to silently degrade.
public struct HeuristicChangeClassifier: ChangeClassifier {
    /// Lines shorter than this (after trimming) are considered noise.
    public var minimumLineLength: Int

    public init(minimumLineLength: Int = 3) {
        self.minimumLineLength = minimumLineLength
    }

    public func assess(_ context: ChangeContext) async throws -> ChangeAssessment {
        let substantive = (context.change.addedLines + context.change.removedLines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= minimumLineLength }
        if let first = substantive.first {
            return ChangeAssessment(shouldNotify: true, reason: "Page changed: \(first.prefix(120))")
        }
        return ChangeAssessment(shouldNotify: false, reason: "Only trivial characters changed")
    }
}
