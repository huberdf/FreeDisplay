import AppKit
import SwiftUI
import CoreGraphics

/// Shows a fullscreen overlay on a target display to help users visually identify it.
/// The overlay displays the monitor name and ID for 3 seconds then auto-dismisses.
@MainActor
class VisualIdentificationManager {
    static let shared = VisualIdentificationManager()
    private var window: NSWindow?

    private init() {}

    func show(for displayID: CGDirectDisplayID, name: String) {
        window?.close()

        guard let screen = NSScreen.screen(for: displayID) else { return }

        let win = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        win.backgroundColor = NSColor.black.withAlphaComponent(0.85)
        win.level = .modalPanel
        win.ignoresMouseEvents = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.isOpaque = false

        let hostingView = NSHostingView(
            rootView: IdentificationOverlayView(displayName: name, displayID: displayID)
        )
        hostingView.frame = NSRect(origin: .zero, size: screen.frame.size)
        win.contentView = hostingView
        win.orderFront(nil)
        window = win

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.window?.close()
            self?.window = nil
        }
    }
}

private struct IdentificationOverlayView: View {
    let displayName: String
    let displayID: CGDirectDisplayID

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
            VStack(spacing: 24) {
                Image(systemName: "display")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                Text(displayName)
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text("ID: \(displayID)")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .ignoresSafeArea()
    }
}
