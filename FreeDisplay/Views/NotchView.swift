import SwiftUI
import AppKit

/// Displays notch information and provides a toggle to cover the notch with a black overlay.
/// Only visible for built-in displays that actually have a notch (safeAreaInsets.top > 0).
struct NotchView: View {
    @ObservedObject var display: DisplayInfo
    @State private var isHidingNotch: Bool = false
    @State private var isHovered = false

    private func syncState() {
        isHidingNotch = NotchOverlayManager.shared.isShowingOverlay(for: display.displayID)
    }

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
                    MenuItemIcon(systemName: "camera.aperture", color: .blue)
                    Text("刘海")
                        .font(.body)
                    Text(String(format: "%.0f pt", notchHeight))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)

                // Hide/show toggle
                HStack {
                    MenuItemIcon(systemName: isHidingNotch ? "eye.slash" : "eye", color: .secondary)
                    Text("隐藏刘海区域")
                        .font(.body)
                    Spacer()
                    Toggle("", isOn: $isHidingNotch)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                        .onChange(of: isHidingNotch) { _, newValue in
                            if newValue {
                                NotchOverlayManager.shared.showOverlay(for: display.displayID)
                            } else {
                                NotchOverlayManager.shared.hideOverlay(for: display.displayID)
                            }
                        }
                        .help("在顶部菜单栏区域显示黑色遮罩以隐藏刘海")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(isHovered ? 0.06 : 0))
                .onHover { isHovered = $0 }
            }
            .onAppear {
                syncState()
            }
        }
    }
}
