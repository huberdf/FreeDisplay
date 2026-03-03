import Foundation
import IOKit
import IOKit.graphics
import CoreGraphics

/// Unified brightness service.
/// - Internal display: uses IODisplayGetFloatParameter / IODisplaySetFloatParameter
/// - External display: uses DDCService VCP 0x10
final class BrightnessService: @unchecked Sendable {
    static let shared = BrightnessService()
    private init() {}

    // MARK: - Public API

    /// Reads brightness asynchronously and updates display.brightness on MainActor.
    /// Must be called from a @MainActor context (or within a Task @MainActor).
    @MainActor
    func refreshBrightness(for display: DisplayInfo) {
        let isBuiltin  = display.isBuiltin
        let displayID  = display.displayID

        if isBuiltin {
            if let b = getInternalBrightness() {
                display.brightness = b
            }
        } else {
            DDCService.shared.readAsync(
                displayID: displayID,
                command: DDCService.brightnessVCP
            ) { result in
                guard let result = result, result.max > 0 else { return }
                let brightness = Double(result.current) / Double(result.max) * 100.0
                Task { @MainActor in display.brightness = brightness }
            }
        }
    }

    /// Sets brightness. Internal display is set synchronously; external uses async DDC.
    /// Must be called from a @MainActor context.
    @MainActor
    func setBrightness(_ brightness: Double, for display: DisplayInfo) {
        let clamped   = max(0.0, min(100.0, brightness))
        let isBuiltin = display.isBuiltin
        let displayID = display.displayID

        if isBuiltin {
            setInternalBrightness(Float(clamped / 100.0))
        } else {
            DDCService.shared.writeAsync(
                displayID: displayID,
                command: DDCService.brightnessVCP,
                value: UInt16(clamped)
            )
        }
    }

    // MARK: - Internal Display (IODisplayGetFloatParameter)

    private func getInternalBrightness() -> Double? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iter
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iter) }
            var value: Float = 0
            if IODisplayGetFloatParameter(
                service, 0, "brightness" as CFString, &value
            ) == KERN_SUCCESS {
                return Double(value) * 100.0
            }
        }
        return nil
    }

    private func setInternalBrightness(_ value: Float) {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iter
        ) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iter) }
            if IODisplaySetFloatParameter(
                service, 0, "brightness" as CFString, value
            ) == KERN_SUCCESS { return }
        }
    }
}
