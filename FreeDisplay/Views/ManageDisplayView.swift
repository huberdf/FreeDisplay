import SwiftUI
import AppKit
import IOKit
import IOKit.pwr_mgt

/// "管理显示器" section: system preferences shortcut, visual identification,
/// and prevent-sleep assertion.
struct ManageDisplayView: View {
    @ObservedObject var display: DisplayInfo
    @State private var preventSleep: Bool = false
    @State private var sleepAssertionID: IOPMAssertionID = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Open system display settings
            HStack {
                Image(systemName: "display")
                    .foregroundColor(.blue)
                    .frame(width: 20)
                Text("配置显示...")
                    .font(.body)
                Spacer()
                Image(systemName: "arrow.up.forward.square")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture { openDisplaySettings() }

            // Visual identification
            HStack {
                Image(systemName: "eye.fill")
                    .foregroundColor(.blue)
                    .frame(width: 20)
                Text("视觉识别")
                    .font(.body)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture { showVisualIdentification() }

            Text("使用 ⌥ Option + 点击显示菜单标题以快速识别。")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            // Prevent sleep toggle
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.blue)
                    .frame(width: 20)
                Text("连接时防止进入睡眠")
                    .font(.body)
                Spacer()
                Toggle("", isOn: $preventSleep)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .onChange(of: preventSleep) { newValue in
                        if newValue {
                            createSleepAssertion()
                        } else {
                            releaseSleepAssertion()
                        }
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .onDisappear {
            if sleepAssertionID != 0 {
                IOPMAssertionRelease(sleepAssertionID)
                sleepAssertionID = 0
                preventSleep = false
            }
        }
    }

    // MARK: - Actions

    private func openDisplaySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showVisualIdentification() {
        VisualIdentificationManager.shared.show(for: display.displayID, name: display.name)
    }

    private func createSleepAssertion() {
        let reason = "FreeDisplay: Display Connected" as CFString
        IOPMAssertionCreateWithName(
            "NoIdleSleep" as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &sleepAssertionID
        )
    }

    private func releaseSleepAssertion() {
        if sleepAssertionID != 0 {
            IOPMAssertionRelease(sleepAssertionID)
            sleepAssertionID = 0
        }
    }
}
