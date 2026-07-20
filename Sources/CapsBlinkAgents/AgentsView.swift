import CapsBlinkAgentKit
import SwiftUI

struct AgentsView: View {
    @Bindable var model: AgentsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CapsBlink Agents").font(.headline)
                Text("Blinks Caps Lock when a coding agent finishes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("Monitor agents", isOn: $model.isEnabled)
                .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.statuses) { status in
                    AgentRow(status: status)
                }
            }
            .padding(.vertical, 2)

            if !model.hasInputMonitoring {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Caps Lock control needs the Input Monitoring permission.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Button("Open Privacy Settings…") {
                        model.openInputMonitoringSettings()
                    }
                    .font(.caption)
                }
            }

            Divider()

            HStack {
                Button("Test blink") { model.testBlink() }
                Spacer()
                Button("Quit") { model.quit() }
            }
            .font(.caption)
        }
        .padding(12)
        .frame(width: 300)
    }
}

private struct AgentRow: View {
    let status: AgentStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(status.kind.displayName)
                .font(.callout)
            Spacer()
            Text(stateText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var color: Color {
        switch status.state {
        case .notInstalled: return .gray.opacity(0.4)
        case .idle: return .gray
        case .working: return .orange
        case .finished: return .green
        }
    }

    private var stateText: String {
        switch status.state {
        case .notInstalled:
            return "Not detected"
        case .idle:
            return "Idle"
        case .working(let since):
            return "Working since \(since.formatted(date: .omitted, time: .shortened))"
        case .finished(let at):
            return "Finished \(at.formatted(date: .omitted, time: .shortened))"
        }
    }
}
