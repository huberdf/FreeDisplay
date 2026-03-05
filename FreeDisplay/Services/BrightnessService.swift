import Foundation
import IOKit
import IOKit.graphics
import CoreGraphics

@_silgen_name("CGDisplayIOServicePort")
private func CGDisplayIOServicePort(_ display: CGDirectDisplayID) -> io_service_t

final class BrightnessService: @unchecked Sendable {
    static let shared = BrightnessService()
    private init() {}

    private let queue = DispatchQueue(label: "com.freedisplay.brightness", qos: .userInitiated)

    // MARK: - Manual Adjust Cooldown

    /// Set when the user manually adjusts brightness; auto-brightness skips updates for 30 s.
    private(set) var lastManualAdjustDate: Date? = nil
    private let manualAdjustLock = NSLock()

    // MARK: - Software Brightness Factors

    /// Stores the current software brightness factor per display (0.01–1.0).
    private var softwareBrightnessFactors: [CGDirectDisplayID: Double] = [:]
    private let softwareBrightnessLock = NSLock()

    private func softBrightnessKey(for displayID: CGDirectDisplayID) -> String {
        "fd.softBrightness_\(displayID)"
    }

    private func saveSoftwareBrightness(factor: Double, for displayID: CGDirectDisplayID) {
        UserDefaults.standard.set(factor, forKey: softBrightnessKey(for: displayID))
    }

    private func loadSoftwareBrightness(for displayID: CGDirectDisplayID) -> Double? {
        let key = softBrightnessKey(for: displayID)
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return UserDefaults.standard.double(forKey: key)
    }

    /// Returns the current software brightness factor for a display, or nil if not set.
    func currentSoftwareBrightness(for displayID: CGDirectDisplayID) -> Double? {
        softwareBrightnessLock.withLock { softwareBrightnessFactors[displayID] }
    }

    // MARK: - DDC Availability Cache

    /// Tracks whether hardware DDC is available for each external display.
    /// nil  = not yet determined
    /// true = DDC write succeeded at least once
    /// false = DDC write has failed; use software (gamma) fallback
    private var ddcAvailable: [CGDirectDisplayID: Bool] = [:]
    private let ddcAvailableLock = NSLock()

    /// Per-display DDC max brightness value reported by the monitor.
    /// Used to denormalize 0–100% into the display's native DDC range.
    private var ddcMaxBrightness: [CGDirectDisplayID: UInt16] = [:]

    // MARK: - Public API

    @MainActor
    func refreshBrightness(for display: DisplayInfo) async {
        let isBuiltin = display.isBuiltin
        let displayID = display.displayID

        if isBuiltin {
            let brightness = await withCheckedContinuation { continuation in
                queue.async { [weak self] in
                    continuation.resume(returning: self?.getInternalBrightness())
                }
            }
            if let b = brightness {
                display.brightness = b
            }
        } else {
            // First check if DDC is already known to be unavailable; if so skip the
            // async DDC call and just read the current gamma-derived brightness.
            let knownUnavailable: Bool = ddcAvailableLock.withLock {
                ddcAvailable[displayID] == false
            }
            if knownUnavailable {
                // Can't read brightness from gamma tables meaningfully; leave value as-is
                return
            }

            DDCService.shared.readAsync(
                displayID: displayID,
                command: DDCService.brightnessVCP
            ) { [weak self] result in
                guard let self else { return }
                if let result = result, result.max > 0 {
                    let brightness = Double(result.current) / Double(result.max) * 100.0
                    self.ddcAvailableLock.lock()
                    self.ddcAvailable[displayID] = true
                    self.ddcMaxBrightness[displayID] = result.max
                    self.ddcAvailableLock.unlock()
                    Task { @MainActor in display.brightness = brightness }
                } else {
                    // DDC read returned nil; mark unavailable
                    self.ddcAvailableLock.lock()
                    if self.ddcAvailable[displayID] == nil {
                        self.ddcAvailable[displayID] = false
                    }
                    self.ddcAvailableLock.unlock()
                }
            }
        }
    }

    @MainActor
    func setBrightness(_ brightness: Double, for display: DisplayInfo, isAutoAdjust: Bool = false) async {
        let clamped = max(0.0, min(100.0, brightness))
        let isBuiltin = display.isBuiltin
        let displayID = display.displayID

        // Record manual adjust time so auto-brightness can honour the cooldown period.
        if !isAutoAdjust {
            manualAdjustLock.withLock { lastManualAdjustDate = Date() }
        }

        if isBuiltin {
            let value = Float(clamped / 100.0)
            display.brightness = clamped
            queue.async { [weak self] in
                self?.setInternalBrightness(value)
            }
        } else {
            // Check current DDC availability status
            let currentStatus: Bool? = ddcAvailableLock.withLock { ddcAvailable[displayID] }

            if currentStatus == false {
                // DDC known unavailable — go straight to software fallback
                queue.async { [weak self] in
                    self?.setSoftwareBrightness(clamped, for: displayID)
                }
                return
            }

            // Denormalize percentage to display's native DDC range.
            // If max is unknown, default to 100 (safe for most monitors).
            let knownMax: UInt16 = ddcAvailableLock.withLock {
                ddcMaxBrightness[displayID] ?? 100
            }
            let ddcValue = UInt16((clamped / 100.0) * Double(knownMax))

            // Attempt DDC write; if it fails, fall back to gamma table dimming
            DDCService.shared.writeAsync(
                displayID: displayID,
                command: DDCService.brightnessVCP,
                value: ddcValue
            ) { [weak self] success in
                guard let self else { return }
                if success {
                    self.ddcAvailableLock.withLock { self.ddcAvailable[displayID] = true }
                } else {
                    self.ddcAvailableLock.withLock { self.ddcAvailable[displayID] = false }
                    // Apply gamma-based software brightness as fallback (must be on main thread)
                    DispatchQueue.main.async { [weak self] in
                        self?.setSoftwareBrightness(clamped, for: displayID)
                    }
                    #if DEBUG
                    print("[BrightnessService] DDC unavailable for display \(displayID), using software fallback")
                    #endif
                }
            }
        }
    }

    // MARK: - Software Brightness (Gamma Table Fallback)

    /// Applies brightness via gamma table manipulation for displays where DDC is unavailable.
    /// Uses a linear ramp from 0 to `factor` so white level is dimmed while black stays black.
    /// brightness: 0–100 (percentage); never goes fully to 0 to avoid a completely black screen.
    ///
    /// If GammaService has an active adjustment for this display, it delegates to GammaService
    /// so the two do not overwrite each other's CGSetDisplayTransfer* call.
    func setSoftwareBrightness(_ brightness: Double, for displayID: CGDirectDisplayID) {
        let factor = max(0.05, brightness / 100.0)
        softwareBrightnessLock.withLock { softwareBrightnessFactors[displayID] = factor }
        saveSoftwareBrightness(factor: factor, for: displayID)

        // If GammaService has an active adjustment, let it re-apply (it will incorporate the factor).
        if GammaService.shared.hasActiveAdjustment(for: displayID) {
            GammaService.shared.reapply(for: displayID)
            return
        }

        // No active gamma adjustment — write a plain dimmed ramp directly.
        let floatFactor = Float(factor)
        let tableSize: UInt32 = 256
        var red   = [CGGammaValue](repeating: 0, count: Int(tableSize))
        var green = [CGGammaValue](repeating: 0, count: Int(tableSize))
        var blue  = [CGGammaValue](repeating: 0, count: Int(tableSize))

        for i in 0..<Int(tableSize) {
            let v = CGGammaValue(Float(i) / Float(tableSize - 1) * floatFactor)
            red[i]   = v
            green[i] = v
            blue[i]  = v
        }

        let result = CGSetDisplayTransferByTable(displayID, tableSize, &red, &green, &blue)
        #if DEBUG
        if result != CGError.success {
            print("[BrightnessService] CGSetDisplayTransferByTable failed: \(result)")
        } else {
            print("[BrightnessService] software brightness set to \(Int(brightness))% for display \(displayID)")
        }
        #endif
    }

    /// Resets the gamma table for a display back to the identity curve.
    func resetSoftwareBrightness(for displayID: CGDirectDisplayID) {
        let size = 256
        let values = (0..<size).map { CGGammaValue($0) / CGGammaValue(size - 1) }
        var red = values
        var green = values
        var blue = values
        CGSetDisplayTransferByTable(displayID, UInt32(size), &red, &green, &blue)
    }

    /// Returns whether DDC is available for the given display.
    /// nil means not yet determined (first use).
    func isDDCAvailable(for displayID: CGDirectDisplayID) -> Bool? {
        ddcAvailableLock.withLock { ddcAvailable[displayID] }
    }

    /// Clears DDC availability and max brightness cache for a disconnected display.
    /// Call this when a display is removed so stale state cannot pollute a reconnect.
    func invalidateDDCState(for displayID: CGDirectDisplayID) {
        ddcAvailableLock.withLock {
            ddcAvailable.removeValue(forKey: displayID)
            ddcMaxBrightness.removeValue(forKey: displayID)
        }
    }

    /// Re-applies the software brightness for a display after wake from sleep or hot-plug.
    /// Checks in-memory factor first; falls back to UserDefaults so restart is handled too.
    /// No-op if no saved factor < 1.0 exists.
    func reapplySoftwareBrightnessIfNeeded(for display: DisplayInfo) {
        let displayID = display.displayID
        let inMemory = softwareBrightnessLock.withLock { softwareBrightnessFactors[displayID] }
        let factor = inMemory ?? loadSoftwareBrightness(for: displayID)
        guard let f = factor, f < 1.0 else { return }
        // Populate in-memory cache if loaded from disk
        if inMemory == nil {
            softwareBrightnessLock.withLock { softwareBrightnessFactors[displayID] = f }
        }
        setSoftwareBrightness(f * 100.0, for: displayID)
    }

    // MARK: - Internal Display (IODisplayGetFloatParameter)

    private static nonisolated(unsafe) let ioDisplayBrightnessKey = "brightness" as CFString

    /// Returns the io_service_t for the built-in display using CGDisplayIOServicePort.
    /// Falls back to iterating IODisplayConnect services if CGDisplayIOServicePort returns null.
    /// Caller does NOT need to release — CGDisplayIOServicePort returns a non-retained port.
    private func builtinIOService() -> io_service_t? {
        // Find the built-in CGDirectDisplayID
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &displayCount)
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetOnlineDisplayList(displayCount, &displayIDs, &displayCount)

        guard let builtinID = (0..<Int(displayCount))
            .map({ displayIDs[$0] })
            .first(where: { CGDisplayIsBuiltin($0) != 0 }) else {
            return nil
        }

        // CGDisplayIOServicePort returns a non-retained service port (do not release)
        let servicePort = CGDisplayIOServicePort(builtinID)
        if servicePort != MACH_PORT_NULL && servicePort != 0 {
            return servicePort
        }

        return nil
    }

    private func getInternalBrightness() -> Double? {
        // Primary: use CGDisplayIOServicePort to get the specific builtin display service
        if let servicePort = builtinIOService() {
            var value: Float = 0
            if IODisplayGetFloatParameter(
                servicePort, 0, Self.ioDisplayBrightnessKey, &value
            ) == KERN_SUCCESS {
                return Double(value) * 100.0
            }
        }

        // Fallback: iterate IODisplayConnect but only accept services that
        // correspond to a built-in display (matched via CGDisplayIOServicePort cross-check).
        // Build set of known external service ports to exclude them.
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &displayCount)
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetOnlineDisplayList(displayCount, &displayIDs, &displayCount)

        var externalPorts = Set<io_service_t>()
        for i in 0..<Int(displayCount) {
            let id = displayIDs[i]
            if CGDisplayIsBuiltin(id) == 0 {
                let port = CGDisplayIOServicePort(id)
                if port != MACH_PORT_NULL && port != 0 {
                    externalPorts.insert(port)
                }
            }
        }

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
            // Skip services that are known external display ports
            guard !externalPorts.contains(service) else { continue }
            var value: Float = 0
            if IODisplayGetFloatParameter(
                service, 0, Self.ioDisplayBrightnessKey, &value
            ) == KERN_SUCCESS {
                return Double(value) * 100.0
            }
        }
        return nil
    }

    private func setInternalBrightness(_ value: Float) {
        // Primary: use CGDisplayIOServicePort to target only the builtin display service
        if let servicePort = builtinIOService() {
            if IODisplaySetFloatParameter(
                servicePort, 0, Self.ioDisplayBrightnessKey, value
            ) == KERN_SUCCESS {
                #if DEBUG
                print("[BrightnessService] internal brightness set to \(value)")
                #endif
                return
            }
        }

        // Fallback: iterate IODisplayConnect, skipping known external ports
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &displayCount)
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetOnlineDisplayList(displayCount, &displayIDs, &displayCount)

        var externalPorts = Set<io_service_t>()
        for i in 0..<Int(displayCount) {
            let id = displayIDs[i]
            if CGDisplayIsBuiltin(id) == 0 {
                let port = CGDisplayIOServicePort(id)
                if port != MACH_PORT_NULL && port != 0 {
                    externalPorts.insert(port)
                }
            }
        }

        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iter
        ) == KERN_SUCCESS else {
            #if DEBUG
            print("[BrightnessService] setInternalBrightness: no builtin service responded")
            #endif
            return
        }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iter) }
            guard !externalPorts.contains(service) else { continue }
            if IODisplaySetFloatParameter(
                service, 0, Self.ioDisplayBrightnessKey, value
            ) == KERN_SUCCESS {
                #if DEBUG
                print("[BrightnessService] internal brightness set to \(value)")
                #endif
                return
            }
        }
        #if DEBUG
        print("[BrightnessService] setInternalBrightness: no builtin service responded")
        #endif
    }
}
