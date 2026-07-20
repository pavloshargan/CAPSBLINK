import SwiftUI

@main
struct CapsBlinkApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView(model: model)
        } label: {
            Image(systemName: model.isEnabled ? "capslock.fill" : "capslock")
        }
        .menuBarExtraStyle(.window)
    }
}
