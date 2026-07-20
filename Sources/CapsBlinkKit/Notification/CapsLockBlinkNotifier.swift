import Foundation

/// Primary notifier: blinks the Caps Lock LED in short bursts.
public struct CapsLockBlinkNotifier: ChangeNotifier {
    public struct Pattern: Sendable {
        public var bursts: Int
        public var blinksPerBurst: Int
        public var pauseBetweenBurstsMilliseconds: UInt64

        public init(bursts: Int = 2, blinksPerBurst: Int = 6, pauseBetweenBurstsMilliseconds: UInt64 = 600) {
            self.bursts = bursts
            self.blinksPerBurst = blinksPerBurst
            self.pauseBetweenBurstsMilliseconds = pauseBetweenBurstsMilliseconds
        }
    }

    private let led: CapsLockLED
    private let pattern: Pattern

    public init(led: CapsLockLED = CapsLockLED(), pattern: Pattern = Pattern()) {
        self.led = led
        self.pattern = pattern
    }

    public func isAvailable() async -> Bool {
        CapsLockLED.hasPermission && led.isLEDAvailable()
    }

    public func notify(_ notification: ChangeNotification) async {
        for burst in 0..<pattern.bursts {
            try? await led.blink(times: pattern.blinksPerBurst)
            if burst < pattern.bursts - 1 {
                try? await Task.sleep(nanoseconds: pattern.pauseBetweenBurstsMilliseconds * 1_000_000)
            }
        }
        led.restoreToModifierState()
    }
}
