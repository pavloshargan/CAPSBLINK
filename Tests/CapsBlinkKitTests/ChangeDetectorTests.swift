import XCTest
@testable import CapsBlinkKit

final class ChangeDetectorTests: XCTestCase {
    private let detector = ChangeDetector()

    func testIdenticalTextIsNoChange() {
        XCTAssertNil(detector.detect(previous: "a\nb\nc", current: "a\nb\nc"))
    }

    func testAddedAndRemovedLines() {
        let change = detector.detect(previous: "score 0-0\nlive", current: "score 1-0\nlive")
        XCTAssertEqual(change?.addedLines, ["score 1-0"])
        XCTAssertEqual(change?.removedLines, ["score 0-0"])
    }

    func testPureReorderingIsNoChange() {
        XCTAssertNil(detector.detect(previous: "a\nb\nc", current: "c\na\nb"))
    }

    func testDuplicateLineCountsMatter() {
        let change = detector.detect(previous: "x\nx", current: "x")
        XCTAssertEqual(change?.removedLines, ["x"])
        XCTAssertEqual(change?.addedLines, [])
    }

    func testContentHashIsStable() {
        XCTAssertEqual(ChangeDetector.contentHash("hello"), ChangeDetector.contentHash("hello"))
        XCTAssertNotEqual(ChangeDetector.contentHash("hello"), ChangeDetector.contentHash("hello "))
    }
}

final class HeuristicClassifierTests: XCTestCase {
    func testNotifiesOnSubstantiveChange() async throws {
        let classifier = HeuristicChangeClassifier()
        let context = ChangeContext(
            url: URL(string: "https://example.com")!,
            change: DetectedChange(addedLines: ["Arsenal scored"], removedLines: []),
            watchInstruction: "anything"
        )
        let assessment = try await classifier.assess(context)
        XCTAssertTrue(assessment.shouldNotify)
    }

    func testIgnoresTrivialChange() async throws {
        let classifier = HeuristicChangeClassifier()
        let context = ChangeContext(
            url: URL(string: "https://example.com")!,
            change: DetectedChange(addedLines: ["1"], removedLines: ["2"]),
            watchInstruction: "anything"
        )
        let assessment = try await classifier.assess(context)
        XCTAssertFalse(assessment.shouldNotify)
    }
}
