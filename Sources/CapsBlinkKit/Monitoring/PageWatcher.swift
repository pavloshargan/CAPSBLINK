import Foundation

/// Builds the classifier on demand (typically: ensure model file → load LLM).
/// Reported progress is 0...1 for downloads, `nil` for indeterminate loading.
public typealias ClassifierFactory = @Sendable (
    _ progress: @escaping @Sendable (Double?) -> Void
) async throws -> any ChangeClassifier

/// Orchestrates the watch loop:
///
///     fetch → extract text → deterministic diff → (only if changed) LLM verdict → blink
///
/// The model is loaded once when watching starts and reused for every check;
/// between checks the watcher is fully idle (a single sleeping task).
public actor PageWatcher {
    public struct Configuration: Sendable {
        public var url: URL
        public var interval: TimeInterval
        public var watchInstruction: String

        public init(url: URL, interval: TimeInterval = SettingsStore.defaultInterval,
                    watchInstruction: String = SettingsStore.defaultWatchInstruction) {
            self.url = url
            self.interval = max(5, interval)
            self.watchInstruction = watchInstruction
        }
    }

    private let fetcher: PageFetcher
    private let extractor: HTMLTextExtractor
    private let detector: ChangeDetector
    private let notifier: any ChangeNotifier
    private let snapshots: SnapshotStore
    private let classifierFactory: ClassifierFactory

    private var classifier: (any ChangeClassifier)?
    private var loopTask: Task<Void, Never>?
    private var previousText: String?
    private var consecutiveFailures = 0

    public nonisolated let statusStream: AsyncStream<WatcherStatus>
    private let statusContinuation: AsyncStream<WatcherStatus>.Continuation

    /// How many consecutive fetch failures before surfacing an error status.
    private static let failureThreshold = 3

    public init(
        fetcher: PageFetcher = PageFetcher(),
        extractor: HTMLTextExtractor = HTMLTextExtractor(),
        detector: ChangeDetector = ChangeDetector(),
        notifier: any ChangeNotifier,
        snapshots: SnapshotStore = SnapshotStore(),
        classifierFactory: @escaping ClassifierFactory
    ) {
        self.fetcher = fetcher
        self.extractor = extractor
        self.detector = detector
        self.notifier = notifier
        self.snapshots = snapshots
        self.classifierFactory = classifierFactory
        (statusStream, statusContinuation) = AsyncStream.makeStream(
            of: WatcherStatus.self,
            bufferingPolicy: .bufferingNewest(8)
        )
    }

    public func start(_ configuration: Configuration) {
        stop()
        loopTask = Task { [weak self] in
            await self?.run(configuration)
        }
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
        previousText = nil
        consecutiveFailures = 0
        emit(.idle)
    }

    /// Frees the LLM (and its memory) — called when the user disables watching.
    public func unloadClassifier() {
        classifier = nil
    }

    private func emit(_ status: WatcherStatus) {
        statusContinuation.yield(status)
    }

    // MARK: - Loop

    private func run(_ configuration: Configuration) async {
        do {
            if classifier == nil {
                emit(.preparingModel(progress: nil))
                classifier = try await classifierFactory { [weak self] progress in
                    Task { await self?.emit(.preparingModel(progress: progress)) }
                }
            }
        } catch {
            // Degrade rather than die: the heuristic classifier keeps the
            // watcher useful (it over-notifies instead of missing events).
            emit(.error("Model unavailable, using basic detection (\(error.localizedDescription))"))
            classifier = HeuristicChangeClassifier()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }

        // Baseline: reuse the persisted snapshot if we have one so an app
        // relaunch doesn't forget what the page looked like.
        if let stored = snapshots.load(for: configuration.url) {
            previousText = stored.text
        }

        while !Task.isCancelled {
            await checkOnce(configuration)
            do {
                try await Task.sleep(nanoseconds: UInt64(configuration.interval * 1_000_000_000))
            } catch {
                break // cancelled
            }
        }
    }

    public func checkOnce(_ configuration: Configuration) async {
        do {
            let result = try await fetcher.fetch(configuration.url)
            consecutiveFailures = 0

            guard case .content(let html) = result else {
                emit(.watching(lastChecked: .now)) // 304 — nothing changed
                return
            }

            let text = extractor.text(fromHTML: html)
            defer {
                snapshots.save(PageSnapshot(text: text), for: configuration.url)
                previousText = text
            }

            guard let previous = previousText else {
                emit(.watching(lastChecked: .now)) // first observation = baseline
                return
            }
            guard let change = detector.detect(previous: previous, current: text) else {
                emit(.watching(lastChecked: .now))
                return
            }

            emit(.evaluating)
            let context = ChangeContext(
                url: configuration.url,
                change: change,
                watchInstruction: configuration.watchInstruction
            )
            let assessment: ChangeAssessment
            do {
                assessment = try await (classifier ?? HeuristicChangeClassifier()).assess(context)
            } catch {
                // Inference failed — fall back to "notify", missing an update
                // is worse than a spurious blink.
                assessment = ChangeAssessment(shouldNotify: true, reason: "Page changed (classifier error)")
            }

            if assessment.shouldNotify {
                await notifier.notify(ChangeNotification(
                    title: configuration.url.host() ?? configuration.url.absoluteString,
                    reason: assessment.reason
                ))
                emit(.notified(reason: assessment.reason, at: .now))
            } else {
                emit(.watching(lastChecked: .now))
            }
        } catch {
            consecutiveFailures += 1
            if consecutiveFailures >= Self.failureThreshold {
                emit(.error(error.localizedDescription))
            } else {
                emit(.watching(lastChecked: .now))
            }
        }
    }
}
