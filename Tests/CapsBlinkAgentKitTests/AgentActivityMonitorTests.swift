import XCTest
import CapsBlinkKit
@testable import CapsBlinkAgentKit

final class RecordingNotifier: ChangeNotifier, @unchecked Sendable {
    private let lock = NSLock()
    private var _titles: [String] = []
    var titles: [String] {
        lock.lock(); defer { lock.unlock() }
        return _titles
    }
    func isAvailable() async -> Bool { true }
    func notify(_ notification: ChangeNotification) async {
        lock.lock(); defer { lock.unlock() }
        _titles.append(notification.title)
    }
}

final class AgentActivityMonitorTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("capsblink-agent-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeAgent() -> AgentKind {
        AgentKind(id: "test", displayName: "TestAgent", transcriptRoots: [root])
    }

    func testWorkingThenQuietTriggersFinishedNotification() async throws {
        let notifier = RecordingNotifier()
        let monitor = AgentActivityMonitor(
            notifier: notifier,
            configuration: .init(
                agents: [makeAgent()],
                quietThreshold: 2,
                minimumActivityDuration: 0,
                finishedDisplayDuration: 60
            )
        )
        await monitor.start()

        // Simulate an agent writing its transcript for ~1.5s.
        let transcript = root.appendingPathComponent("session.jsonl")
        FileManager.default.createFile(atPath: transcript.path, contents: Data())
        let handle = try FileHandle(forWritingTo: transcript)
        for _ in 0..<5 {
            try handle.write(contentsOf: Data("{\"event\":\"work\"}\n".utf8))
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        try handle.close()

        // Wait past the quiet threshold for the finished transition.
        try await Task.sleep(nanoseconds: 4_000_000_000)

        XCTAssertEqual(notifier.titles, ["TestAgent"])
        await monitor.stop()
    }

    func testNonMatchingFilesAreIgnored() async throws {
        let notifier = RecordingNotifier()
        let monitor = AgentActivityMonitor(
            notifier: notifier,
            configuration: .init(
                agents: [makeAgent()],
                quietThreshold: 1,
                minimumActivityDuration: 0,
                finishedDisplayDuration: 60
            )
        )
        await monitor.start()

        let other = root.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: other)
        try await Task.sleep(nanoseconds: 2_500_000_000)

        XCTAssertTrue(notifier.titles.isEmpty)
        await monitor.stop()
    }

    func testUninstalledAgentReportsNotInstalled() async {
        let missing = AgentKind(
            id: "missing",
            displayName: "Missing",
            transcriptRoots: [root.appendingPathComponent("nope")]
        )
        XCTAssertFalse(missing.isInstalled)
    }
}
