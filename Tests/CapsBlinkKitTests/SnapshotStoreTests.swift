import XCTest
@testable import CapsBlinkKit

final class SnapshotStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("capsblink-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRoundTrip() {
        let store = SnapshotStore(directory: directory)
        let url = URL(string: "https://example.com/match")!
        XCTAssertNil(store.load(for: url))

        let snapshot = PageSnapshot(text: "hello\nworld")
        store.save(snapshot, for: url)

        let loaded = store.load(for: url)
        XCTAssertEqual(loaded?.text, "hello\nworld")
        XCTAssertEqual(loaded?.contentHash, ChangeDetector.contentHash("hello\nworld"))

        store.clear(for: url)
        XCTAssertNil(store.load(for: url))
    }

    func testDistinctURLsDoNotCollide() {
        let store = SnapshotStore(directory: directory)
        let first = URL(string: "https://example.com/a")!
        let second = URL(string: "https://example.com/b")!
        store.save(PageSnapshot(text: "A"), for: first)
        store.save(PageSnapshot(text: "B"), for: second)
        XCTAssertEqual(store.load(for: first)?.text, "A")
        XCTAssertEqual(store.load(for: second)?.text, "B")
    }
}

final class SettingsStoreTests: XCTestCase {
    func testWatchInstructionFallsBackToDefault() {
        let defaults = UserDefaults(suiteName: "capsblink-tests-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.watchInstruction, SettingsStore.defaultWatchInstruction)

        store.watchInstruction = "watch for price drops"
        XCTAssertEqual(store.watchInstruction, "watch for price drops")

        store.watchInstruction = "   "
        XCTAssertEqual(store.watchInstruction, SettingsStore.defaultWatchInstruction)

        store.resetWatchInstruction()
        XCTAssertEqual(store.watchInstruction, SettingsStore.defaultWatchInstruction)
    }

    func testIntervalHasSaneFloor() {
        let defaults = UserDefaults(suiteName: "capsblink-tests-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.interval, SettingsStore.defaultInterval)
        store.interval = 1 // below floor
        XCTAssertEqual(store.interval, SettingsStore.defaultInterval)
        store.interval = 120
        XCTAssertEqual(store.interval, 120)
    }
}
