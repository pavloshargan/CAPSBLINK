import CoreGraphics
import Foundation
import IOKit.hid

public enum CapsLockLEDError: LocalizedError {
    case openFailed(IOReturn)
    case noLEDFound

    public var errorDescription: String? {
        switch self {
        case .openFailed:
            return "Could not open the keyboard. Grant CapsBlink access under "
                + "System Settings → Privacy & Security → Input Monitoring."
        case .noLEDFound:
            return "No keyboard with a controllable Caps Lock LED was found."
        }
    }
}

/// Low-level Caps Lock LED control via IOKit HID.
///
/// This drives the LED *output element* of connected keyboards directly, so
/// blinking never toggles the actual Caps Lock modifier — typing is
/// unaffected. After a blink sequence the LED is restored to mirror the real
/// modifier state.
///
/// macOS requires the Input Monitoring privacy permission to open keyboard
/// HID devices (even for output). Use `hasPermission` / `requestPermission`
/// to drive the permission UX.
public final class CapsLockLED: @unchecked Sendable {
    private let manager: IOHIDManager
    private var opened = false
    private let lock = NSLock()

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches: [[String: Int]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keypad],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
    }

    deinit {
        if opened {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    // MARK: - Permission

    public static var hasPermission: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Triggers the system permission prompt (once); returns the current state.
    @discardableResult
    public static func requestPermission() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    // MARK: - LED control

    /// Whether at least one connected keyboard exposes a Caps Lock LED we can drive.
    public func isLEDAvailable() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard (try? openIfNeeded()) != nil else { return false }
        return !capsLockLEDElements().isEmpty
    }

    /// Sets the Caps Lock LED on every keyboard that exposes one.
    public func setLED(on: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        try openIfNeeded()
        let elements = capsLockLEDElements()
        guard !elements.isEmpty else { throw CapsLockLEDError.noLEDFound }
        for (device, element) in elements {
            let value = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, 0, on ? 1 : 0)
            IOHIDDeviceSetValue(device, element, value)
        }
    }

    /// Blinks the LED and then restores it to the real Caps Lock modifier state.
    public func blink(times: Int = 8, onMilliseconds: UInt64 = 140, offMilliseconds: UInt64 = 110) async throws {
        for _ in 0..<times {
            try setLED(on: true)
            try await Task.sleep(nanoseconds: onMilliseconds * 1_000_000)
            try setLED(on: false)
            try await Task.sleep(nanoseconds: offMilliseconds * 1_000_000)
        }
        restoreToModifierState()
    }

    /// Re-syncs the LED with the actual Caps Lock modifier so we never leave
    /// the light lying about the keyboard state.
    public func restoreToModifierState() {
        let capsLockActive = CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift)
        try? setLED(on: capsLockActive)
    }

    // MARK: - Internals

    private func openIfNeeded() throws {
        guard !opened else { return }
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            throw CapsLockLEDError.openFailed(result)
        }
        opened = true
    }

    private func capsLockLEDElements() -> [(IOHIDDevice, IOHIDElement)] {
        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return []
        }
        let match: [String: Int] = [
            kIOHIDElementUsagePageKey: kHIDPage_LEDs,
            kIOHIDElementUsageKey: kHIDUsage_LED_CapsLock,
        ]
        var results: [(IOHIDDevice, IOHIDElement)] = []
        for device in deviceSet {
            guard let elements = IOHIDDeviceCopyMatchingElements(
                device, match as CFDictionary, IOOptionBits(kIOHIDOptionsTypeNone)
            ) as? [IOHIDElement] else { continue }
            for element in elements {
                results.append((device, element))
            }
        }
        return results
    }
}
