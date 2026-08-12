import AppKit
import SwiftUI
import Metal

// MARK: - StreamWindowController

/// Creates and manages an NSWindow that displays a live stream from one display.
@MainActor
final class StreamWindowController: NSObject {
    private(set) var window: NSWindow?
    let viewModel: StreamViewModel

    /// Display the full-screen window is pinned to, so it can be re-framed whenever the
    /// screen layout changes. Repositioning displays invalidates NSScreen frames; without
    /// this the window keeps its old frame and ends up off-screen or on the wrong display.
    private var pinnedDisplayID: CGDirectDisplayID?
    private var screenObserver: NSObjectProtocol?

    init(viewModel: StreamViewModel) {
        self.viewModel = viewModel
        super.init()
    }

    /// Re-applies the window frame to the pinned display's current geometry.
    private func repinToDisplay() {
        guard let win = window,
              let id = pinnedDisplayID,
              let screen = NSScreen.screen(for: id) else { return }
        if win.frame != screen.frame {
            win.setFrame(screen.frame, display: true)
        }
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        if let win = window {
            win.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView:
            StreamContentView(viewModel: viewModel)
                .frame(minWidth: 320, minHeight: 180)
        )
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "屏幕串流"
        win.contentViewController = hosting
        win.center()
        win.isReleasedWhenClosed = false
        win.alphaValue = viewModel.config.alphaValue
        win.makeKeyAndOrderFront(nil)
        window = win
    }

    /// Opens a borderless, full-screen window pinned to `screen`, showing the stream
    /// with no chrome. Used by the rotated-Sidecar feature: the physical display shows
    /// nothing but the (already rotated) content of the associated virtual display.
    ///
    /// The window deliberately does NOT become key — clicking through to it would steal
    /// focus from whatever the user is doing on their primary display.
    func showFullScreen(on screen: NSScreen) {
        close()
        pinnedDisplayID = screen.displayID
        // Registered after close() — close() unregisters, so doing this in init would
        // leave the observer dangling the first time a window is shown.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.repinToDisplay() }
        }

        let hosting = NSHostingController(rootView: StreamContentView(viewModel: viewModel))
        let win = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        win.contentViewController = hosting
        win.setFrame(screen.frame, display: true)
        win.isReleasedWhenClosed = false
        win.backgroundColor = .black
        win.hasShadow = false
        win.isMovable = false
        // Sit ABOVE the menu bar. The target display is a pure output surface — its own
        // menu bar and Dock belong to the physical (landscape) display, so once the iPad
        // is turned they appear along a vertical edge, on top of the rotated content.
        // Covering them leaves only the streamed virtual display's own menu bar visible,
        // which is correctly oriented.
        win.level = .init(Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        // Show on the target display even when the user switches Spaces on the main one.
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        win.ignoresMouseEvents = false
        win.orderFrontRegardless()
        window = win
    }

    func close() {
        window?.close()
        window = nil
        pinnedDisplayID = nil
        // Removed here rather than in deinit: a nonisolated deinit can't touch
        // @MainActor state under Swift concurrency checking.
        if let obs = screenObserver {
            NotificationCenter.default.removeObserver(obs)
            screenObserver = nil
        }
    }

    func updateAlpha(_ value: Double) {
        window?.alphaValue = value
    }
}

// MARK: - StreamContentView

struct StreamContentView: View {
    @ObservedObject var viewModel: StreamViewModel
    /// Observed separately: `latestFrame` is @Published on the *service*, and nested
    /// ObservableObjects do not propagate through their parent. Observing only the
    /// view model means the view never re-renders and the window stays black.
    @ObservedObject var service: ScreenCaptureService

    init(viewModel: StreamViewModel) {
        self.viewModel = viewModel
        self.service = viewModel.service
    }

    var body: some View {
        ZStack {
            Color.black
            if let frame = service.latestFrame {
                CIImageDisplayView(ciImage: viewModel.processedImage(frame))
            } else if service.isCapturing {
                ProgressView("正在获取画面…")
                    .progressViewStyle(.circular)
                    .tint(.white)
            } else if let err = service.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "display.trianglebadge.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("串流未启动")
                        .foregroundColor(.secondary)
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - CIImageDisplayView

/// NSViewRepresentable wrapper that renders a CIImage into a layer-backed NSView.
struct CIImageDisplayView: NSViewRepresentable {
    let ciImage: CIImage

    func makeNSView(context: Context) -> StreamNSView {
        StreamNSView()
    }

    func updateNSView(_ nsView: StreamNSView, context: Context) {
        nsView.ciImage = ciImage
    }
}

// MARK: - StreamNSView

/// Layer-backed NSView that renders CIImage efficiently using a Metal-backed CIContext.
final class StreamNSView: NSView {
    var ciImage: CIImage? {
        didSet { needsDisplay = true }
    }

    /// Shared Metal-backed CIContext for efficient GPU rendering.
    private static let ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.useSoftwareRenderer: false])
        }
        return CIContext(options: [.useSoftwareRenderer: false])
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = CGColor.black
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let ciImage = ciImage else {
            layer?.contents = nil
            return
        }
        let extent = ciImage.extent
        guard !extent.isEmpty, !extent.isInfinite else { return }
        if let cgImage = Self.ciContext.createCGImage(ciImage, from: extent) {
            layer?.contents = cgImage
            layer?.contentsGravity = .resizeAspect
            layer?.backgroundColor = CGColor.black
        }
    }
}
