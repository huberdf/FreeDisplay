import SwiftUI

/// "Sidecar" section — drives a portrait iPad by rotating a virtual display and streaming
/// it full-screen to the (landscape-locked) Sidecar display.
/// See `RotatedSidecarService` for why it works this way.
struct RotatedSidecarView: View {
    @ObservedObject private var service = RotatedSidecarService.shared
    @State private var sidecarDisplays: [CGDirectDisplayID] = []
    @State private var hasScreenRecording = true
    @State private var isWorking = false
    @State private var isHovered = false

    private var canEnable: Bool { !sidecarDisplays.isEmpty && hasScreenRecording }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Prerequisites — spelled out, because each one fails in a way that looks like
            // something else (a missing display, a black screen, a cropped image).
            VStack(alignment: .leading, spacing: 4) {
                RequirementRow(
                    ok: hasScreenRecording,
                    text: "屏幕录制权限",
                    fixLabel: hasScreenRecording ? nil : "打开设置",
                    fix: {
                        RotatedSidecarService.requestScreenRecordingPermission()
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
                // Not a check — macOS cannot see the iPad's rotation lock — so it sits
                // with the prerequisites as guidance rather than as a pass/fail row.
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                        .font(.caption)
                        .accessibilityHidden(true)
                    Text("请在 iPad 仍为横屏时打开「旋转锁定」，然后再转动 iPad。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 6)

            // Main toggle — mirrors AutoBrightnessView's row.
            HStack {
                MenuItemIcon(
                    systemName: "rotate.right.fill",
                    color: service.isActive ? .indigo : .secondary
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("竖屏模式")
                        .font(.body)
                    Text("竖向使用 iPad")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                        .frame(width: 24)
                } else {
                    Toggle("", isOn: Binding(
                        get: { service.isActive },
                        set: { _ in toggle() }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .disabled(!canEnable && !service.isActive)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(isHovered ? 0.06 : 0))
            .onHover { isHovered = $0 }
            .contentShape(Rectangle())

            // Orientation only matters once it is running.
            if service.isActive {
                HStack(spacing: 6) {
                    Text("方向")
                        .font(.caption)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { service.orientation },
                        set: { setOrientation($0) }
                    )) {
                        ForEach(RotatedSidecarService.Orientation.allCases) { o in
                            Text(o.label).tag(o)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .fixedSize()
                    .disabled(isWorking)
                    .help("与 iPad 实际摆放方向保持一致")
                }
                .padding(.horizontal, 12)
                .padding(.top, 2)
                .padding(.bottom, 6)
            }

            if let err = service.errorMessage {
                HStack(spacing: 5) {
                    Image(systemName: service.autoStartFailed
                          ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(service.autoStartFailed ? .red : .orange)
                        .font(.caption2)
                        .accessibilityHidden(true)
                    Text(err)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 4)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification
        )) { _ in
            refresh()
        }
    }

    private func refresh() {
        sidecarDisplays = RotatedSidecarService.connectedSidecarDisplays()
        hasScreenRecording = RotatedSidecarService.hasScreenRecordingPermission
    }

    private func toggle() {
        guard let target = sidecarDisplays.first else { return }
        isWorking = true
        Task { @MainActor in
            if service.isActive {
                await service.stop()
            } else {
                await service.start(sidecarDisplayID: target, orientation: service.orientation)
            }
            isWorking = false
        }
    }

    /// Changing orientation while running has to restart the pipeline — the rotation is
    /// baked into the capture chain when it starts.
    private func setOrientation(_ new: RotatedSidecarService.Orientation) {
        guard new != service.orientation else { return }
        guard service.isActive, let target = sidecarDisplays.first else {
            service.orientation = new
            return
        }
        isWorking = true
        Task { @MainActor in
            await service.stop()
            await service.start(sidecarDisplayID: target, orientation: new)
            isWorking = false
        }
    }
}

// MARK: - RequirementRow

/// One prerequisite line: green tick when satisfied, red cross when not.
private struct RequirementRow: View {
    let ok: Bool
    let text: LocalizedStringKey
    var fixLabel: LocalizedStringKey? = nil
    var fix: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(ok ? .green : .red)
                .font(.caption)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .foregroundColor(ok ? .secondary : .primary)
            Spacer()
            if let fixLabel, let fix {
                Button(fixLabel, action: fix)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }
}
