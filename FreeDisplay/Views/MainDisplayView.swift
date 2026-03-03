import SwiftUI

/// Displays the "Set as Main Display" control inside DisplayDetailView.
/// Shows a status row when this display is already main, or a tappable button otherwise.
struct MainDisplayView: View {
    @ObservedObject var display: DisplayInfo
    @EnvironmentObject var displayManager: DisplayManager

    var body: some View {
        if display.isMain {
            HStack {
                Image(systemName: "m.circle.fill")
                    .foregroundColor(.blue)
                    .frame(width: 20)
                Text("当前主显示屏")
                    .font(.body)
                Spacer()
                Text("主")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .cornerRadius(3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        } else {
            HStack {
                Image(systemName: "m.circle.fill")
                    .foregroundColor(.blue)
                    .frame(width: 20)
                Text("设为主显示屏")
                    .font(.body)
                Spacer()
                Image(systemName: "arrow.right.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture {
                ArrangementService.shared.setAsMainDisplay(
                    display.displayID,
                    among: displayManager.displays
                )
            }
        }
    }
}
