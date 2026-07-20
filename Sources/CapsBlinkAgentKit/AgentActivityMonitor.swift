import CapsBlinkKit
import Foundation

/// Watches local coding agents (Claude Code, Codex) through their transcript
/// directories and drives a state machine per agent:
///
///     idle → working (transcript being written) → finished (writes stopped) → idle
///
/// Entering `finished` fires the notifier (Caps Lock blink): the agent is done
/// or waiting for input — time to switch back to the terminal.
public actor AgentActivityMonitor {
    public struct Configuration: Sendable {
        public var agents: [AgentKind]
        /// No writes for this long while working → the agent is considered done.
        /// Long-running silent tool calls can exceed this; prefer a spurious
        /// blink over a late one.
        public var quietThreshold: TimeInterval
        /// Activity shorter than this never triggers a "finished" blink
        /// (filters out one-off file touches).
        public var minimumActivityDuration: TimeInterval
        /// How long the "finished" badge stays before returning to idle.
        public var finishedDisplayDuration: TimeInterval

        public init(
            agents: [AgentKind] = AgentKind.all,
            quietThreshold: TimeInterval = 10,
            minimumActivityDuration: TimeInterval = 3,
            finishedDisplayDuration: TimeInterval = 120
        ) {
            self.agents = agents
            self.quietThreshold = quietThreshold
            self.minimumActivityDuration = minimumActivityDuration
            self.finishedDisplayDuration = finishedDisplayDuration
        }
    }

    private let notifier: any ChangeNotifier
    private var configuration: Configuration
    private var stream: DirectoryEventStream?
    private var tickTask: Task<Void, Never>?

    private var lastEventAt: [String: Date] = [:]
    private var workingSince: [String: Date] = [:]
    private var states: [String: AgentActivityState] = [:]

    public nonisolated let statusStream: AsyncStream<[AgentStatus]>
    private let statusContinuation: AsyncStream<[AgentStatus]>.Continuation

    public init(notifier: any ChangeNotifier, configuration: Configuration = Configuration()) {
        self.notifier = notifier
        self.configuration = configuration
        (statusStream, statusContinuation) = AsyncStream.makeStream(
            of: [AgentStatus].self,
            bufferingPolicy: .bufferingNewest(4)
        )
    }

    public func start() {
        stop()
        for agent in configuration.agents {
            states[agent.id] = agent.isInstalled ? .idle : .notInstalled
        }
        publish()

        let agents = configuration.agents
        let rootPrefixes: [String: [String]] = Dictionary(uniqueKeysWithValues: agents.map { kind in
            (kind.id, kind.transcriptRoots.map { Self.canonical($0.path) })
        })
        let eventStream = DirectoryEventStream { [weak self] path in
            guard let self else { return }
            let eventPath = Self.canonical(path)
            guard let agent = agents.first(where: { kind in
                eventPath.hasSuffix("." + kind.fileExtension)
                    && rootPrefixes[kind.id, default: []].contains { eventPath.hasPrefix($0) }
            }) else { return }
            Task { await self.recordActivity(for: agent) }
        }
        eventStream.start(paths: configuration.agents.flatMap { $0.transcriptRoots.map(\.path) })
        stream = eventStream

        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self?.tick()
            }
        }
    }

    public func stop() {
        stream?.stop()
        stream = nil
        tickTask?.cancel()
        tickTask = nil
        lastEventAt.removeAll()
        workingSince.removeAll()
        states = states.mapValues { _ in AgentActivityState.idle }
    }

    private func recordActivity(for agent: AgentKind) {
        let now = Date.now
        lastEventAt[agent.id] = now
        if workingSince[agent.id] == nil {
            workingSince[agent.id] = now
        }
        if case .working = states[agent.id] {} else {
            states[agent.id] = .working(since: workingSince[agent.id] ?? now)
            publish()
        }
    }

    private func tick() async {
        let now = Date.now
        var changed = false
        for agent in configuration.agents {
            guard case .working(let since) = states[agent.id],
                  let lastEvent = lastEventAt[agent.id]
            else {
                // Let stale "finished" badges decay back to idle.
                if case .finished(let at) = states[agent.id],
                   now.timeIntervalSince(at) > configuration.finishedDisplayDuration {
                    states[agent.id] = .idle
                    changed = true
                }
                continue
            }
            guard now.timeIntervalSince(lastEvent) >= configuration.quietThreshold else { continue }

            workingSince[agent.id] = nil
            if now.timeIntervalSince(since) - configuration.quietThreshold
                >= configuration.minimumActivityDuration {
                states[agent.id] = .finished(at: now)
                changed = true
                await notifier.notify(ChangeNotification(
                    title: agent.displayName,
                    reason: "\(agent.displayName) finished and is waiting for you"
                ))
            } else {
                states[agent.id] = .idle
                changed = true
            }
        }
        if changed {
            publish()
        }
    }

    /// FSEvents reports firmlink-resolved paths (`/private/var/…`) while
    /// callers configure `/var/…`-style paths — and `resolvingSymlinksInPath`
    /// deliberately leaves `/var` & friends alone. Strip the `/private`
    /// prefix from both sides before comparing.
    static func canonical(_ path: String) -> String {
        for prefix in ["/private/var/", "/private/tmp/", "/private/etc/"] where path.hasPrefix(prefix) {
            return String(path.dropFirst("/private".count))
        }
        return path
    }

    private func publish() {
        let snapshot = configuration.agents.map {
            AgentStatus(kind: $0, state: states[$0.id] ?? .idle)
        }
        statusContinuation.yield(snapshot)
    }
}
