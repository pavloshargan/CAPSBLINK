import AppKit
import CapsBlinkKit
import CapsBlinkLlama
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var urlString: String {
        didSet { settings.urlString = urlString }
    }
    var watchInstruction: String {
        didSet { settings.watchInstruction = watchInstruction }
    }
    var intervalSeconds: Double {
        didSet { settings.interval = intervalSeconds }
    }
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? start() : stopWatching()
        }
    }
    private(set) var status: WatcherStatus = .idle
    private(set) var hasInputMonitoring = CapsLockLED.hasPermission

    private let settings = SettingsStore()
    private let led = CapsLockLED()
    private let watcher: PageWatcher

    init() {
        urlString = settings.urlString
        watchInstruction = settings.watchInstruction
        intervalSeconds = settings.interval
        watcher = PageWatcher(
            notifier: CapsLockBlinkNotifier(led: led),
            classifierFactory: LlamaClassifierFactory.make()
        )
        let stream = watcher.statusStream
        Task { [weak self] in
            for await status in stream {
                self?.status = status
            }
        }
    }

    // MARK: - Actions

    private func start() {
        guard let url = validatedURL else {
            status = .error("Enter a valid http(s) URL first")
            isEnabled = false
            return
        }
        hasInputMonitoring = CapsLockLED.hasPermission
        if !hasInputMonitoring {
            CapsLockLED.requestPermission()
        }
        let configuration = PageWatcher.Configuration(
            url: url,
            interval: intervalSeconds,
            watchInstruction: watchInstruction
        )
        Task { await watcher.start(configuration) }
    }

    private func stopWatching() {
        Task {
            await watcher.stop()
            await watcher.unloadClassifier() // release the model's memory
        }
    }

    var validatedURL: URL? {
        var candidate = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }
        if !candidate.contains("://") {
            candidate = "https://" + candidate
        }
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host() != nil
        else { return nil }
        return url
    }

    func testBlink() {
        CapsLockLED.requestPermission()
        Task {
            try? await led.blink(times: 4)
            hasInputMonitoring = CapsLockLED.hasPermission
        }
    }

    func resetInstructionToDefault() {
        settings.resetWatchInstruction()
        watchInstruction = SettingsStore.defaultWatchInstruction
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

    // MARK: - Presentation

    var statusColor: NSColor {
        switch status {
        case .idle: return .systemGray
        case .preparingModel: return .systemOrange
        case .watching: return .systemGreen
        case .evaluating: return .systemBlue
        case .notified: return .systemGreen
        case .error: return .systemRed
        }
    }
}
