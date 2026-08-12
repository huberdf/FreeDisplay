import AppKit
import CoreGraphics
import Foundation

/// Drives a rotated (portrait) Sidecar iPad display.
///
/// ## Why this is not "rotate the display"
///
/// A Sidecar display cannot be rotated. `CGDisplayRotation` is read-only, macOS exposes
/// no Rotation control for Sidecar in System Settings, and the old `IOFBTransform` IOKit
/// path does not exist on Apple Silicon (there are zero `IODisplayConnect` services).
/// Physically turning the iPad makes iPadOS reorient while macOS keeps sending a landscape
/// framebuffer, which crops the image — a longstanding iPadOS bug.
///
/// ## What this does instead
///
/// The Sidecar display is never rotated. Instead:
///
///   1. Create a **virtual** display whose dimensions are the Sidecar display's, flipped
///      (a landscape 1280x854 Sidecar gets an 854x1280 portrait virtual display).
///   2. Capture that virtual display with ScreenCaptureKit.
///   3. Rotate the captured frames 90° with CoreImage.
///   4. Render them into a borderless full-screen window pinned to the Sidecar display.
///
/// The iPad stays locked in landscape the whole time and simply shows a full-screen stream
/// of already-rotated content. The user drags windows onto the *virtual* portrait display;
/// the Sidecar display becomes a dumb output surface.
///
/// This mirrors BetterDisplay's approach:
/// https://github.com/waydabber/BetterDisplay/wiki/Rotated-Sidecar
@MainActor
final class RotatedSidecarService: ObservableObject, @unchecked Sendable {
    static let shared = RotatedSidecarService()

    private init() {
        // Sidecar displays get a NEW CGDirectDisplayID on every reconnect, and locking
        // the iPad's orientation or toggling mirroring counts as a reconnect. Without
        // this, the service stays "active" pointing at a display that no longer exists,
        // its window is pinned to a dead NSScreen, and Start becomes a silent no-op.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenChange()
            }
        }
        isSidecarConnected = !Self.connectedSidecarDisplays().isEmpty
    }

    /// Tears down if the display we were driving has gone away; otherwise takes the chance
    /// to auto-start, since Sidecar typically connects seconds AFTER login.
    private func handleScreenChange() {
        isSidecarConnected = !Self.connectedSidecarDisplays().isEmpty
        guard isActive, let target = targetDisplayID else {
            attemptAutoStart()
            return
        }
        let stillPresent = Self.connectedSidecarDisplays().contains(target)
        guard !stillPresent else { return }
        Task { @MainActor in
            await teardown()
            errorMessage = "Sidecar 显示器已断开，请重新开启。"
        }
    }

    // MARK: - Restore across launches

    /// Arms auto-start if the feature was left enabled. Called once at launch.
    ///
    /// Cannot simply start here: Sidecar reconnects a few seconds after login, with a new
    /// display ID, so there is usually nothing to attach to yet. `handleScreenChange`
    /// retries when a display actually appears.
    func restoreIfEnabled() {
        if let raw = UserDefaults.standard.object(forKey: Keys.orientation) as? Int,
           let stored = Orientation(rawValue: raw) {
            orientation = stored
        }
        guard UserDefaults.standard.bool(forKey: Keys.enabled) else { return }
        autoStartArmed = true
        attemptAutoStart()
    }

    /// One-shot: on any failure it disarms rather than retrying, so a broken prerequisite
    /// is reported once and stays reported.
    private func attemptAutoStart() {
        guard autoStartArmed, !isActive else { return }
        guard let target = Self.connectedSidecarDisplays().first else { return }

        guard Self.hasScreenRecordingPermission else {
            autoStartArmed = false
            autoStartFailed = true
            errorMessage = "需要屏幕录制权限。授权后请重新开启。"
            FDLog.sidecar.error("auto-start aborted: no Screen Recording permission")
            return
        }

        autoStartArmed = false   // one attempt only
        Task { @MainActor in
            await start(sidecarDisplayID: target, orientation: orientation, isAutoStart: true)
            if !isActive {
                autoStartFailed = true
                FDLog.sidecar.error("auto-start failed; not retrying until the user presses Start")
            }
        }
    }

    // MARK: - Types

    /// Which way the iPad is physically turned. Determines the frame rotation applied
    /// to the virtual display's content.
    enum Orientation: Int, CaseIterable, Identifiable {
        /// iPad turned counter-clockwise (USB-C port at the top).
        case portraitCounterClockwise = 270
        /// iPad turned clockwise (USB-C port ends up at the bottom on most iPads).
        case portraitClockwise = 90

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .portraitCounterClockwise: return "上"
            case .portraitClockwise:        return "下"
            }
        }
    }

    // MARK: - State

    @Published private(set) var isActive = false
    @Published private(set) var errorMessage: String?
    /// Display ID of the Sidecar display currently being driven.
    @Published private(set) var targetDisplayID: CGDirectDisplayID?
    /// Set when an automatic start failed. Auto-start does not run again until the user
    /// presses Start, so a broken prerequisite (revoked permission, say) surfaces once
    /// instead of retrying on every screen change forever.
    @Published private(set) var autoStartFailed = false
    /// Whether any Sidecar display is currently connected. The menu hides the whole
    /// section when false — the feature is meaningless without an iPad attached.
    @Published private(set) var isSidecarConnected = false

    /// Orientation the user last chose; restored across launches.
    @Published var orientation: Orientation = .portraitClockwise {
        didSet {
            guard orientation != oldValue else { return }
            UserDefaults.standard.set(orientation.rawValue, forKey: Keys.orientation)
        }
    }

    private var virtualConfigID: UUID?
    private var viewModel: StreamViewModel?
    private var windowController: StreamWindowController?
    /// Whether an auto-start is still permitted this session.
    private var autoStartArmed = false

    private enum Keys {
        static let enabled = "fd.rotatedSidecar.enabled"
        static let orientation = "fd.rotatedSidecar.orientation"
        /// The Sidecar display's origin BEFORE we parked it, so Stop can put it back even
        /// after a relaunch or a crash. In memory only, this was lost on quit and the
        /// user's layout could never be restored.
        static let originalOrigin = "fd.rotatedSidecar.originalOrigin"
        /// Where we parked the Sidecar display and placed the virtual one last time, so a
        /// restored session reproduces the same layout instead of recomputing it.
        static let parkedOrigin = "fd.rotatedSidecar.parkedOrigin"
        static let virtualOrigin = "fd.rotatedSidecar.virtualOrigin"
    }

    /// Displays whose position this service owns while running. DisplayManager's
    /// auto-arrange must leave these alone or it will undo the parking.
    var managedDisplayIDs: Set<CGDirectDisplayID> {
        guard isActive else { return [] }
        var ids = Set<CGDirectDisplayID>()
        if let t = targetDisplayID { ids.insert(t) }
        if let cfg = virtualConfigID, let v = VirtualDisplayService.shared.displayID(for: cfg) {
            ids.insert(v)
        }
        return ids
    }

    // MARK: - Prerequisites

    /// Whether Screen Recording has been granted. ScreenCaptureKit cannot enumerate or
    /// capture displays without it, and the failure looks like a missing display.
    nonisolated static var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the system's Screen Recording prompt (only ever shown once per app;
    /// afterwards the user must grant it in System Settings by hand).
    nonisolated static func requestScreenRecordingPermission() {
        _ = CGRequestScreenCaptureAccess()
    }

    // MARK: - Persistence helpers

    private static func point(forKey key: String) -> CGPoint? {
        guard let s = UserDefaults.standard.string(forKey: key) else { return nil }
        let parts = s.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return CGPoint(x: parts[0], y: parts[1])
    }

    private static func set(_ p: CGPoint?, forKey key: String) {
        guard let p else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set("\(Int(p.x)),\(Int(p.y))", forKey: key)
    }

    /// CoreGraphics reports Sidecar displays with these ASCII-encoded IDs:
    /// vendor 0x6161706c == "aapl", model 0x69506164 == "iPad".
    nonisolated private static let sidecarVendorID: UInt32 = 0x6161706c
    nonisolated private static let sidecarModelID: UInt32 = 0x69506164

    // MARK: - Detection

    /// True if `displayID` is an iPad connected over Sidecar.
    nonisolated static func isSidecarDisplay(_ displayID: CGDirectDisplayID) -> Bool {
        CGDisplayVendorNumber(displayID) == sidecarVendorID
            && CGDisplayModelNumber(displayID) == sidecarModelID
    }

    /// Every active display ID.
    static func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids
    }

    /// All currently connected Sidecar displays.
    static func connectedSidecarDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.filter { isSidecarDisplay($0) }
    }

    // MARK: - Start

    /// Sets up the virtual display, capture, and output window.
    ///
    /// - Parameters:
    ///   - sidecarDisplayID: the physical Sidecar display to drive.
    ///   - orientation: which way the iPad is physically turned.
    /// - Parameter isAutoStart: true when restoring at launch. Only a user-initiated
    ///   start clears `autoStartFailed`, so a failed restore stays visible.
    func start(sidecarDisplayID: CGDirectDisplayID,
               orientation: Orientation,
               isAutoStart: Bool = false) async {
        guard !isActive else { return }
        errorMessage = nil
        if !isAutoStart { autoStartFailed = false }
        self.orientation = orientation

        guard Self.hasScreenRecordingPermission else {
            errorMessage = "需要屏幕录制权限。授权后请重新开启。"
            return
        }

        // The Sidecar display's landscape size in points.
        let bounds = CGDisplayBounds(sidecarDisplayID)
        let landscapeW = Int(bounds.width.rounded())
        let landscapeH = Int(bounds.height.rounded())
        guard landscapeW > 0, landscapeH > 0 else {
            errorMessage = "无法读取 Sidecar 显示器尺寸"
            return
        }

        // The virtual display is the same size with width/height swapped, so that once
        // its content is rotated 90° it exactly fills the Sidecar display with no scaling.
        let config = VirtualDisplayService.VirtualDisplayConfig(
            name: "Sidecar（虚拟）",
            width: landscapeH,
            height: landscapeW,
            refreshRate: 60.0,
            // 1:1 pixel mapping — a HiDPI backing store would be rescaled on the way out
            // and cost GPU for no visible gain, since the Sidecar output is fixed size.
            hiDPI: false,
            autoCreate: false
        )

        guard await VirtualDisplayService.shared.create(config: config) else {
            errorMessage = "创建虚拟显示器失败"
            return
        }
        virtualConfigID = config.id

        FDLog.sidecar.info("""
            created virtual display config \
            \(config.width, privacy: .public)x\(config.height, privacy: .public) \
            for sidecar \(sidecarDisplayID, privacy: .public) \
            (\(landscapeW, privacy: .public)x\(landscapeH, privacy: .public))
            """)

        guard let virtualID = VirtualDisplayService.shared.displayID(for: config.id) else {
            errorMessage = "虚拟显示器已创建，但没有 display ID"
            await teardown()
            return
        }

        // Give WindowServer a moment to register the new display.
        try? await Task.sleep(nanoseconds: 700_000_000)

        // macOS PERSISTS mirror arrangements. If the user has ever mirrored a display
        // onto this Sidecar display, the newly created virtual display gets folded into
        // that remembered mirror set automatically. A mirrored secondary is *online but
        // not active*, never appears in SCShareableContent, and therefore cannot be
        // captured — which surfaces as a baffling "target display not found".
        //
        // Break the mirroring explicitly. This is the one legitimate use of
        // CGConfigureDisplayMirrorOfDisplay in this codebase: turning mirroring OFF.
        // (Using it to turn mirroring ON for HiDPI is banned — see docs/lessons.)
        if MirrorService.shared.isMirroring(virtualID) {
            FDLog.sidecar.info("""
                virtual display \(virtualID, privacy: .public) was auto-mirrored to \
                \(MirrorService.shared.mirrorSource(for: virtualID) ?? 0, privacy: .public) — unmirroring
                """)
            _ = await MirrorService.shared.disableMirror(displayID: virtualID)
            // Let the reconfiguration settle before checking for the display again.
            try? await Task.sleep(nanoseconds: 700_000_000)
        }

        let vm = StreamViewModel(displayID: virtualID)
        vm.config.rotation = orientation.rawValue
        // The cursor MUST be captured. This is a display the user works on, not a passive
        // mirror — the real pointer lives on the virtual display, which is never visible
        // directly, so without the captured cursor there is no pointer on the iPad at all.
        vm.config.showCursor = true
        viewModel = vm

        await vm.service.startCapture(showCursor: vm.config.showCursor)
        guard vm.service.isCapturing else {
            // Most likely cause: Screen Recording permission has not been granted.
            errorMessage = vm.service.errorMessage
                ?? "屏幕捕获启动失败。请在「系统设置 › 隐私与安全性 › 屏幕录制」中授权。"
            await teardown()
            return
        }
        vm.isCapturing = true

        // Arrange before showing the window: repositioning displays invalidates NSScreen
        // frames, and the window must be sized to the Sidecar screen's final position.
        await arrangeForRotatedSidecar(virtualID: virtualID, sidecarID: sidecarDisplayID)

        // Don't guess with a fixed sleep: NSScreen.screens refreshes asynchronously after
        // a display reconfiguration, so a window built from a stale frame lands off-screen.
        // Wait until AppKit's geometry agrees with CoreGraphics' before placing the window.
        await waitForScreenGeometry(displayID: sidecarDisplayID)

        guard let arrangedScreen = NSScreen.screen(for: sidecarDisplayID) else {
            errorMessage = "找不到 Sidecar 显示器对应的屏幕"
            await teardown()
            return
        }

        let controller = StreamWindowController(viewModel: vm)
        controller.showFullScreen(on: arrangedScreen)
        windowController = controller

        targetDisplayID = sidecarDisplayID
        isActive = true
        // Only now, with everything running, is it safe to ask for this to be restored.
        UserDefaults.standard.set(true, forKey: Keys.enabled)
    }

    // MARK: - Stop

    func stop() async {
        // Explicit stop means "don't bring this back next launch", and forgets the parked
        // layout so a later start recomputes it rather than reusing a stale corner.
        UserDefaults.standard.set(false, forKey: Keys.enabled)
        Self.set(nil, forKey: Keys.parkedOrigin)
        Self.set(nil, forKey: Keys.virtualOrigin)
        autoStartFailed = false
        await teardown()
    }

    private func teardown() async {
        windowController?.close()
        windowController = nil

        if let vm = viewModel {
            await vm.service.stopCapture()
        }
        viewModel = nil

        if let id = virtualConfigID {
            _ = VirtualDisplayService.shared.destroy(configID: id)
            VirtualDisplayService.shared.removeConfig(id: id)
        }
        virtualConfigID = nil

        await restoreOriginalArrangement(sidecarID: targetDisplayID)

        targetDisplayID = nil
        isActive = false
    }

    // MARK: - Layout

    /// Arranges the layout so the cursor can reach the portrait virtual display but not
    /// the physical Sidecar display behind it.
    ///
    /// The problem: one physical screen now has two entries in the arrangement — the
    /// virtual display the user works on, and the real Sidecar display that merely shows
    /// our output window. If the cursor wanders onto the latter it appears to vanish,
    /// because that display's content is a static mirror of the former.
    ///
    /// The fix: macOS only lets the cursor cross between displays that share an **edge**.
    /// Placing the Sidecar display so it touches the layout at a single **corner** keeps
    /// the arrangement contiguous (macOS rejects disconnected layouts) while leaving no
    /// edge to cross. The virtual display takes the natural spot beside the main display.
    private func arrangeForRotatedSidecar(virtualID: CGDirectDisplayID,
                                          sidecarID: CGDirectDisplayID) async {
        // Remember where the user had the Sidecar display BEFORE we move it, so Stop can
        // put it back. Persisted, not just in memory: a quit or crash while active would
        // otherwise strand the display in the parking corner permanently.
        // Only recorded on a fresh arrangement — re-recording after a restore would save
        // the parked position as if it were the user's own.
        if Self.point(forKey: Keys.originalOrigin) == nil {
            Self.set(CGDisplayBounds(sidecarID).origin, forKey: Keys.originalOrigin)
        }

        // Reuse the previous layout when there is one, so a restored session reproduces
        // the arrangement the user already accepted rather than recomputing (and possibly
        // landing somewhere else, since the anchor display can change).
        let storedVirtual = Self.point(forKey: Keys.virtualOrigin)
        let storedParked = Self.point(forKey: Keys.parkedOrigin)

        let vx: Int, vy: Int
        if let sv = storedVirtual {
            vx = Int(sv.x); vy = Int(sv.y)
        } else {
            // Virtual display: immediately to the right of the main display, tops aligned.
            let mainBounds = CGDisplayBounds(CGMainDisplayID())
            vx = Int(mainBounds.maxX)
            vy = Int(mainBounds.minY)
        }
        _ = await ArrangementService.shared.setPosition(x: vx, y: vy, for: virtualID)

        let sx: Int, sy: Int
        if let sp = storedParked {
            sx = Int(sp.x); sy = Int(sp.y)
        } else {
            // Corner-park beyond the OUTERMOST display so it sits at the far end of the
            // layout rather than wedged between displays the user works on.
            //
            // macOS only lets the cursor cross between displays sharing an EDGE, so a
            // single-point corner contact keeps the arrangement contiguous (macOS rejects
            // disconnected layouts) while leaving nothing to cross.
            //
            // Anchor on a real display's corner, not the bounding box's: the box corner
            // may be empty space, and a display touching nothing gets shoved back adjacent.
            let sidecarSize = CGDisplayBounds(sidecarID).size
            let sw = Int(sidecarSize.width)
            let sh = Int(sidecarSize.height)
            let anchor = Self.activeDisplayIDs()
                .filter { $0 != sidecarID && $0 != virtualID }
                .map { ($0, CGDisplayBounds($0)) }
                .min { ($0.1.minX + $0.1.minY) < ($1.1.minX + $1.1.minY) }
            if let (anchorID, anchorBounds) = anchor {
                sx = Int(anchorBounds.minX) - sw
                sy = Int(anchorBounds.minY) - sh
                FDLog.sidecar.info("parking sidecar off display \(anchorID, privacy: .public)'s top-left corner")
            } else {
                let vb = CGDisplayBounds(virtualID)
                sx = vx + Int(vb.width)
                sy = vy + Int(vb.height)
            }
        }
        _ = await ArrangementService.shared.setPosition(x: sx, y: sy, for: sidecarID)

        // Record the layout so the next start reproduces it exactly.
        Self.set(CGPoint(x: vx, y: vy), forKey: Keys.virtualOrigin)
        Self.set(CGPoint(x: sx, y: sy), forKey: Keys.parkedOrigin)

        FDLog.sidecar.info("""
            arranged: virtual \(virtualID, privacy: .public) at \(vx, privacy: .public),\(vy, privacy: .public) — \
            sidecar \(sidecarID, privacy: .public) parked at \(sx, privacy: .public),\(sy, privacy: .public) \
            \(storedParked == nil ? "(computed)" : "(restored)", privacy: .public)
            """)
    }

    /// Puts the Sidecar display back where the user had it before we parked it.
    /// Reads the persisted origin, so this still works after a relaunch.
    private func restoreOriginalArrangement(sidecarID: CGDirectDisplayID?) async {
        guard let origin = Self.point(forKey: Keys.originalOrigin) else { return }
        if let id = sidecarID, CGDisplayIsOnline(id) != 0 {
            _ = await ArrangementService.shared.setPosition(
                x: Int(origin.x), y: Int(origin.y), for: id
            )
        }
        Self.set(nil, forKey: Keys.originalOrigin)
    }

    // MARK: - Helpers

    /// Waits until AppKit's `NSScreen` for `displayID` reports the same size CoreGraphics
    /// does, meaning the reconfiguration has propagated. Gives up after ~2s and lets the
    /// caller proceed with whatever AppKit currently reports.
    private func waitForScreenGeometry(displayID: CGDirectDisplayID) async {
        let expected = CGDisplayBounds(displayID).size
        for _ in 0..<20 {
            if let s = NSScreen.screen(for: displayID),
               Int(s.frame.width) == Int(expected.width),
               Int(s.frame.height) == Int(expected.height) {
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        FDLog.sidecar.error("""
            NSScreen geometry never settled for display \(displayID, privacy: .public); \
            expected \(Int(expected.width), privacy: .public)x\(Int(expected.height), privacy: .public)
            """)
    }
}
