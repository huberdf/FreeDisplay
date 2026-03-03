import Foundation
import CoreGraphics

// Global C-compatible callback for display reconfiguration.
// Must be a top-level function (not a closure) to be used as a C function pointer.
private func displayReconfigCallback(
    displayID: CGDirectDisplayID,
    flags: CGDisplayChangeSummaryFlags,
    userInfo: UnsafeMutableRawPointer?
) {
    guard let ptr = userInfo else { return }
    let manager = Unmanaged<DisplayManager>.fromOpaque(ptr).takeUnretainedValue()

    let relevant: CGDisplayChangeSummaryFlags = [.addFlag, .removeFlag, .setMainFlag]
    guard !flags.intersection(relevant).isEmpty else { return }

    Task { @MainActor in
        manager.refreshDisplays()
    }
}

@MainActor
class DisplayManager: ObservableObject {
    @Published var displays: [DisplayInfo] = []

    // nonisolated(unsafe) allows deinit (which is nonisolated in Swift 6) to access this value.
    nonisolated(unsafe) private var callbackContext: UnsafeMutableRawPointer?

    init() {
        refreshDisplays()
        setupReconfigCallback()
    }

    deinit {
        if let ctx = callbackContext {
            CGDisplayRemoveReconfigurationCallback(displayReconfigCallback, ctx)
        }
    }

    func refreshDisplays() {
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(16, &displayIDs, &displayCount)

        let newDisplays = (0..<Int(displayCount)).map { i in
            DisplayInfo(displayID: displayIDs[i])
        }
        displays = newDisplays
        DisplayManagerAccessor.shared.displays = newDisplays

        for display in newDisplays {
            Task { await BrightnessService.shared.refreshBrightness(for: display) }
            Task { await display.loadDetails() }
        }
    }

    private func setupReconfigCallback() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        callbackContext = ctx
        CGDisplayRegisterReconfigurationCallback(displayReconfigCallback, ctx)
    }

    /// Toggle a display on/off.
    func toggleDisplay(_ display: DisplayInfo) {
        display.isEnabled.toggle()

        if display.isBuiltin {
            // Phase 2 will implement real brightness control for built-in display
            return
        }

        if display.isEnabled {
            CGDisplayRelease(display.displayID)
        } else {
            CGDisplayCapture(display.displayID)
        }
    }

    /// Makes the target display the main display by repositioning it to origin (0, 0).
    func setAsMainDisplay(_ display: DisplayInfo) {
        let ok = ArrangementService.shared.setAsMainDisplay(display.displayID, among: displays)
        if ok { refreshDisplays() }
    }
}
