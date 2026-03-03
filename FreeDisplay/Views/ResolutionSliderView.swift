import SwiftUI

/// Horizontal slider to scrub through available resolution modes.
/// Left side: small monitor icon. Right side: "WxH" current resolution text.
/// Releasing the slider applies the selected mode.
struct ResolutionSliderView: View {
    @ObservedObject var display: DisplayInfo
    /// Index into display.availableModes
    @State private var sliderIndex: Double = 0
    @State private var isSwitching: Bool = false

    private var modes: [DisplayMode] { display.availableModes }

    private var maxIndex: Double {
        max(0, Double(modes.count - 1))
    }

    private var previewMode: DisplayMode? {
        guard !modes.isEmpty else { return nil }
        let idx = min(Int(sliderIndex.rounded()), modes.count - 1)
        return modes[idx]
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "display")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 14)

            Slider(
                value: $sliderIndex,
                in: 0...max(1, maxIndex),
                step: 1
            )
            .disabled(modes.isEmpty || isSwitching)
            .onReceive(display.$currentDisplayMode) { mode in
                syncSliderToCurrentMode()
            }
            .onAppear {
                syncSliderToCurrentMode()
            }

            Text(previewMode?.resolutionString ?? "—")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 72, alignment: .trailing)
                .monospacedDigit()
                .animation(nil, value: sliderIndex)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in applySelectedMode() }
        )
    }

    private func syncSliderToCurrentMode() {
        guard let current = display.currentDisplayMode,
              let idx = modes.firstIndex(where: { $0.id == current.id }) else { return }
        sliderIndex = Double(idx)
    }

    private func applySelectedMode() {
        guard !modes.isEmpty, !isSwitching else { return }
        let idx = min(Int(sliderIndex.rounded()), modes.count - 1)
        let selected = modes[idx]
        guard selected.id != display.currentDisplayMode?.id else { return }
        isSwitching = true
        Task { @MainActor in
            let success = await ResolutionService.shared.setDisplayMode(selected, for: display.displayID)
            if success {
                display.currentDisplayMode = selected
            }
            isSwitching = false
        }
    }
}
