import SwiftUI

/// Expandable "图像调整" section — 11 sliders for software gamma/image adjustments.
/// Mirrors BetterDisplay's Image Adjustment panel.
struct ImageAdjustmentView: View {
    @ObservedObject var display: DisplayInfo

    // MARK: - Local adjustment state (mirrors GammaAdjustment)
    @State private var contrast: Double = 0           // -100 … +100
    @State private var gammaVal: Double = 0           // -100 … +100
    @State private var gain: Double = 0               // -100 … +100
    @State private var colorTemperature: Double = 0   // -100 … +100
    @State private var quantLevels: Double = 256      // 2 … 256 (256 = ∞)
    @State private var rGamma: Double = 0
    @State private var gGamma: Double = 0
    @State private var bGamma: Double = 0
    @State private var rGain: Double = 0
    @State private var gGain: Double = 0
    @State private var bGain: Double = 0
    @State private var isInverted: Bool = false
    @State private var isPaused: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Group 1: Global adjustments ────────────────────────────────
            adjustRow(icon: "circle.righthalf.filled",   label: "对比度",  value: $contrast).help("调整 对比度")
            adjustRow(icon: "sparkle",                   label: "伽马值",  value: $gammaVal).help("调整 伽马值")
            adjustRow(icon: "bolt.fill",                 label: "增益",    value: $gain).help("调整 增益")
            adjustRow(icon: "thermometer.medium",        label: "色温",    value: $colorTemperature).help("调整 色温")
            quantizationRow

            Divider()
                .padding(.horizontal, 12)
                .padding(.vertical, 2)

            // ── Group 2: Per-channel gamma ─────────────────────────────────
            adjustRow(icon: "r.circle",      label: "伽马值 R",  value: $rGamma, accent: .red).help("调整 红色伽马值")
            adjustRow(icon: "g.circle",      label: "伽马值 G",  value: $gGamma, accent: .green).help("调整 绿色伽马值")
            adjustRow(icon: "b.circle",      label: "伽马值 B",  value: $bGamma, accent: .blue).help("调整 蓝色伽马值")

            Divider()
                .padding(.horizontal, 12)
                .padding(.vertical, 2)

            // ── Group 3: Per-channel gain ──────────────────────────────────
            adjustRow(icon: "r.circle.fill", label: "增益 R",    value: $rGain,  accent: .red).help("调整 红色增益")
            adjustRow(icon: "g.circle.fill", label: "增益 G",    value: $gGain,  accent: .green).help("调整 绿色增益")
            adjustRow(icon: "b.circle.fill", label: "增益 B",    value: $bGain,  accent: .blue).help("调整 蓝色增益")

            Divider()
                .padding(.horizontal, 12)
                .padding(.vertical, 2)

            // ── HDR warning ────────────────────────────────────────────────
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
                Text("调整可能影响 HDR 内容！")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)

            // ── Action buttons ─────────────────────────────────────────────
            HStack(spacing: 8) {
                actionButton(
                    title: "反转色彩",
                    systemImage: "circle.lefthalf.filled",
                    isActive: isInverted
                ) {
                    isInverted.toggle()
                    commitAdjustment()
                }
                .help("反转显示器色彩（类似夜间模式）")

                actionButton(
                    title: isPaused ? "继续调整" : "暂停调整",
                    systemImage: isPaused ? "play.circle" : "pause.circle",
                    isActive: isPaused
                ) {
                    isPaused.toggle()
                    if isPaused {
                        GammaService.shared.applyIdentity(for: display.displayID)
                    } else {
                        commitAdjustment()
                    }
                }
                .help("暂时停用色彩调整，恢复原始显示")

                actionButton(
                    title: "重置全部",
                    systemImage: "arrow.counterclockwise",
                    isActive: false
                ) {
                    resetAll()
                }
                .help("重置所有色彩调整为默认值")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .onAppear {
            if let saved = GammaService.shared.loadSavedState(for: display.displayID) {
                contrast = saved.contrast
                gammaVal = saved.gammaVal
                gain = saved.gain
                colorTemperature = saved.colorTemperature
                rGamma = saved.rGamma; gGamma = saved.gGamma; bGamma = saved.bGamma
                rGain = saved.rGain;   gGain = saved.gGain;   bGain = saved.bGain
                quantLevels = Double(saved.quantizationLevels)
                isInverted = saved.isInverted
                isPaused = saved.isPaused
                // Re-apply visually so the display matches the saved state immediately.
                if !saved.isPaused {
                    GammaService.shared.apply(saved, for: display.displayID)
                }
            }
        }
        .onDisappear {
            let isAtZero = contrast == 0 && gammaVal == 0 && gain == 0 &&
                colorTemperature == 0 && rGamma == 0 && gGamma == 0 && bGamma == 0 &&
                rGain == 0 && gGain == 0 && bGain == 0 && !isInverted &&
                quantLevels == 256
            if isAtZero {
                GammaService.shared.clearSavedState(for: display.displayID)
                GammaService.shared.resetSingleDisplay(display.displayID)
            } else {
                let adj = GammaAdjustment(
                    contrast: contrast, gammaVal: gammaVal, gain: gain,
                    colorTemperature: colorTemperature,
                    rGamma: rGamma, gGamma: gGamma, bGamma: bGamma,
                    rGain: rGain, gGain: gGain, bGain: bGain,
                    quantizationLevels: Int(quantLevels),
                    isInverted: isInverted, isPaused: isPaused
                )
                GammaService.shared.saveState(adj, for: display.displayID)
            }
        }
    }

    // MARK: - Slider row builder

    private func adjustRow(
        icon: String,
        label: String,
        value: Binding<Double>,
        accent: Color = .blue
    ) -> some View {
        AdjustRow(icon: icon, label: label, value: value, accent: accent, commitAction: commitAdjustment)
    }

    // MARK: - Quantization row

    private var quantizationRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.fill")
                .foregroundColor(.blue)
                .frame(width: 18)
                .font(.caption)

            Text("量化")
                .font(.caption)
                .frame(width: 72, alignment: .leading)

            Slider(value: $quantLevels, in: 2...256, step: 1) { _ in
                commitAdjustment()
            }
            .help("调整 量化级别")

            Text(quantLevels >= 255 ? "∞" : "\(Int(quantLevels))")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 38, alignment: .trailing)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    // MARK: - Action button builder

    private func actionButton(
        title: String,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption)
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.08))
            .foregroundColor(isActive ? .blue : .primary)
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func commitAdjustment() {
        guard !isPaused else { return }
        let adj = GammaAdjustment(
            contrast: contrast,
            gammaVal: gammaVal,
            gain: gain,
            colorTemperature: colorTemperature,
            rGamma: rGamma, gGamma: gGamma, bGamma: bGamma,
            rGain: rGain,   gGain: gGain,   bGain: bGain,
            quantizationLevels: Int(quantLevels),
            isInverted: isInverted,
            isPaused: false
        )
        GammaService.shared.apply(adj, for: display.displayID)
    }

    @MainActor
    private func resetAll() {
        contrast = 0; gammaVal = 0; gain = 0; colorTemperature = 0
        rGamma = 0; gGamma = 0; bGamma = 0
        rGain = 0;  gGain = 0;  bGain = 0
        quantLevels = 256
        isInverted = false
        isPaused = false
        GammaService.shared.clearSavedState(for: display.displayID)
        GammaService.shared.resetSingleDisplay(display.displayID)
    }
}

private struct AdjustRow: View {
    let icon: String
    let label: String
    @Binding var value: Double
    let accent: Color
    let commitAction: () -> Void

    @State private var highlighted: Bool = false

    private func percentLabel(_ v: Double) -> String {
        let sign = v > 0 ? "+" : ""
        return "\(sign)\(Int(v))%"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(accent)
                .frame(width: 18)
                .font(.caption)

            Text(label)
                .font(.caption)
                .frame(width: 72, alignment: .leading)

            Slider(value: $value, in: -100...100, step: 1) { editing in
                if !editing {
                    commitAction()
                    withAnimation(.easeOut(duration: 0.3)) { highlighted = true }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        withAnimation(.easeOut(duration: 0.3)) { highlighted = false }
                    }
                }
            }
            .tint(accent)

            Text(percentLabel(value))
                .font(.caption)
                .foregroundColor(highlighted ? accent : .secondary)
                .frame(width: 38, alignment: .trailing)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }
}
