import Foundation
import CoreGraphics

/// Service responsible for reading and changing display resolution modes.
@MainActor
final class ResolutionService: @unchecked Sendable {
    static let shared = ResolutionService()
    private init() {}

    // MARK: - Query

    func availableModes(for displayID: CGDirectDisplayID) -> [DisplayMode] {
        DisplayMode.availableModes(for: displayID)
    }

    func currentMode(for displayID: CGDirectDisplayID) -> DisplayMode? {
        DisplayMode.currentMode(for: displayID)
    }

    // MARK: - Apply

    func setDisplayMode(_ mode: DisplayMode, for displayID: CGDirectDisplayID) async -> Bool {
        let options: CFDictionary = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        guard let allRaw = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] else {
            return false
        }

        guard let targetMode = allRaw.first(where: {
            $0.ioDisplayModeID == mode.ioDisplayModeID
        }) else {
            return false
        }

        return await withCheckedContinuation { continuation in
            var config: CGDisplayConfigRef?
            guard CGBeginDisplayConfiguration(&config) == .success,
                  let cfg = config else {
                continuation.resume(returning: false)
                return
            }

            let result = CGConfigureDisplayWithDisplayMode(cfg, displayID, targetMode, nil)
            guard result == .success else {
                CGCancelDisplayConfiguration(cfg)
                continuation.resume(returning: false)
                return
            }

            let complete = CGCompleteDisplayConfiguration(cfg, .permanently)
            continuation.resume(returning: complete == .success)
        }
    }
}
