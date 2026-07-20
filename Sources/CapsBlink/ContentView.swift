import CapsBlinkKit
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var settingsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CapsBlink").font(.headline)
                Text("Blinks Caps Lock when the page meaningfully changes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("https://example.com/live-scores", text: $model.urlString)
                .textFieldStyle(.roundedBorder)
                .disabled(model.isEnabled)

            Toggle("Watch this page", isOn: $model.isEnabled)
                .toggleStyle(.switch)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(Color(model.statusColor))
                    .frame(width: 7, height: 7)
                Text(model.status.displayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

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

            DisclosureGroup("Settings", isExpanded: $settingsExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What to watch for")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $model.watchInstruction)
                        .font(.caption)
                        .frame(height: 76)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.3))
                        )
                    HStack {
                        Button("Reset to sports default") {
                            model.resetInstructionToDefault()
                        }
                        .font(.caption)
                        Spacer()
                    }
                    Picker("Check every", selection: $model.intervalSeconds) {
                        Text("30 s").tag(30.0)
                        Text("1 min").tag(60.0)
                        Text("2 min").tag(120.0)
                        Text("5 min").tag(300.0)
                    }
                    .pickerStyle(.menu)
                    .font(.caption)
                }
                .padding(.top, 6)
            }
            .font(.caption)

            Divider()

            HStack {
                Button("Test blink") { model.testBlink() }
                Spacer()
                Button("Quit") { model.quit() }
            }
            .font(.caption)
        }
        .padding(12)
        .frame(width: 320)
    }
}
