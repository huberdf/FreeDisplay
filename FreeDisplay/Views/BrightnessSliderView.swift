import SwiftUI

struct BrightnessSliderView: View {
    @ObservedObject var display: DisplayInfo
    @State private var localBrightness: Double = 50
    @State private var isDragging: Bool = false
    @State private var valueHighlighted: Bool = false
    @State private var highlightTask: Task<Void, Never>?
    @State private var ddcStatus: Bool? = nil  // nil=unknown, true=DDC, false=Software
    /// Throttle DDC writes during drag to ~100ms intervals.
    @State private var lastDDCWrite: Date = .distantPast

    var body: some View {
        VStack(spacing: 2) {
            // Mode indicator row
            HStack(spacing: 4) {
                Spacer()
                if display.isBuiltin {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                    Text("系统")
                        .font(.caption2)
                        .foregroundColor(.blue)
                } else if let status = ddcStatus {
                    Circle()
                        .fill(status ? Color.green : Color.orange)
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                    Text(status ? "DDC" : "软件")
                        .font(.caption2)
                        .foregroundColor(status ? .green : .orange)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 2)
            .accessibilityLabel(display.isBuiltin ? "亮度控制模式：系统" : "亮度控制模式：\(ddcStatus == true ? "DDC 硬件" : "软件模拟")")
            .help(display.isBuiltin ? "系统亮度：通过系统 API 控制内建显示屏亮度" : "DDC: 硬件直接控制亮度\n软件: 通过软件调节亮度")

            HStack(spacing: 6) {
                let sunIcon: String = {
                    if localBrightness < 30 { return "sun.min" }
                    else if localBrightness < 70 { return "sun.min.fill" }
                    else { return "sun.max.fill" }
                }()
                Image(systemName: sunIcon)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .frame(width: 14)
                    .animation(.easeInOut(duration: 0.2), value: sunIcon)
                    .accessibilityHidden(true)

                Slider(value: $localBrightness, in: 5...100, step: 1) { editing in
                    isDragging = editing
                    if !editing {
                        // Drag ended — apply final value with smooth transition and show highlight.
                        withAnimation(.easeOut(duration: 0.3)) { valueHighlighted = true }
                        highlightTask?.cancel()
                        highlightTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            withAnimation(.easeOut(duration: 0.3)) { valueHighlighted = false }
                        }
                        Task { @MainActor in
                            // Use smooth transition from current hardware brightness to slider value.
                            BrightnessService.shared.setBrightnessSmooth(localBrightness, for: display)
                            updateDDCStatus()
                        }
                        lastDDCWrite = Date()
                    }
                }
                .accessibilityLabel("显示器亮度")
                .accessibilityValue("\(Int(localBrightness))%")
                .help("拖动调整亮度")
                .onChange(of: localBrightness) { _, newValue in
                    guard isDragging else { return }
                    // Apply immediately — the service chooses software or DDC internally.
                    // For DDC displays, throttle to ~100ms to avoid flooding the I2C bus.
                    let isDDC = ddcStatus == true
                    let now = Date()
                    if isDDC && now.timeIntervalSince(lastDDCWrite) < 0.1 {
                        // Too soon for another DDC write; the drag-end handler will flush the final value.
                        display.brightness = newValue
                        return
                    }
                    lastDDCWrite = now
                    display.brightness = newValue
                    Task { @MainActor in
                        await BrightnessService.shared.setBrightness(newValue, for: display)
                    }
                }

                Image(systemName: "sun.max")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 14)
                    .accessibilityHidden(true)

                let brightnessLabel: String = {
                    if ddcStatus == false { return "软件 \(Int(localBrightness))%" }
                    return "\(Int(localBrightness))%"
                }()
                Text(brightnessLabel)
                    .font(.caption)
                    .foregroundColor(valueHighlighted ? .accentColor : .secondary)
                    .frame(width: 52, alignment: .trailing)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .task(id: display.displayID) {
            localBrightness = display.brightness
            updateDDCStatus()
        }
        .onChange(of: display.brightness) { _, newValue in
            if !isDragging && abs(newValue - localBrightness) >= 1 {
                localBrightness = newValue
            }
        }
    }

    private func updateDDCStatus() {
        ddcStatus = BrightnessService.shared.isDDCAvailable(for: display.displayID)
    }
}

struct CombinedBrightnessView: View {
    let displays: [DisplayInfo]
    @State private var combinedBrightness: Double = 50
    @State private var isDragging: Bool = false
    /// Throttle DDC writes during drag to ~100ms intervals.
    @State private var lastDDCWrite: Date = .distantPast

    private var averageBrightness: Double {
        guard !displays.isEmpty else { return 50 }
        return displays.map(\.brightness).reduce(0, +) / Double(displays.count)
    }

    /// True if any display in the group uses DDC (so we apply throttle).
    private var anyDDC: Bool {
        displays.contains { BrightnessService.shared.isDDCAvailable(for: $0.displayID) == true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "sun.max.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
                    .accessibilityHidden(true)
                Text("亮度（组合）")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(combinedBrightness))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 6) {
                Image(systemName: "sun.min")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 14)
                    .accessibilityHidden(true)

                Slider(value: $combinedBrightness, in: 5...100, step: 1) { editing in
                    isDragging = editing
                    if !editing {
                        // Drag ended — flush final value to all displays with smooth transition.
                        Task { @MainActor in
                            for display in displays {
                                BrightnessService.shared.setBrightnessSmooth(combinedBrightness, for: display)
                            }
                        }
                        lastDDCWrite = Date()
                    }
                }
                .accessibilityLabel("组合亮度")
                .accessibilityValue("\(Int(combinedBrightness))%")
                .onChange(of: combinedBrightness) { _, newValue in
                    guard isDragging else { return }
                    let now = Date()
                    if anyDDC && now.timeIntervalSince(lastDDCWrite) < 0.1 {
                        // Throttle DDC — update model only; drag-end flushes final value.
                        for display in displays { display.brightness = newValue }
                        return
                    }
                    lastDDCWrite = now
                    Task { @MainActor in
                        for display in displays {
                            display.brightness = newValue
                            await BrightnessService.shared.setBrightness(newValue, for: display)
                        }
                    }
                }

                Image(systemName: "sun.max")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 14)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onAppear {
            combinedBrightness = averageBrightness
        }
    }
}
