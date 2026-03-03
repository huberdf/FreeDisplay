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
            let content = try await SCShareableContent.current
            guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
                errorMessage = "找不到目标显示器"
                return
            }
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
