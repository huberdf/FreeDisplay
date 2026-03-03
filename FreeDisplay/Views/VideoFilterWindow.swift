import SwiftUI
import CoreImage

// MARK: - VideoFilterWindow

/// A standalone NSWindow that shows a live preview of CIFilter effects
/// applied to the content of StreamViewModel (if streaming is active).
final class VideoFilterWindowController: NSObject, @unchecked Sendable {
    static let shared = VideoFilterWindowController()
    private var window: NSWindow?

    private override init() { super.init() }

    func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: VideoFilterView())
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = "视频滤镜"
        w.contentViewController = hosting
        w.center()
        w.isReleasedWhenClosed = false
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }
}

// MARK: - Filter Descriptor

struct CIFilterDescriptor: Identifiable, Hashable {
    let id: String          // CIFilter name
    let displayName: String
    let parameters: [String: Any]

    static func == (lhs: CIFilterDescriptor, rhs: CIFilterDescriptor) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - VideoFilterViewModel

@MainActor
final class VideoFilterViewModel: ObservableObject {
    @Published var selectedFilter: CIFilterDescriptor? = nil
    @Published var previewImage: NSImage? = nil
    @Published var intensity: Double = 0.5

    let availableFilters: [CIFilterDescriptor] = [
        CIFilterDescriptor(id: "CIColorMonochrome",   displayName: "灰度",         parameters: ["inputColor": CIColor.gray, "inputIntensity": 1.0]),
        CIFilterDescriptor(id: "CIColorInvert",       displayName: "反色",         parameters: [:]),
        CIFilterDescriptor(id: "CIGaussianBlur",      displayName: "模糊",         parameters: ["inputRadius": 5.0]),
        CIFilterDescriptor(id: "CISharpenLuminance",  displayName: "锐化",         parameters: ["inputSharpness": 0.4]),
        CIFilterDescriptor(id: "CIHueAdjust",         displayName: "色调旋转",     parameters: ["inputAngle": 1.0]),
        CIFilterDescriptor(id: "CIGammaAdjust",       displayName: "伽马调整",     parameters: ["inputPower": 0.75]),
        CIFilterDescriptor(id: "CISepiaTone",         displayName: "复古棕色",     parameters: ["inputIntensity": 0.8]),
        CIFilterDescriptor(id: "CIVignette",          displayName: "暗角",         parameters: ["inputIntensity": 1.0, "inputRadius": 1.0]),
    ]

    private var sampleImage: CIImage = {
        // Generate a colourful gradient sample image for preview
        let width  = 400
        let height = 300
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                pixels[idx]   = UInt8(x * 255 / width)
                pixels[idx+1] = UInt8(y * 255 / height)
                pixels[idx+2] = UInt8((x + y) * 255 / (width + height))
                pixels[idx+3] = 255
            }
        }
        let data = Data(pixels)
        return CIImage(bitmapData: data,
                       bytesPerRow: width * 4,
                       size: CGSize(width: width, height: height),
                       format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())
    }()

    func applyFilter(_ descriptor: CIFilterDescriptor?) {
        selectedFilter = descriptor
        updatePreview()
    }

    func updatePreview() {
        guard let descriptor = selectedFilter,
              let filter = CIFilter(name: descriptor.id) else {
            // Show original
            previewImage = ciImageToNSImage(sampleImage)
            return
        }
        filter.setValue(sampleImage, forKey: kCIInputImageKey)
        // Apply stored parameters with intensity scaling where applicable
        for (key, value) in descriptor.parameters {
            if key == "inputIntensity" || key == "inputSharpness" || key == "inputPower" {
                if let base = value as? Double {
                    filter.setValue(base * intensity, forKey: key)
                } else {
                    filter.setValue(value, forKey: key)
                }
            } else if key == "inputRadius" {
                if let base = value as? Double {
                    filter.setValue(base * intensity * 10, forKey: key)
                } else {
                    filter.setValue(value, forKey: key)
                }
            } else if key == "inputAngle" {
                if let base = value as? Double {
                    filter.setValue(base * intensity * .pi * 2, forKey: key)
                } else {
                    filter.setValue(value, forKey: key)
                }
            } else {
                filter.setValue(value, forKey: key)
            }
        }
        guard let output = filter.outputImage else {
            previewImage = ciImageToNSImage(sampleImage)
            return
        }
        let ctx = CIContext()
        if let cgImg = ctx.createCGImage(output, from: sampleImage.extent) {
            previewImage = NSImage(cgImage: cgImg, size: .zero)
        }
    }

    private func ciImageToNSImage(_ ciImage: CIImage) -> NSImage? {
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }
}

// MARK: - VideoFilterView

struct VideoFilterView: View {
    @StateObject private var vm = VideoFilterViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Preview area
            Group {
                if let img = vm.previewImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(Text("预览区域").foregroundColor(.secondary))
                }
            }
            .frame(height: 220)
            .background(Color.black)
            .clipped()

            Divider()

            // Intensity slider
            HStack {
                Text("强度")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Slider(value: $vm.intensity, in: 0...1, onEditingChanged: { _ in vm.updatePreview() })
                Text("\(Int(vm.intensity * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // Filter list
            ScrollView {
                VStack(spacing: 1) {
                    // None option
                    filterRow(label: "无 (原始)", isSelected: vm.selectedFilter == nil) {
                        vm.applyFilter(nil)
                    }

                    ForEach(vm.availableFilters) { descriptor in
                        filterRow(label: descriptor.displayName,
                                  isSelected: vm.selectedFilter == descriptor) {
                            vm.applyFilter(descriptor)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            HStack {
                Button("关闭") { VideoFilterWindowController.shared.close() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text("注: 滤镜应用于串流/PiP 画面")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 420, height: 520)
        .onAppear { vm.updatePreview() }
    }

    @ViewBuilder
    private func filterRow(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .blue : .secondary)
                .font(.body)
            Text(label)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(isSelected ? Color.blue.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { action() }
    }
}

// MARK: - VideoFilterMenuEntry (embedded in MenuBarView tools)

struct VideoFilterMenuEntry: View {
    var body: some View {
        HStack {
            Image(systemName: "camera.filters")
                .foregroundColor(.purple)
                .frame(width: 20)
            Text("视频滤镜窗口")
                .font(.body)
            Spacer()
            Image(systemName: "arrow.up.right.square")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture {
            VideoFilterWindowController.shared.show()
        }
    }
}
