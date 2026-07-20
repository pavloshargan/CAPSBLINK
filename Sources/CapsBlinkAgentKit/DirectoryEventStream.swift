import CoreServices
import Foundation

/// Minimal FSEvents wrapper: reports the path of every file event under the
/// given roots. FSEvents is the cheapest way to observe transcript writes —
/// zero polling, near-zero CPU while agents are idle.
final class DirectoryEventStream: @unchecked Sendable {
    private var streamRef: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.pavloshargan.capsblink.fsevents")
    private let handler: @Sendable (String) -> Void

    init(handler: @escaping @Sendable (String) -> Void) {
        self.handler = handler
    }

    /// Returns false when the stream could not be created (e.g. no roots exist).
    @discardableResult
    func start(paths: [String]) -> Bool {
        stop()
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return false }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, eventCount, eventPaths, _, _ in
            guard let info else { return }
            let stream = Unmanaged<DirectoryEventStream>.fromOpaque(info).takeUnretainedValue()
            // With kFSEventStreamCreateFlagUseCFTypes the paths pointer is a CFArray of CFString.
            guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
            for path in paths.prefix(Int(eventCount)) {
                stream.handler(path)
            }
        }

        let flags = FSEventStreamCreateFlags(
            UInt32(kFSEventStreamCreateFlagUseCFTypes)
                | UInt32(kFSEventStreamCreateFlagFileEvents)
                | UInt32(kFSEventStreamCreateFlagNoDefer)
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            existing as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3, // latency: coalesce bursts of writes
            flags
        ) else { return false }

        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return false
        }
        streamRef = stream
        return true
    }

    func stop() {
        guard let stream = streamRef else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        streamRef = nil
    }

    deinit {
        stop()
    }
}
