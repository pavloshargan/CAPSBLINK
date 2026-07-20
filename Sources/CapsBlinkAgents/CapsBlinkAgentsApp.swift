import SwiftUI

@main
struct CapsBlinkAgentsApp: App {
    @State private var model = AgentsModel()

    var body: some Scene {
        MenuBarExtra {
            AgentsView(model: model)
        } label: {
            Image(systemName: model.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}
