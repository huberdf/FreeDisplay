import SwiftUI

/// "Auto Brightness" section — follows builtin screen brightness and adjusts external display brightness automatically.
struct AutoBrightnessView: View {
    @StateObject private var service = AutoBrightnessService.shared
    @State private var isHovered = false

    /// True only after the service has polled at least once and found no builtin display.
    private var builtinUnavailable: Bool {
        service.hasPolled && service.builtinBrightness <= 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main toggle
            HStack {
                MenuItemIcon(systemName: "sun.max.trianglebadge.exclamationmark", color: service.isEnabled ? .orange : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Otomatik Parlaklık", "Auto Brightness"))
                        .font(.body)
                    Text(statusText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: $service.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .disabled(builtinUnavailable)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(isHovered ? 0.06 : 0))
            .onHover { isHovered = $0 }
            .contentShape(Rectangle())
        }
    }

    private var statusText: String {
        if builtinUnavailable {
            return L("Dahili ekran algılanmadı", "No built-in display detected")
        } else if service.isEnabled {
            return L("Dahili ekran parlaklığıyla eşitleniyor", "Syncing with built-in display brightness")
        } else {
            return L("Harici ekranları dahili ekran parlaklığına göre ayarla", "Adjust external displays to follow built-in brightness")
        }
    }
}
