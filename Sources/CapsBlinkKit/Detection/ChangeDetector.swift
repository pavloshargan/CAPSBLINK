import CryptoKit
import Foundation

/// The deterministic difference between two extracted page texts.
public struct DetectedChange: Sendable, Equatable {
    public let addedLines: [String]
    public let removedLines: [String]

    public init(addedLines: [String], removedLines: [String]) {
        self.addedLines = addedLines
        self.removedLines = removedLines
    }

    public var isEmpty: Bool { addedLines.isEmpty && removedLines.isEmpty }
}

/// Cheap, deterministic comparison that gates the (expensive) LLM call:
/// identical content — or content whose lines merely moved around — never
/// reaches the model.
public struct ChangeDetector: Sendable {
    public init() {}

    public static func contentHash(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Returns `nil` when there is nothing meaningful to evaluate.
    ///
    /// Uses an order-preserving multiset line diff: a line counts as added if
    /// it appears more times in the new text than in the old one (and vice
    /// versa). Pure reordering therefore produces no change.
    public func detect(previous: String, current: String) -> DetectedChange? {
        if previous == current { return nil }

        let oldLines = previous.components(separatedBy: "\n")
        let newLines = current.components(separatedBy: "\n")

        var oldCounts: [String: Int] = [:]
        for line in oldLines {
            oldCounts[line, default: 0] += 1
        }

        var added: [String] = []
        var remaining = oldCounts
        for line in newLines {
            if let count = remaining[line], count > 0 {
                remaining[line] = count - 1
            } else {
                added.append(line)
            }
        }

        var newCounts: [String: Int] = [:]
        for line in newLines {
            newCounts[line, default: 0] += 1
        }
        var removed: [String] = []
        var remainingNew = newCounts
        for line in oldLines {
            if let count = remainingNew[line], count > 0 {
                remainingNew[line] = count - 1
            } else {
                removed.append(line)
            }
        }

        let change = DetectedChange(addedLines: added, removedLines: removed)
        return change.isEmpty ? nil : change
    }
}
