import SwiftUI

/// Expandable section for screen rotation control.
/// Displays four options: 0°, 90°, 180°, 270° with the current angle highlighted.
struct RotationView: View {
    @ObservedObject var display: DisplayInfo

    private struct RotationOption: Identifiable {
        let id: Int  // degrees
        let label: String
        let icon: String
    }

    private let options: [RotationOption] = [
        RotationOption(id: 0,   label: "关闭旋转 (0°)",  icon: "display"),
        RotationOption(id: 90,  label: "旋转 90°",       icon: "rotate.right"),
        RotationOption(id: 180, label: "旋转 180°",      icon: "arrow.up.and.down"),
        RotationOption(id: 270, label: "旋转 270°",      icon: "rotate.left"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(options) { option in
                Button(action: { applyRotation(option.id) }) {
                    HStack {
                        Image(systemName: option.icon)
                            .frame(width: 20)
                            .foregroundColor(isSelected(option.id) ? .blue : .primary)
                        Text(option.label)
                            .foregroundColor(.primary)
                        Spacer()
                        if isSelected(option.id) {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func isSelected(_ degrees: Int) -> Bool {
        Int(display.rotation) == degrees
    }

    private func applyRotation(_ degrees: Int) {
        let success = RotationService.shared.setRotation(degrees, for: display.displayID)
        if success {
            display.rotation = Double(degrees)
        }
    }
}
