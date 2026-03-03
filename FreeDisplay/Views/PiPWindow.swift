import AppKit
import SwiftUI

// MARK: - PiP Options

enum PiPWindowLevel: String, CaseIterable {
    case normal = "normal"
    case floating = "floating"
    case aboveMenuBar = "aboveMenuBar"

    var localizedName: String {
        switch self {
        case .normal: return "普通层级"
        case .floating: return "浮动（置顶）"
        case .aboveMenuBar: return "菜单栏之上"
        }
    }

    var nsLevel: NSWindow.Level {
        switch self {
        case .normal: return .normal
        case .floating: return .floating
        case .aboveMenuBar: return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        }
    }
}

// MARK: - PiPWindowController

/// A floating picture-in-picture window for displaying a live screen stream.
@MainActor
final class PiPWindowController: NSObject, NSWindowDelegate {
    private(set) var window: PiPNSWindow?
    let viewModel: StreamViewModel

    // PiP-specific options
    var pipLevel: PiPWindowLevel = .floating {
        didSet { window?.level = pipLevel.nsLevel }
    }
    var showTitleBar: Bool = false {
        didSet { applyTitleBarVisibility() }
    }
    var isMovable: Bool = true {
        didSet { window?.isMovable = isMovable }
    }
    var isResizable: Bool = true {
        didSet { applyResizable() }
    }
    var ignoresMouse: Bool = false {
        didSet { window?.ignoresMouseEvents = ignoresMouse }
    }
    var hasShadow: Bool = true {
        didSet { window?.hasShadow = hasShadow }
    }
    var snapsToQuarters: Bool = false {
        didSet { window?.snapsToQuarters = snapsToQuarters }
    }

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
        )
        let pip = PiPNSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: buildStyleMask(),
            backing: .buffered,
            defer: false
        )
        pip.title = "画中画"
        pip.contentViewController = hosting
        pip.level = pipLevel.nsLevel
        pip.isMovable = isMovable
        pip.hasShadow = hasShadow
        pip.ignoresMouseEvents = ignoresMouse
        pip.snapsToQuarters = snapsToQuarters
        pip.alphaValue = viewModel.config.alphaValue
        pip.isReleasedWhenClosed = false
        pip.delegate = self
        pip.center()
        pip.makeKeyAndOrderFront(nil)
        window = pip
    }

    func close() {
        window?.close()
        window = nil
    }

    func updateAlpha(_ value: Double) {
        window?.alphaValue = value
    }

    // MARK: - Private helpers

    private func buildStyleMask() -> NSWindow.StyleMask {
        var mask: NSWindow.StyleMask = [.closable, .resizable]
        if showTitleBar { mask.insert(.titled) }
        if isResizable { mask.insert(.resizable) } else { mask.remove(.resizable) }
        return mask
    }

    private func applyTitleBarVisibility() {
        guard let win = window else { return }
        if showTitleBar {
            win.styleMask.insert(.titled)
        } else {
            win.styleMask.remove(.titled)
        }
    }

    private func applyResizable() {
        guard let win = window else { return }
        if isResizable {
            win.styleMask.insert(.resizable)
        } else {
            win.styleMask.remove(.resizable)
        }
    }
}

// MARK: - PiPNSWindow

/// NSWindow subclass that can snap its origin to 25% increments after a drag.
final class PiPNSWindow: NSWindow, @unchecked Sendable {
    var snapsToQuarters: Bool = false

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        if snapsToQuarters { snapToQuarterScreen() }
    }

    private func snapToQuarterScreen() {
        guard let screen = screen else { return }
        let sf = screen.visibleFrame
        let step = sf.width * 0.25
        let snappedX = (round((frame.origin.x - sf.minX) / step) * step) + sf.minX
        let clampedX = max(sf.minX, min(sf.maxX - frame.width, snappedX))
        setFrameOrigin(CGPoint(x: clampedX, y: frame.origin.y))
    }
}
