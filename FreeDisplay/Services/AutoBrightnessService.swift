import Foundation
import IOKit
import CoreGraphics

/// Reads the built-in ambient light sensor via IOKit's AppleLMUController and maps lux → brightness.
/// When enabled, it periodically polls the sensor and adjusts display brightness through BrightnessService.
@MainActor
final class AutoBrightnessService: ObservableObject, @unchecked Sendable {
    static let shared = AutoBrightnessService()
    private init() {
        loadPrefs()
    }

    // MARK: - State

    @Published var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                startPolling()
            } else {
                stopPolling()
            }
            savePrefs()
        }
    }

    /// 0.0 – 1.0. Higher = faster / more aggressive adjustment.
    @Published var sensitivity: Double = 0.5 {
        didSet { savePrefs() }
    }

    /// Last raw lux reading (0 = unavailable / no sensor).
    @Published private(set) var lastLux: Double = 0

    // MARK: - Private

    private var pollingTask: Task<Void, Never>?
    private let pollingInterval: TimeInterval = 2.0  // seconds

    // MARK: - Ambient Light Sensor

    /// Reads the ambient light from AppleLMUController.
    /// Returns the average of left+right sensor channels, or nil if not available.
    nonisolated func readAmbientLux() -> Double? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleLMUController")
        )
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var dataPort: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &dataPort) == KERN_SUCCESS else { return nil }
        defer { IOServiceClose(dataPort) }

        // Selector 0 returns two UInt64 ambient light sensor values (left and right).
        var outputCount: UInt32 = 2
        var output: [UInt64] = [0, 0]
        var outputStructSize: Int = 0
        let kr = IOConnectCallMethod(
            dataPort,
            0,          // selector
            nil, 0,     // input scalars (none)
            nil, 0,     // input struct (none)
            &output, &outputCount,
            nil, &outputStructSize  // output struct (none)
        )
        guard kr == KERN_SUCCESS, outputCount >= 2 else { return nil }

        // Values are raw sensor counts. Average both channels, then scale to approximate lux.
        let rawAvg = Double(output[0] + output[1]) / 2.0
        // Scale factor is empirical; Apple uses 0.0001-ish internally on some models.
        let lux = rawAvg / 1_000_000.0 * 1_000.0  // rough mapping to 0–1000 lux range
        return max(0, lux)
    }

    // MARK: - Brightness Mapping

    /// Maps ambient lux to a target brightness percentage [0, 100].
    /// Uses a logarithmic curve; sensitivity shifts the curve offset.
    func luxToBrightness(_ lux: Double) -> Double {
        guard lux > 0 else { return max(5.0, 20.0 - sensitivity * 15.0) }

        // log scale: log10(1) = 0 → 0% dark,  log10(1000) = 3 → 100% bright
        let logLux = log10(lux + 1.0) / log10(1001.0)   // normalise to [0, 1]
        // sensitivity shifts midpoint: 0 = compressed low end, 1 = expanded low end
        let adjusted = pow(logLux, 1.0 - sensitivity * 0.6)
        let brightness = max(5.0, min(100.0, adjusted * 100.0))
        return brightness
    }

    // MARK: - Polling

    private func startPolling() {
        stopPolling()
        pollingTask = Task {
            while !Task.isCancelled {
                if let lux = self.readAmbientLux() {
                    await self.applyBrightness(lux: lux)
                }
                try? await Task.sleep(nanoseconds: UInt64(self.pollingInterval * 1_000_000_000))
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    @MainActor
    private func applyBrightness(lux: Double) {
        lastLux = lux
        let targetBrightness = luxToBrightness(lux)

        // Apply to all active displays
        let displays = DisplayManagerAccessor.shared.displays
        for display in displays {
            // Only adjust if the difference is meaningful (avoid micro-jitter)
            let current = display.brightness
            if abs(current - targetBrightness) >= 2.0 {
                BrightnessService.shared.setBrightness(targetBrightness, for: display)
                display.brightness = targetBrightness
            }
        }
    }

    // MARK: - Persistence

    private let enabledKey = "AutoBrightnessEnabled"
    private let sensitivityKey = "AutoBrightnessSensitivity"

    private func loadPrefs() {
        isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        if UserDefaults.standard.object(forKey: sensitivityKey) != nil {
            sensitivity = UserDefaults.standard.double(forKey: sensitivityKey)
        }
    }

    private func savePrefs() {
        UserDefaults.standard.set(isEnabled, forKey: enabledKey)
        UserDefaults.standard.set(sensitivity, forKey: sensitivityKey)
    }
}

// MARK: - Display Manager Accessor

/// Thin wrapper so AutoBrightnessService can reach displays without a direct EnvironmentObject.
@MainActor
final class DisplayManagerAccessor: ObservableObject {
    static let shared = DisplayManagerAccessor()
    var displays: [DisplayInfo] = []
    private init() {}
}
