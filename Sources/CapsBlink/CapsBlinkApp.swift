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
        WindowGroup("CapsBlink") {
            ContentView(model: model)
        }
        .windowResizability(.contentSize)
    }
}
