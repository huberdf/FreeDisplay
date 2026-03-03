import AppKit
import CoreGraphics

/// Manages a black overlay window that covers the notch area of built-in MacBook displays.
@MainActor
class NotchOverlayManager {
    static let shared = NotchOverlayManager()
    private var overlayWindows: [CGDirectDisplayID: NSWindow] = [:]

    private init() {}

    func showOverlay(for displayID: CGDirectDisplayID) {
        guard let screen = NSScreen.screen(for: displayID) else { return }
        let notchHeight = screen.safeAreaInsets.top
        guard notchHeight > 0 else { return }

        let screenFrame = screen.frame
        let overlayFrame = NSRect(
            x: screenFrame.minX,
            y: screenFrame.maxY - notchHeight,
            width: screenFrame.width,
            height: notchHeight
        )

        let window = NSWindow(
            contentRect: overlayFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.backgroundColor = .black
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.isOpaque = true
        window.hasShadow = false
        window.orderFront(nil)

        overlayWindows[displayID]?.close()
        overlayWindows[displayID] = window
    }

    func hideOverlay(for displayID: CGDirectDisplayID) {
        overlayWindows[displayID]?.close()
        overlayWindows.removeValue(forKey: displayID)
    }

    func isShowingOverlay(for displayID: CGDirectDisplayID) -> Bool {
        overlayWindows[displayID] != nil
    }
}
