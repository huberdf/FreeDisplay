import SwiftUI

/// "自动亮度" section — reads ambient light sensor and adjusts display brightness automatically.
struct AutoBrightnessView: View {
    @StateObject private var service = AutoBrightnessService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Main toggle
            HStack {
                Image(systemName: "a.circle.fill")
                    .foregroundColor(service.isEnabled ? .blue : .secondary)
                    .frame(width: 20)
                Text("自动亮度")
                    .font(.body)
                Spacer()
                Toggle("", isOn: $service.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())

            if service.isEnabled {
                // Sensitivity slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("灵敏度")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(sensitivityLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $service.sensitivity, in: 0...1, step: 0.1)
                        .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

                // Lux status
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                    if service.lastLux > 0 {
                        Text(String(format: "当前环境光: %.0f lux", service.lastLux))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("未检测到环境光传感器")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }
        }
    }

    private var sensitivityLabel: String {
        switch service.sensitivity {
        case 0..<0.3: return "低"
        case 0.3..<0.7: return "中"
        default: return "高"
        }
    }
}
