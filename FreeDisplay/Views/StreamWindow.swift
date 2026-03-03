import AppKit
import SwiftUI
import Metal

// MARK: - StreamWindowController

/// Creates and manages an NSWindow that displays a live stream from one display.
@MainActor
final class StreamWindowController: NSObject {
    private(set) var window: NSWindow?
    let viewModel: StreamViewModel

    init(viewModel: StreamViewModel) {
        self.viewModel = viewModel
        super.init()
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

    func close() {
        window?.close()
        window = nil
    }

    func updateAlpha(_ value: Double) {
        window?.alphaValue = value
    }
}

// MARK: - StreamContentView

struct StreamContentView: View {
    @ObservedObject var viewModel: StreamViewModel

    var body: some View {
        ZStack {
            Color.black
            if let frame = viewModel.service.latestFrame {
                CIImageDisplayView(ciImage: viewModel.processedImage(frame))
            } else if viewModel.isCapturing {
                ProgressView("正在获取画面…")
                    .progressViewStyle(.circular)
                    .tint(.white)
            } else if let err = viewModel.service.errorMessage {
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
