import CoreGraphics
import Foundation

/// Provides hardware-level screen mirroring via CGDisplayConfiguration API.
@MainActor
final class MirrorService: @unchecked Sendable {
    static let shared = MirrorService()
    private init() {}

    // MARK: - Query

    /// Returns the source display that `displayID` is mirroring, or nil if not mirroring.
    func mirrorSource(for displayID: CGDirectDisplayID) -> CGDirectDisplayID? {
        let source = CGDisplayMirrorsDisplay(displayID)
        guard source != kCGNullDirectDisplay else { return nil }
        return source
    }

    /// Returns true when `displayID` is currently mirroring another display.
    func isMirroring(_ displayID: CGDirectDisplayID) -> Bool {
        mirrorSource(for: displayID) != nil
    }

    // MARK: - Enable

    /// Makes `target` mirror `source`.
    /// - Returns: true on success.
    @discardableResult
    func enableMirror(source: CGDirectDisplayID, target: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success,
              let cfg = config else { return false }
        CGConfigureDisplayMirrorOfDisplay(cfg, target, source)
        return CGCompleteDisplayConfiguration(cfg, .permanently) == .success
    }

    // MARK: - Disable

    /// Stops `displayID` from mirroring.
    /// - Returns: true on success.
    @discardableResult
    func disableMirror(displayID: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success,
              let cfg = config else { return false }
        CGConfigureDisplayMirrorOfDisplay(cfg, displayID, kCGNullDirectDisplay)
        return CGCompleteDisplayConfiguration(cfg, .permanently) == .success
    }
}
