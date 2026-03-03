import SwiftUI

struct BrightnessSliderView: View {
    @ObservedObject var display: DisplayInfo
    @State private var localBrightness: Double = 50
    @State private var isDragging: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sun.min")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 14)

            Slider(value: $localBrightness, in: 0...100, step: 1) { editing in
                isDragging = editing
                if !editing {
                    Task { @MainActor in
                        display.brightness = localBrightness
                        await BrightnessService.shared.setBrightness(localBrightness, for: display)
                    }
                }
            }

            Image(systemName: "sun.max")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 14)

            Text("\(Int(localBrightness))%")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 32, alignment: .trailing)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .onAppear {
            localBrightness = display.brightness
        }
        .onChange(of: display.brightness) { newValue in
            if !isDragging && abs(newValue - localBrightness) > 1 {
                localBrightness = newValue
            }
        }
    }
}

struct CombinedBrightnessView: View {
    let displays: [DisplayInfo]
    @State private var combinedBrightness: Double = 50
    @State private var isDragging: Bool = false

    private var averageBrightness: Double {
        guard !displays.isEmpty else { return 50 }
        return displays.map(\.brightness).reduce(0, +) / Double(displays.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "sun.max.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
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

                Slider(value: $combinedBrightness, in: 0...100, step: 1) { editing in
                    isDragging = editing
                    if !editing {
                        Task { @MainActor in
                            for display in displays {
                                display.brightness = combinedBrightness
                                await BrightnessService.shared.setBrightness(combinedBrightness, for: display)
                            }
                        }
                    }
                }

                Image(systemName: "sun.max")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 14)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onAppear {
            combinedBrightness = averageBrightness
        }
    }
}
