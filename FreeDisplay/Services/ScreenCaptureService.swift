@preconcurrency import ScreenCaptureKit
import CoreMedia
import CoreImage
import Foundation

/// Captures a single display using ScreenCaptureKit (macOS 14+).
/// All state mutations happen on @MainActor; SCStream callbacks are bridged via Task.
@MainActor
final class ScreenCaptureService: NSObject, @unchecked Sendable, ObservableObject {
    let displayID: CGDirectDisplayID
    @Published private(set) var latestFrame: CIImage?
    @Published private(set) var isCapturing = false
    @Published private(set) var errorMessage: String?

    private var stream: SCStream?

    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
        super.init()
    }

    // MARK: - Start

    func startCapture(showCursor: Bool) async {
        guard !isCapturing else { return }
        errorMessage = nil
        do {
            // A just-created virtual display does not appear in SCShareableContent
            // immediately — the list is refreshed asynchronously by the window server,
            // so a single lookup right after creation reliably misses it. Poll instead.
            var scDisplay: SCDisplay?
            var lastSeen: [UInt32] = []
            for attempt in 0..<12 {
                let content = try await SCShareableContent.current
                lastSeen = content.displays.map { $0.displayID }
                if let match = content.displays.first(where: { $0.displayID == displayID }) {
                    scDisplay = match
                    break
                }
                if attempt < 11 {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
            guard let scDisplay else {
                // Log what SCShareableContent actually reported vs. what CoreGraphics
                // thinks is active — the two disagreeing is the whole diagnosis here.
                var cgCount: UInt32 = 0
                CGGetActiveDisplayList(0, nil, &cgCount)
                var cgIDs = [CGDirectDisplayID](repeating: 0, count: Int(cgCount))
                CGGetActiveDisplayList(cgCount, &cgIDs, &cgCount)

                // Online but NOT active means the display exists yet isn't drawing —
                // the classic cause being that it has been folded into a mirror set,
                // where only the master is active and capturable.
                var onCount: UInt32 = 0
                CGGetOnlineDisplayList(0, nil, &onCount)
                var onIDs = [CGDirectDisplayID](repeating: 0, count: Int(onCount))
                CGGetOnlineDisplayList(onCount, &onIDs, &onCount)

                let target = self.displayID
                let mirrorInfo = onIDs.contains(target)
                    ? "online=YES mirrors=\(CGDisplayMirrorsDisplay(target)) inMirrorSet=\(CGDisplayIsInMirrorSet(target) != 0)"
                    : "online=NO"

                FDLog.capture.error("""
                    target display not found. \
                    want=\(target, privacy: .public) \
                    SCShareableContent=\(lastSeen.map(String.init).joined(separator: ","), privacy: .public) \
                    CGActive=\(cgIDs.map(String.init).joined(separator: ","), privacy: .public) \
                    CGOnline=\(onIDs.map(String.init).joined(separator: ","), privacy: .public) \
                    \(mirrorInfo, privacy: .public)
                    """)
                errorMessage = "找不到目标显示器"
                return
            }
            FDLog.capture.info("capturing display \(self.displayID, privacy: .public)")
            let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = scDisplay.width
            config.height = scDisplay.height
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = showCursor
            config.capturesAudio = false
            let s = SCStream(filter: filter, configuration: config, delegate: self)
            try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
            try await s.startCapture()
            stream = s
            isCapturing = true
        } catch {
            errorMessage = "串流启动失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Stop

    func stopCapture() async {
        guard let s = stream else { return }
        do {
            try await s.stopCapture()
        } catch {
            // Ignore stop errors
        }
        stream = nil
        isCapturing = false
        latestFrame = nil
    }

    // MARK: - Restart with new options

    func restart(showCursor: Bool) {
        Task {
            await stopCapture()
            await startCapture(showCursor: showCursor)
        }
    }
}

// MARK: - SCStreamOutput

extension ScreenCaptureService: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        Task { @MainActor [weak self] in
            self?.latestFrame = ciImage
        }
    }
}

// MARK: - SCStreamDelegate

extension ScreenCaptureService: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.isCapturing = false
            self?.stream = nil
            self?.errorMessage = "串流中断：\(error.localizedDescription)"
        }
    }
}
