import SwiftUI
import AppKit

/// Displays notch information and provides a toggle to cover the notch with a black overlay.
/// Only visible for built-in displays that actually have a notch (safeAreaInsets.top > 0).
struct NotchView: View {
    @ObservedObject var display: DisplayInfo
    @State private var isHidingNotch: Bool = false

    private var notchHeight: CGFloat {
        guard display.isBuiltin,
              let screen = NSScreen.screen(for: display.displayID)
        else { return 0 }
        return screen.safeAreaInsets.top
    }

    var body: some View {
        if notchHeight > 0 {
            VStack(alignment: .leading, spacing: 0) {
                // Info row
                HStack {
                    Image(systemName: "camera.aperture")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    Text("刘海")
                        .font(.body)
                    Text(String(format: "%.0f pt", notchHeight))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

                // Hide/show toggle
                HStack {
                    Image(systemName: isHidingNotch ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    Text("隐藏刘海")
                        .font(.body)
                    Spacer()
                    Toggle("", isOn: $isHidingNotch)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                        .onChange(of: isHidingNotch) { newValue in
                            if newValue {
                                NotchOverlayManager.shared.showOverlay(for: display.displayID)
                            } else {
                                NotchOverlayManager.shared.hideOverlay(for: display.displayID)
                            }
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
        }
    }
}
