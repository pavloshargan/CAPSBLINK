import Foundation

/// A local coding agent whose activity can be observed through the session
/// transcript files it writes while working.
public struct AgentKind: Sendable, Hashable, Identifiable {
    public let id: String
    public let displayName: String
    /// Directories whose contents are appended to while the agent works.
    public let transcriptRoots: [URL]
    /// Only files with this extension count as activity.
    public let fileExtension: String

    public init(id: String, displayName: String, transcriptRoots: [URL], fileExtension: String = "jsonl") {
        self.id = id
        self.displayName = displayName
        self.transcriptRoots = transcriptRoots
        self.fileExtension = fileExtension
    }

    /// Claude Code appends to `~/.claude/projects/<project>/<session>.jsonl`
    /// for every message and tool call in a session.
    public static let claudeCode = AgentKind(
        id: "claude",
        displayName: "Claude Code",
        transcriptRoots: [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        ]
    )

    /// Codex CLI appends to `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`.
    public static let codex = AgentKind(
        id: "codex",
        displayName: "Codex",
        transcriptRoots: [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        ]
    )

    public static let all: [AgentKind] = [.claudeCode, .codex]

    public var isInstalled: Bool {
        transcriptRoots.contains { FileManager.default.fileExists(atPath: $0.path) }
    }
}

/// Where an agent currently is in its work cycle.
public enum AgentActivityState: Sendable, Equatable {
    case notInstalled
    case idle
    case working(since: Date)
    /// The agent was working and has gone quiet — it finished (or is waiting
    /// for the user's input). This is the state that triggers the blink.
    case finished(at: Date)
}

public struct AgentStatus: Sendable, Equatable, Identifiable {
    public let kind: AgentKind
    public let state: AgentActivityState

    public var id: String { kind.id }

    public init(kind: AgentKind, state: AgentActivityState) {
        self.kind = kind
        self.state = state
    }
}
