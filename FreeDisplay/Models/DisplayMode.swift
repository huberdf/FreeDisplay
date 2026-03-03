import Foundation
import CoreGraphics

/// Represents a single display mode (resolution + refresh rate + HiDPI flag).
struct DisplayMode: Identifiable, Equatable {
    /// Unique identifier: IODisplayModeID
    let id: Int32
    /// Logical width in points
    let width: Int
    /// Logical height in points
    let height: Int
    /// Physical pixel width (HiDPI: 2× logical)
    let pixelWidth: Int
    /// Physical pixel height
    let pixelHeight: Int
    /// Refresh rate in Hz (0 means display default, shown as 60)
    let refreshRate: Double
    /// Whether this is a HiDPI (Retina) scaled mode
    let isHiDPI: Bool
    /// Whether this is the native (highest pixel resolution) mode
    let isNative: Bool
    /// Raw IODisplayModeID for CGConfigureDisplayWithDisplayMode
    let ioDisplayModeID: Int32

    // MARK: - Display strings

    var resolutionString: String {
        "\(width)×\(height)"
    }

    var refreshRateString: String {
        let r = refreshRate <= 0 ? 60.0 : refreshRate
        if r.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(r))Hz"
        }
        return String(format: "%.2fHz", r)
    }

    // MARK: - Enumeration helpers

    /// Returns all display modes for the given display, sorted by logical width descending.
    /// Pass `includeHiDPI: true` (default) to include all scaled modes.
    static func availableModes(for displayID: CGDirectDisplayID) -> [DisplayMode] {
        let options: CFDictionary = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        guard let rawModes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode],
              !rawModes.isEmpty else {
            return []
        }

        // Determine native pixel width (maximum across all modes)
        let maxPixelWidth = rawModes.map { $0.pixelWidth }.max() ?? 0

        var seen = Set<Int32>()
        return rawModes.compactMap { mode -> DisplayMode? in
            let modeID = mode.ioDisplayModeID
            guard seen.insert(modeID).inserted else { return nil }  // deduplicate
            guard mode.isUsableForDesktopGUI() else { return nil }

            let w = mode.width
            let h = mode.height
            let pw = mode.pixelWidth
            let ph = mode.pixelHeight
            let refresh = mode.refreshRate

            return DisplayMode(
                id: modeID,
                width: w,
                height: h,
                pixelWidth: pw,
                pixelHeight: ph,
                refreshRate: refresh,
                isHiDPI: pw > w,
                isNative: pw >= maxPixelWidth,
                ioDisplayModeID: modeID
            )
        }
        .sorted { lhs, rhs in
            if lhs.width != rhs.width { return lhs.width > rhs.width }
            if lhs.height != rhs.height { return lhs.height > rhs.height }
            return lhs.refreshRate > rhs.refreshRate
        }
    }

    /// Returns the current active display mode.
    static func currentMode(for displayID: CGDirectDisplayID) -> DisplayMode? {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else { return nil }

        let options: CFDictionary = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        let allModes = (CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode]) ?? []
        let maxPixelWidth = allModes.map { $0.pixelWidth }.max() ?? 0

        let w = mode.width
        let h = mode.height
        let pw = mode.pixelWidth
        let ph = mode.pixelHeight
        let refresh = mode.refreshRate
        let modeID = mode.ioDisplayModeID

        return DisplayMode(
            id: modeID,
            width: w,
            height: h,
            pixelWidth: pw,
            pixelHeight: ph,
            refreshRate: refresh,
            isHiDPI: pw > w,
            isNative: pw >= maxPixelWidth,
            ioDisplayModeID: modeID
        )
    }
}
