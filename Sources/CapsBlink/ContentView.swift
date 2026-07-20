import CapsBlinkKit
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "capslock.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(model.isEnabled ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("CapsBlink").font(.title2.bold())
                    Text("Blinks the Caps Lock LED when the page meaningfully changes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("Page") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("https://example.com/live-scores", text: $model.urlString)
                        .textFieldStyle(.roundedBorder)
                        .disabled(model.isEnabled)

                    Toggle("Enabled — watch this page", isOn: $model.isEnabled)
                        .toggleStyle(.checkbox)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Circle()
                            .fill(Color(model.statusColor))
                            .frame(width: 8, height: 8)
                        Text(model.status.displayText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("What to watch for") {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $model.watchInstruction)
                        .font(.body)
                        .frame(height: 90)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.25))
                        )
                    HStack {
                        Button("Reset to sports default") {
                            model.resetInstructionToDefault()
                        }
                        Spacer()
                        Picker("Check every", selection: $model.intervalSeconds) {
                            Text("30 s").tag(30.0)
                            Text("1 min").tag(60.0)
                            Text("2 min").tag(120.0)
                            Text("5 min").tag(300.0)
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                }
                .padding(6)
            }

            if !model.hasInputMonitoring {
                GroupBox {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Blinking the LED needs the Input Monitoring permission.")
                                .font(.caption)
                            Button("Open Privacy Settings…") {
                                model.openInputMonitoringSettings()
                            }
                            .font(.caption)
                        }
                        Spacer()
                    }
                    .padding(4)
                }
            }

            HStack {
                Button("Test blink") { model.testBlink() }
                Spacer()
                Button("Quit") { model.quit() }
            }
        }
        .padding(16)
        .frame(width: 460)
    }
}
