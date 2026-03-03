import AppKit
import CoreGraphics

/// Per-display software image adjustment parameters.
/// All slider values are in the range -100...+100 with 0 = neutral,
/// except quantizationLevels (2...256, 256 = no quantization).
struct GammaAdjustment {
    var contrast: Double = 0.0          // -100 to +100, 0 = neutral
    var gammaVal: Double = 0.0          // -100 to +100, 0 = neutral (gamma exponent 1.0)
    var gain: Double = 0.0              // -100 to +100, 0 = neutral (multiplier 1.0)
    var colorTemperature: Double = 0.0  // -100 to +100, 0 = neutral (6500 K)
    var rGamma: Double = 0.0            // per-channel gamma offset
    var gGamma: Double = 0.0
    var bGamma: Double = 0.0
    var rGain: Double = 0.0             // per-channel gain offset
    var gGain: Double = 0.0
    var bGain: Double = 0.0
    var quantizationLevels: Int = 256   // 256 = no quantization
    var isInverted: Bool = false
    var isPaused: Bool = false
}

/// Applies software gamma / image adjustments to a display using
/// CoreGraphics CGSetDisplayTransferByFormula / CGSetDisplayTransferByTable.
final class GammaService: @unchecked Sendable {
    static let shared = GammaService()
    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clearSavedState()
            CGDisplayRestoreColorSyncSettings()
        }
    }

    // MARK: - Public API

    /// Apply a complete GammaAdjustment snapshot to the given display.
    func apply(_ adj: GammaAdjustment, for displayID: CGDirectDisplayID) {
        guard !adj.isPaused else { return }
        if adj.quantizationLevels < 256 {
            applyQuantizedTable(adj, for: displayID)
        } else {
            applyFormula(adj, for: displayID)
        }
    }

    /// Apply identity transfer (gamma 1.0) to a single display without
    /// discarding stored parameters. Used by "pause" mode.
    func applyIdentity(for displayID: CGDirectDisplayID) {
        CGSetDisplayTransferByFormula(displayID,
            0.0, 1.0, 1.0,
            0.0, 1.0, 1.0,
            0.0, 1.0, 1.0)
    }

    /// Restore all displays to their ColorSync profile settings
    /// (system-wide reset — no per-display variant in the public API).
    func restoreColorSync() {
        CGDisplayRestoreColorSyncSettings()
    }

    private static let stateKey = "GammaService.savedAdjustment"

    func saveState(_ adj: GammaAdjustment, for displayID: CGDirectDisplayID) {
        let dict: [String: Any] = [
            "displayID": displayID,
            "contrast": adj.contrast,
            "gammaVal": adj.gammaVal,
            "gain": adj.gain,
            "colorTemperature": adj.colorTemperature,
            "rGamma": adj.rGamma, "gGamma": adj.gGamma, "bGamma": adj.bGamma,
            "rGain": adj.rGain,   "gGain": adj.gGain,   "bGain": adj.bGain,
            "quantizationLevels": adj.quantizationLevels,
            "isInverted": adj.isInverted,
            "isPaused": adj.isPaused
        ]
        UserDefaults.standard.set(dict, forKey: GammaService.stateKey)
    }

    func loadSavedState(for displayID: CGDirectDisplayID) -> GammaAdjustment? {
        guard let dict = UserDefaults.standard.dictionary(forKey: GammaService.stateKey),
              let savedID = dict["displayID"] as? CGDirectDisplayID,
              savedID == displayID else { return nil }
        var adj = GammaAdjustment()
        adj.contrast           = dict["contrast"]           as? Double ?? 0
        adj.gammaVal           = dict["gammaVal"]           as? Double ?? 0
        adj.gain               = dict["gain"]               as? Double ?? 0
        adj.colorTemperature   = dict["colorTemperature"]   as? Double ?? 0
        adj.rGamma             = dict["rGamma"]             as? Double ?? 0
        adj.gGamma             = dict["gGamma"]             as? Double ?? 0
        adj.bGamma             = dict["bGamma"]             as? Double ?? 0
        adj.rGain              = dict["rGain"]              as? Double ?? 0
        adj.gGain              = dict["gGain"]              as? Double ?? 0
        adj.bGain              = dict["bGain"]              as? Double ?? 0
        adj.quantizationLevels = dict["quantizationLevels"] as? Int    ?? 256
        adj.isInverted         = dict["isInverted"]         as? Bool   ?? false
        adj.isPaused           = dict["isPaused"]           as? Bool   ?? false
        return adj
    }

    func clearSavedState() {
        UserDefaults.standard.removeObject(forKey: GammaService.stateKey)
    }

    // MARK: - Formula mode

    private struct ChannelParams {
        var rLo, rHi, rGam: Double
        var gLo, gHi, gGam: Double
        var bLo, bHi, bGam: Double
    }

    private func applyFormula(_ adj: GammaAdjustment, for displayID: CGDirectDisplayID) {
        let p = channelParams(for: adj)
        CGSetDisplayTransferByFormula(displayID,
            CGGammaValue(p.rLo), CGGammaValue(p.rHi), CGGammaValue(p.rGam),
            CGGammaValue(p.gLo), CGGammaValue(p.gHi), CGGammaValue(p.gGam),
            CGGammaValue(p.bLo), CGGammaValue(p.bHi), CGGammaValue(p.bGam))
    }

    private func channelParams(for adj: GammaAdjustment) -> ChannelParams {
        // ── Gamma exponent ──────────────────────────────────────────────
        // slider=0 → exp=1.0; +100 → 0.5 (brighter curve); -100 → 2.0 (darker)
        let globalGammaExp = pow(2.0, -adj.gammaVal / 100.0)
        let rGammaExp = globalGammaExp * pow(2.0, -adj.rGamma / 100.0)
        let gGammaExp = globalGammaExp * pow(2.0, -adj.gGamma / 100.0)
        let bGammaExp = globalGammaExp * pow(2.0, -adj.bGamma / 100.0)

        // ── Gain (output ceiling / brightness scale) ────────────────────
        // slider=0 → 1.0; +100 → 2.0; -100 → 0.0
        let globalGain = max(0.0, 1.0 + adj.gain / 100.0)
        let rGain = max(0.0, globalGain * (1.0 + adj.rGain / 100.0))
        let gGain = max(0.0, globalGain * (1.0 + adj.gGain / 100.0))
        let bGain = max(0.0, globalGain * (1.0 + adj.bGain / 100.0))

        // ── Color temperature ───────────────────────────────────────────
        let (tempR, tempG, tempB) = colorTempFactors(adj.colorTemperature)

        // Per-channel max after gain × color-temp
        let rHiBase = rGain * tempR
        let gHiBase = gGain * tempG
        let bHiBase = bGain * tempB

        // ── Contrast (symmetric push/pull of min and max) ───────────────
        // ±100% → ±0.4 shift, widening/narrowing the output range
        let contrastShift = adj.contrast / 250.0

        var rLo = 0.0 - contrastShift
        var gLo = 0.0 - contrastShift
        var bLo = 0.0 - contrastShift
        var rHi = rHiBase + contrastShift
        var gHi = gHiBase + contrastShift
        var bHi = bHiBase + contrastShift

        // ── Inversion (swap min ↔ max per channel) ─────────────────────
        if adj.isInverted {
            swap(&rLo, &rHi)
            swap(&gLo, &gHi)
            swap(&bLo, &bHi)
        }

        return ChannelParams(
            rLo: rLo, rHi: rHi, rGam: rGammaExp,
            gLo: gLo, gHi: gHi, gGam: gGammaExp,
            bLo: bLo, bHi: bHi, bGam: bGammaExp)
    }

    // MARK: - Color temperature (Tanner Helland algorithm)

    /// Returns per-channel gain multipliers normalised so that 6500 K → (1, 1, 1).
    private func colorTempFactors(_ sliderValue: Double) -> (r: Double, g: Double, b: Double) {
        guard sliderValue != 0.0 else { return (1.0, 1.0, 1.0) }
        // positive slider = warmer (lower K); negative = cooler (higher K)
        let kelvin: Double
        if sliderValue > 0 {
            kelvin = 6500.0 - sliderValue / 100.0 * 4500.0  // 6500 K → 2000 K
        } else {
            kelvin = 6500.0 - sliderValue / 100.0 * 5500.0  // 6500 K → 12000 K
        }
        let (r, g, b) = kelvinToRGB(kelvin)
        let (rN, gN, bN) = kelvinToRGB(6500.0)
        return (
            rN > 0 ? r / rN : r,
            gN > 0 ? g / gN : g,
            bN > 0 ? b / bN : b
        )
    }

    private func kelvinToRGB(_ kelvin: Double) -> (Double, Double, Double) {
        let temp = max(1000.0, min(40000.0, kelvin)) / 100.0

        let r: Double
        if temp <= 66 {
            r = 1.0
        } else {
            r = max(0, min(1, 1.292936186 * pow(temp - 60, -0.1332047592)))
        }

        let g: Double
        if temp <= 66 {
            g = max(0, min(1, 0.390081579 * log(temp) - 0.631841444))
        } else {
            g = max(0, min(1, 1.129890861 * pow(temp - 60, -0.0755148492)))
        }

        let b: Double
        if temp >= 66 {
            b = 1.0
        } else if temp <= 19 {
            b = 0.0
        } else {
            b = max(0, min(1, 0.543206789 * log(temp - 10) - 1.196254089))
        }

        return (r, g, b)
    }

    // MARK: - Quantization (table mode)

    private func applyQuantizedTable(_ adj: GammaAdjustment, for displayID: CGDirectDisplayID) {
        let levels = max(2, min(255, adj.quantizationLevels))
        let capacity = 256

        var redTable   = [CGGammaValue](repeating: 0, count: capacity)
        var greenTable = [CGGammaValue](repeating: 0, count: capacity)
        var blueTable  = [CGGammaValue](repeating: 0, count: capacity)

        let p = channelParams(for: adj)

        for i in 0..<capacity {
            let input = Double(i) / Double(capacity - 1)

            func tableValue(lo: Double, hi: Double, gam: Double) -> CGGammaValue {
                let raw = lo + (hi - lo) * pow(input, gam)
                let clamped = max(0.0, min(1.0, raw))
                // Quantize to `levels` discrete steps
                let stepped = floor(clamped * Double(levels)) / Double(levels)
                return CGGammaValue(stepped)
            }

            redTable[i]   = tableValue(lo: p.rLo, hi: p.rHi, gam: p.rGam)
            greenTable[i] = tableValue(lo: p.gLo, hi: p.gHi, gam: p.gGam)
            blueTable[i]  = tableValue(lo: p.bLo, hi: p.bHi, gam: p.bGam)
        }

        CGSetDisplayTransferByTable(displayID, UInt32(capacity),
                                    &redTable, &greenTable, &blueTable)
    }
}
