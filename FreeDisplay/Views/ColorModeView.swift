import SwiftUI
import CoreGraphics

/// Expandable section for color mode display and frame buffer type selection.
/// Shows current color info (bit depth, SDR/HDR) and lets the user pick a
/// frame buffer type (Standard / Inverted) via public CoreGraphics gamma APIs.
struct ColorModeView: View {
    @ObservedObject var display: DisplayInfo
    @State private var framebufferType: FramebufferType = .standard

    enum FramebufferType: String, CaseIterable, Identifiable {
        case standard          = "标准帧缓存"
        case inverted          = "反色帧缓存"
        case grayscale         = "灰阶帧缓存"
        case invertedGrayscale = "反色灰度帧缓存"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .standard:          return "display"
            case .inverted:          return "rectangle.inset.filled"
            case .grayscale:         return "circle.lefthalf.striped.horizontal"
            case .invertedGrayscale: return "circle.filled.pattern.diagonalline.rectangle"
            }
        }

        /// Whether this type can be applied via public CoreGraphics gamma APIs.
        var isSupported: Bool {
            self == .standard || self == .inverted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Current mode info row
            colorInfoRow

            Divider()
                .padding(.horizontal, 12)
                .padding(.vertical, 2)

            // Frame buffer type options
            ForEach(FramebufferType.allCases) { type in
                framebufferRow(for: type)
            }
        }
    }

    // MARK: - Color info row

    private var colorInfoRow: some View {
        HStack(spacing: 4) {
            let desc = ColorProfileService.shared.colorModeDescription(for: display.displayID)
            Text(desc)
                .font(.caption)
                .foregroundColor(.secondary)
            ColorBadge(text: "SDR")
            ColorBadge(text: "RGB")
            ColorBadge(text: "全范围")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    // MARK: - Frame buffer rows

    private func framebufferRow(for type: FramebufferType) -> some View {
        Button(action: { selectFramebuffer(type) }) {
            HStack(spacing: 8) {
                Image(systemName: framebufferType == type ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundColor(framebufferType == type ? .blue : .secondary)
                    .frame(width: 14)
                Image(systemName: type.icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                Text(type.rawValue)
                    .font(.body)
                Spacer()
                if !type.isSupported {
                    Text("需辅助功能权限")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(type.isSupported ? 1.0 : 0.5)
        .disabled(!type.isSupported)
    }

    // MARK: - Actions

    private func selectFramebuffer(_ type: FramebufferType) {
        guard type.isSupported else { return }
        framebufferType = type
        applyGamma(for: type)
    }

    /// Applies the frame buffer effect via CoreGraphics gamma formula.
    /// Standard:  output = input       (identity)
    /// Inverted:  output = 1 - input   (color inversion)
    private func applyGamma(for type: FramebufferType) {
        let id = display.displayID
        switch type {
        case .standard:
            // Identity transfer: min=0, max=1, gamma=1
            CGSetDisplayTransferByFormula(id, 0.0, 1.0, 1.0,
                                              0.0, 1.0, 1.0,
                                              0.0, 1.0, 1.0)
        case .inverted:
            // Inverted transfer: min=1, max=0, gamma=1  →  output = 1 - input
            CGSetDisplayTransferByFormula(id, 1.0, 0.0, 1.0,
                                              1.0, 0.0, 1.0,
                                              1.0, 0.0, 1.0)
        default:
            break
        }
    }
}

// MARK: - Helper

private struct ColorBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.12))
            .cornerRadius(3)
    }
}
