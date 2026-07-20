import XCTest
import CapsBlinkKit
@testable import CapsBlinkLlama

/// End-to-end inference smoke test against a real GGUF model.
///
/// Skipped unless `CAPSBLINK_SMOKE_MODEL` points at a model file, because CI
/// unit-test runs should not need a 1 GB download. Run locally with:
///
///     make model
///     CAPSBLINK_SMOKE_MODEL=Models/qwen2.5-1.5b-instruct-q4_k_m.gguf swift test --filter LlamaSmokeTests
///
/// Use this when upgrading the model or the pinned llama.cpp version.
final class LlamaSmokeTests: XCTestCase {
    private func makeSession() throws -> LlamaSession {
        guard let path = ProcessInfo.processInfo.environment["CAPSBLINK_SMOKE_MODEL"] else {
            throw XCTSkip("CAPSBLINK_SMOKE_MODEL not set")
        }
        return try LlamaSession(modelPath: path)
    }

    func testScoreChangeTriggersNotification() async throws {
        let session = try makeSession()
        let classifier = LlamaChangeClassifier(session: session)
        let context = ChangeContext(
            url: URL(string: "https://scores.example.com/premier-league")!,
            change: DetectedChange(
                addedLines: ["Arsenal 2 - 1 Chelsea", "78' GOAL — Saka scores for Arsenal"],
                removedLines: ["Arsenal 1 - 1 Chelsea"]
            ),
            watchInstruction: SettingsStore.defaultWatchInstruction
        )
        let assessment = try await classifier.assess(context)
        XCTAssertTrue(assessment.shouldNotify, "a goal must notify; got: \(assessment)")
        XCTAssertFalse(assessment.reason.isEmpty)
    }

    func testClockTickDoesNotNotify() async throws {
        let session = try makeSession()
        let classifier = LlamaChangeClassifier(session: session)
        let context = ChangeContext(
            url: URL(string: "https://scores.example.com/premier-league")!,
            change: DetectedChange(
                addedLines: ["Last updated: 14:03:22", "Ad: Buy 1 get 1 free at SportShop"],
                removedLines: ["Last updated: 14:02:22", "Ad: New season kits available"]
            ),
            watchInstruction: SettingsStore.defaultWatchInstruction
        )
        let assessment = try await classifier.assess(context)
        XCTAssertFalse(assessment.shouldNotify, "clock/ad noise must not notify; got: \(assessment)")
    }
}
