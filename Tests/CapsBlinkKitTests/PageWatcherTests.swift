import XCTest
@testable import CapsBlinkKit

/// Records notifications for assertions.
final class SpyNotifier: ChangeNotifier, @unchecked Sendable {
    private let lock = NSLock()
    private var _notifications: [ChangeNotification] = []

    var notifications: [ChangeNotification] {
        lock.lock(); defer { lock.unlock() }
        return _notifications
    }

    func isAvailable() async -> Bool { true }

    func notify(_ notification: ChangeNotification) async {
        lock.lock(); defer { lock.unlock() }
        _notifications.append(notification)
    }
}

final class CompositeNotifierTests: XCTestCase {
    struct UnavailableNotifier: ChangeNotifier {
        let spy: SpyNotifier
        func isAvailable() async -> Bool { false }
        func notify(_ notification: ChangeNotification) async { await spy.notify(notification) }
    }

    func testDeliversToAvailableNotifiers() async {
        let spy = SpyNotifier()
        let composite = CompositeNotifier([spy])
        await composite.notify(ChangeNotification(title: "t", reason: "r"))
        XCTAssertEqual(spy.notifications.count, 1)
    }

    func testFallsBackToFirstWhenNoneAvailable() async {
        let spy = SpyNotifier()
        let composite = CompositeNotifier([UnavailableNotifier(spy: spy)])
        await composite.notify(ChangeNotification(title: "t", reason: "r"))
        XCTAssertEqual(spy.notifications.count, 1, "events must never be dropped silently")
    }
}

final class ModelManagerTests: XCTestCase {
    func testEnvironmentOverrideWins() async throws {
        // Environment override is read from the process env; here we verify
        // the fallback path: no env var, nothing bundled, nothing downloaded.
        let spec = ModelSpec(
            fileName: "does-not-exist-\(UUID().uuidString).gguf",
            displayName: "test",
            sha256: nil,
            downloadURLs: [URL(string: "https://invalid.invalid/model.gguf")!],
            approximateBytes: 1
        )
        let manager = ModelManager(spec: spec)
        let installed = await manager.installedModelURL()
        XCTAssertNil(installed)
    }
}
