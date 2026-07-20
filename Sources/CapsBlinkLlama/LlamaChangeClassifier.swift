import CapsBlinkKit
import Foundation

/// LLM-backed change classifier: feeds the deterministic diff to a local
/// model and gets a grammar-constrained JSON verdict back.
public struct LlamaChangeClassifier: ChangeClassifier {
    /// Caps applied to the diff before it is put in the prompt, to stay well
    /// inside the model's context window.
    static let maxLinesPerSide = 40
    static let maxCharactersPerSide = 3_500

    private let session: LlamaSession

    public init(session: LlamaSession) {
        self.session = session
    }

    public func assess(_ context: ChangeContext) async throws -> ChangeAssessment {
        let output = try await session.generate(
            system: Self.systemPrompt,
            user: Self.userPrompt(for: context),
            grammar: VerdictGrammar.gbnf,
            maxTokens: 300
        )
        guard let verdict = Self.parseVerdict(output) else {
            // The grammar makes this near-impossible, but if parsing fails we
            // notify anyway: a spurious blink beats a missed update.
            return ChangeAssessment(shouldNotify: true, reason: "Page changed (unparseable verdict)")
        }
        return verdict
    }

    // MARK: - Prompt construction (static, unit-testable)

    static let systemPrompt = """
        You monitor webpages for a user and decide whether an observed change is worth an \
        immediate notification. You are given lines that were removed and lines that were \
        added since the last check.

        Notify only for meaningful content updates matching the user's interest. Never notify \
        for noise: clocks, timestamps, view/like counters, session IDs, ads, cookie banners, \
        rotating promotions, or randomized item order.

        Respond with exactly one JSON object: {"notify": true or false, "reason": "short human explanation"}
        """

    static func userPrompt(for context: ChangeContext) -> String {
        """
        Page: \(context.url.absoluteString)
        The user wants to be notified about: \(context.watchInstruction)

        Removed lines:
        \(clip(context.change.removedLines))

        Added lines:
        \(clip(context.change.addedLines))

        Should the user be notified?
        """
    }

    static func clip(_ lines: [String]) -> String {
        guard !lines.isEmpty else { return "(none)" }
        var kept: [String] = []
        var totalCharacters = 0
        for line in lines.prefix(maxLinesPerSide) {
            let clipped = String(line.prefix(300))
            totalCharacters += clipped.count
            if totalCharacters > maxCharactersPerSide { break }
            kept.append(clipped)
        }
        var result = kept.joined(separator: "\n")
        if kept.count < lines.count {
            result += "\n(… \(lines.count - kept.count) more lines omitted)"
        }
        return result
    }

    // MARK: - Verdict parsing

    static func parseVerdict(_ output: String) -> ChangeAssessment? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start < end
        else { return nil }
        let json = String(trimmed[start...end])
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let notify = object["notify"] as? Bool
        else { return nil }
        let reason = (object["reason"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (notify ? "Meaningful change detected" : "No meaningful change")
        return ChangeAssessment(shouldNotify: notify, reason: reason)
    }
}

/// Convenience factory for the standard pipeline: ensure the GGUF model is
/// present (downloading if needed), load it, return the classifier.
public enum LlamaClassifierFactory {
    public static func make(spec: ModelSpec = .default) -> ClassifierFactory {
        { progress in
            let manager = ModelManager(spec: spec)
            let modelURL = try await manager.ensureModel { fraction in
                progress(fraction)
            }
            progress(nil) // downloading done; now loading (indeterminate)
            let session = try await Task.detached(priority: .userInitiated) {
                try LlamaSession(modelPath: modelURL.path)
            }.value
            return LlamaChangeClassifier(session: session)
        }
    }
}
