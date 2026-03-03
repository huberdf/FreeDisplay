import Foundation
import CoreGraphics

/// Service for reading and setting display positions in the global coordinate space.
/// On macOS, the display whose bounds contain origin (0, 0) is the main display
/// (the one that shows the Dock and menu bar).
@MainActor
class ArrangementService {
    static let shared = ArrangementService()
    private init() {}

    /// Moves the given display to the specified position in the global coordinate space.
    /// - Returns: true if the configuration was applied successfully.
    @discardableResult
    func setPosition(x: Int, y: Int, for displayID: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success,
              let config else { return false }

        CGConfigureDisplayOrigin(config, displayID, Int32(x), Int32(y))
        let result = CGCompleteDisplayConfiguration(config, .forSession)
        return result == .success
    }

    /// Makes the target display the main display by moving it to origin (0, 0).
    /// Moves the current main display to the position previously occupied by the target.
    /// - Returns: true if the configuration was applied successfully.
    @discardableResult
    func setAsMainDisplay(_ targetID: CGDirectDisplayID, among displays: [DisplayInfo]) -> Bool {
        guard let target = displays.first(where: { $0.displayID == targetID }),
              let currentMain = displays.first(where: { $0.isMain }),
              currentMain.displayID != targetID else {
            return false
        }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success,
              let config else { return false }

        // Move target to origin → it becomes the new main display
        CGConfigureDisplayOrigin(config, targetID, 0, 0)

        // Move old main to where the target was, or to the right of the new main if target was at 0
        let targetOriginX = Int(target.bounds.origin.x)
        let targetOriginY = Int(target.bounds.origin.y)
        let newMainX: Int32 = targetOriginX == 0
            ? Int32(target.bounds.width)   // avoid overlap: put old main to the right
            : Int32(targetOriginX)
        let newMainY: Int32 = Int32(targetOriginY)
        CGConfigureDisplayOrigin(config, currentMain.displayID, newMainX, newMainY)

        let result = CGCompleteDisplayConfiguration(config, .forSession)
        return result == .success
    }
}
