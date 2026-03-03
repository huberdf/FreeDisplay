import CoreImage
import Foundation

/// Options used to configure screen capture and apply transforms/filters to frames.
struct StreamConfig {
    var showCursor: Bool = true
    var scale: Double = 1.0         // Display scale multiplier
    var rotation: Int = 0           // 0 / 90 / 180 / 270 (degrees clockwise)
    var flipH: Bool = false
    var flipV: Bool = false
    var cropEnabled: Bool = false
    var cropInset: Double = 0.0     // % cropped from each edge (0..40)
    var filterName: String = "none" // "none" | "grayscale" | "blur" | "sharpen" | "invert"
    var alphaValue: Double = 1.0    // Window opacity
    var autoRestore: Bool = false   // Re-open on display reconnect
}

/// Manages stream state, options, and frame processing for one display.
@MainActor
final class StreamViewModel: ObservableObject {
    @Published var config = StreamConfig()
    @Published var isCapturing = false

    let service: ScreenCaptureService

    init(displayID: CGDirectDisplayID) {
        service = ScreenCaptureService(displayID: displayID)
    }

    // MARK: - Capture control

    func startCapture() {
        Task {
            await service.startCapture(showCursor: config.showCursor)
            isCapturing = service.isCapturing
        }
    }

    func stopCapture() {
        Task {
            await service.stopCapture()
            isCapturing = false
        }
    }

    // MARK: - Frame processing

    /// Applies rotation, flip, crop, and filter to a raw captured CIImage.
    func processedImage(_ raw: CIImage) -> CIImage {
        var image = raw

        // 1. Crop
        if config.cropEnabled && config.cropInset > 0 {
            let ext = image.extent
            let pct = config.cropInset / 100.0
            let cropped = CGRect(
                x: ext.width * pct,
                y: ext.height * pct,
                width: ext.width * (1 - 2 * pct),
                height: ext.height * (1 - 2 * pct)
            )
            image = image.cropped(to: cropped)
            image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        }

        // 2. Rotation (clockwise)
        if config.rotation != 0 {
            image = applyRotation(image, degreesCW: config.rotation)
        }

        // 3. Flip
        if config.flipH {
            let t = CGAffineTransform(scaleX: -1, y: 1)
                .concatenating(CGAffineTransform(translationX: image.extent.width, y: 0))
            image = image.transformed(by: t)
        }
        if config.flipV {
            let t = CGAffineTransform(scaleX: 1, y: -1)
                .concatenating(CGAffineTransform(translationX: 0, y: image.extent.height))
            image = image.transformed(by: t)
        }

        // 4. Video filter
        switch config.filterName {
        case "grayscale":
            if let f = CIFilter(name: "CIColorControls") {
                f.setValue(image, forKey: kCIInputImageKey)
                f.setValue(0.0, forKey: kCIInputSaturationKey)
                image = f.outputImage ?? image
            }
        case "blur":
            if let f = CIFilter(name: "CIGaussianBlur") {
                f.setValue(image, forKey: kCIInputImageKey)
                f.setValue(4.0, forKey: kCIInputRadiusKey)
                image = (f.outputImage ?? image).cropped(to: image.extent)
            }
        case "sharpen":
            if let f = CIFilter(name: "CIUnsharpMask") {
                f.setValue(image, forKey: kCIInputImageKey)
                f.setValue(1.5, forKey: kCIInputIntensityKey)
                f.setValue(2.0, forKey: kCIInputRadiusKey)
                image = (f.outputImage ?? image).cropped(to: image.extent)
            }
        case "invert":
            if let f = CIFilter(name: "CIColorInvert") {
                f.setValue(image, forKey: kCIInputImageKey)
                image = f.outputImage ?? image
            }
        default:
            break
        }

        return image
    }

    // MARK: - Rotation helper

    /// Rotates a CIImage by `degrees` clockwise, then normalizes extent to origin (0,0).
    private func applyRotation(_ image: CIImage, degreesCW: Int) -> CIImage {
        // Negative radians = clockwise in standard math coordinate system
        let radians = -CGFloat(degreesCW) * .pi / 180.0
        let rotated = image.transformed(by: CGAffineTransform(rotationAngle: radians))
        let norm = CGAffineTransform(
            translationX: -rotated.extent.minX,
            y: -rotated.extent.minY
        )
        return rotated.transformed(by: norm)
    }
}
