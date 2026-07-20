import AppKit
import SwiftUI

@main
struct CapsBlinkApp: App {
    @State private var model = AppModel()

    init() {
        // When launched as a bare executable (swift run / Xcode running the
        // SPM target) there is no Info.plist, so claim regular-app status
        // explicitly to get a Dock icon and key window.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        // Closing this window does NOT stop watching: the model (and its
        // watcher) belong to the app, which keeps running in the background.
        // Reopen the window from the Dock icon or the ⇪ menu bar item.
        WindowGroup("CapsBlink", id: "main") {
            ContentView(model: model)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Image(systemName: model.isEnabled ? "capslock.fill" : "capslock")
        }
    }
}

private struct MenuBarContent: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.status.displayText)
        Toggle("Watching enabled", isOn: $model.isEnabled)
        Divider()
        Button("Open CapsBlink…") {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}
