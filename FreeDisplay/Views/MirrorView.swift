import SwiftUI
import CoreGraphics

/// "屏幕镜像" section — lets the user mirror this display to another display,
/// or stop an active mirror session.
struct MirrorView: View {
    @ObservedObject var display: DisplayInfo
    @EnvironmentObject var displayManager: DisplayManager

    /// The display this display is currently mirroring (nil = not mirroring).
    @State private var activeMirrorSource: CGDirectDisplayID? = nil

    // MARK: - Helpers

    /// Other online displays that can serve as mirror targets.
    private var mirrorTargets: [DisplayInfo] {
        displayManager.displays.filter { $0.displayID != display.displayID && $0.isEnabled }
    }

    private var isCurrentlyMirroring: Bool {
        activeMirrorSource != nil
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if mirrorTargets.isEmpty {
                Text("没有可用的目标显示器")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                Text("将此显示器内容镜像到：")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 2)

                ForEach(mirrorTargets) { target in
                    mirrorTargetRow(target: target)
                }
            }

            // Stop mirroring button
            Button(action: stopMirroring) {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                    Text("停止镜像")
                }
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundColor(isCurrentlyMirroring ? .red : .secondary)
            .disabled(!isCurrentlyMirroring)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .onAppear { refreshMirrorState() }
    }

    // MARK: - Mirror Target Row

    @ViewBuilder
    private func mirrorTargetRow(target: DisplayInfo) -> some View {
        let isActive = activeMirrorSource == target.displayID

        HStack {
            Image(systemName: target.isBuiltin ? "laptopcomputer" : "display")
                .foregroundColor(isActive ? .blue : .primary)
                .frame(width: 20)
            Text(target.name)
                .font(.body)
                .foregroundColor(isActive ? .blue : .primary)
            Spacer()
            if isActive {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture { startMirroring(to: target) }
    }

    // MARK: - Actions

    private func startMirroring(to target: DisplayInfo) {
        let success = MirrorService.shared.enableMirror(
            source: target.displayID,
            target: display.displayID
        )
        if success {
            activeMirrorSource = target.displayID
        }
    }

    private func stopMirroring() {
        let success = MirrorService.shared.disableMirror(displayID: display.displayID)
        if success {
            activeMirrorSource = nil
        }
    }

    private func refreshMirrorState() {
        activeMirrorSource = MirrorService.shared.mirrorSource(for: display.displayID)
    }
}
