import XCTest
import CapsBlinkKit
@testable import CapsBlinkLlama

/// Tests for the pure (model-free) parts of the LLM classifier: prompt
/// assembly, diff clipping and verdict parsing. Inference itself is exercised
/// manually / in release smoke tests, not in unit tests.
final class LlamaChangeClassifierTests: XCTestCase {
    func testUserPromptContainsInstructionAndDiff() {
        let context = ChangeContext(
            url: URL(string: "https://example.com/game")!,
            change: DetectedChange(addedLines: ["Arsenal 2 - 1 Chelsea"], removedLines: ["Arsenal 1 - 1 Chelsea"]),
            watchInstruction: "score changes"
        )
        let prompt = LlamaChangeClassifier.userPrompt(for: context)
        XCTAssertTrue(prompt.contains("https://example.com/game"))
        XCTAssertTrue(prompt.contains("score changes"))
        XCTAssertTrue(prompt.contains("Arsenal 2 - 1 Chelsea"))
        XCTAssertTrue(prompt.contains("Arsenal 1 - 1 Chelsea"))
    }

    func testClipCapsLinesAndReportsOmissions() {
        let lines = (0..<200).map { "line \($0)" }
        let clipped = LlamaChangeClassifier.clip(lines)
        XCTAssertTrue(clipped.contains("line 0"))
        XCTAssertFalse(clipped.contains("line 199"))
        XCTAssertTrue(clipped.contains("more lines omitted"))
    }

    func testClipEmptyProducesPlaceholder() {
        XCTAssertEqual(LlamaChangeClassifier.clip([]), "(none)")
    }

    func testParseValidVerdict() {
        let assessment = LlamaChangeClassifier.parseVerdict(
            #"{"notify": true, "reason": "Score changed to 2-1"}"#
        )
        XCTAssertEqual(assessment, ChangeAssessment(shouldNotify: true, reason: "Score changed to 2-1"))
    }

    func testParseVerdictWithSurroundingNoise() {
        let assessment = LlamaChangeClassifier.parseVerdict(
            "Sure! Here is the verdict: {\"notify\": false, \"reason\": \"only a clock changed\"} hope that helps"
        )
        XCTAssertEqual(assessment?.shouldNotify, false)
    }

    func testParseGarbageReturnsNil() {
        XCTAssertNil(LlamaChangeClassifier.parseVerdict("not json at all"))
        XCTAssertNil(LlamaChangeClassifier.parseVerdict("{\"unrelated\": 1}"))
    }

    func testGrammarShapeMatchesParser() {
        // The grammar's fixed prefix must produce JSON the parser accepts.
        XCTAssertTrue(VerdictGrammar.gbnf.contains("root ::="))
        XCTAssertTrue(VerdictGrammar.gbnf.contains("\\\"notify\\\": "))
        let sample = "{\"notify\": true, \"reason\": \"x\"}"
        XCTAssertNotNil(LlamaChangeClassifier.parseVerdict(sample))
    }

    func testChatMLFallbackFormat() {
        let prompt = LlamaSession.chatML(system: "SYS", user: "USR")
        XCTAssertTrue(prompt.contains("<|im_start|>system\nSYS<|im_end|>"))
        XCTAssertTrue(prompt.contains("<|im_start|>user\nUSR<|im_end|>"))
        XCTAssertTrue(prompt.hasSuffix("<|im_start|>assistant\n"))
    }
}
