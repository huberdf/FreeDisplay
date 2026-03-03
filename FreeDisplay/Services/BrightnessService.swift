import Foundation
import IOKit
import IOKit.graphics
import CoreGraphics

final class BrightnessService: @unchecked Sendable {
    static let shared = BrightnessService()
    private init() {}

    private let queue = DispatchQueue(label: "com.freedisplay.brightness", qos: .userInitiated)

    // MARK: - Public API

    @MainActor
    func refreshBrightness(for display: DisplayInfo) async {
        let isBuiltin = display.isBuiltin
        let displayID = display.displayID

        if isBuiltin {
            let brightness = await withCheckedContinuation { continuation in
                queue.async {
                    continuation.resume(returning: self.getInternalBrightness())
                }
            }
            if let b = brightness {
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

    @MainActor
    func setBrightness(_ brightness: Double, for display: DisplayInfo) async {
        let clamped = max(0.0, min(100.0, brightness))
        let isBuiltin = display.isBuiltin
        let displayID = display.displayID

        if isBuiltin {
            let value = Float(clamped / 100.0)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                queue.async {
                    self.setInternalBrightness(value)
                    continuation.resume()
                }
            }
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
