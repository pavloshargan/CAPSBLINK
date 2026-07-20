import AppKit
import CapsBlinkAgentKit
import CapsBlinkKit
import Foundation
import Observation

@MainActor
@Observable
final class AgentsModel {
    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            Task { isEnabled ? await monitor.start() : await monitor.stop() }
        }
    }
    private(set) var statuses: [AgentStatus] = AgentKind.all.map {
        AgentStatus(kind: $0, state: $0.isInstalled ? .idle : .notInstalled)
    }
    private(set) var hasInputMonitoring = CapsLockLED.hasPermission

    private let led = CapsLockLED()
    private let monitor: AgentActivityMonitor

    init() {
        monitor = AgentActivityMonitor(notifier: CapsLockBlinkNotifier(led: led))
        let stream = monitor.statusStream
        Task { [weak self] in
            for await snapshot in stream {
                self?.statuses = snapshot
            }
        }
        Task { [monitor] in
            CapsLockLED.requestPermission()
            await monitor.start()
        }
    }

    var menuBarSymbol: String {
        if statuses.contains(where: { if case .finished = $0.state { return true } else { return false } }) {
            return "capslock.fill"
        }
        return "capslock"
    }

    func testBlink() {
        CapsLockLED.requestPermission()
        Task {
            try? await led.blink(times: 4)
            hasInputMonitoring = CapsLockLED.hasPermission
        }
    }

    func openInputMonitoringSettings() {
        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        if let url = URL(string: pane) {
            NSWorkspace.shared.open(url)
        }
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}
