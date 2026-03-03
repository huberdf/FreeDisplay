import SwiftUI

/// Per-display "配置保护" section — lets users lock specific display settings so any
/// system-level change is automatically reverted.
struct ConfigProtectionView: View {
    @ObservedObject var display: DisplayInfo
    @EnvironmentObject var displayManager: DisplayManager
    @StateObject private var service = ConfigProtectionService.shared

    @State private var showSnapshotSheet = false
    @State private var snapshotName = ""

    private var items: ProtectedItems {
        service.items(for: display.displayID)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<ProtectedItems, Value>) -> Binding<Value> {
        Binding(
            get: { items[keyPath: keyPath] },
            set: { newVal in
                var updated = items
                updated[keyPath: keyPath] = newVal
                service.updateItems(updated, for: display.displayID)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // --- Protection Toggles ---
            VStack(spacing: 0) {
                protectionRow(icon: "aspectratio", label: "分辨率", binding: binding(\.resolution))
                protectionRow(icon: "gauge.medium", label: "刷新率", binding: binding(\.refreshRate))
                protectionRow(icon: "wand.and.rays", label: "色彩模式", binding: binding(\.colorMode))
                protectionRow(icon: "wand.and.stars", label: "HDR 色彩模式", binding: binding(\.hdrColorMode))
                protectionRow(icon: "rotate.right", label: "旋转", binding: binding(\.rotation))
                protectionRow(icon: "paintpalette.fill", label: "颜色描述文件", binding: binding(\.colorProfile))
                protectionRow(icon: "paintpalette", label: "HDR 颜色描述文件", binding: binding(\.hdrColorProfile))
                protectionRow(icon: "sun.max.fill", label: "HDR 状态", binding: binding(\.hdrStatus))
                protectionRow(icon: "rectangle.2.swap", label: "镜像", binding: binding(\.mirror))
                protectionRow(icon: "star.fill", label: "主显示屏状态", binding: binding(\.mainDisplay))
            }

            Divider()
                .padding(.vertical, 2)

            // --- Enable / Disable All ---
            HStack(spacing: 8) {
                Button("启用所有保护") {
                    var all = items
                    all.enableAll()
                    service.updateItems(all, for: display.displayID)
                    ensureMonitoring()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("禁用所有保护") {
                    var all = items
                    all.disableAll()
                    service.updateItems(all, for: display.displayID)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)

            // --- Snapshot management ---
            HStack(spacing: 8) {
                Button("保存快照…") {
                    snapshotName = "快照 \(formattedDate())"
                    showSnapshotSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if !service.snapshots.isEmpty {
                    Menu("恢复快照") {
                        ForEach(service.snapshots) { snapshot in
                            Button(snapshot.name) {
                                service.restoreSnapshot(snapshot, displays: displayManager.displays)
                            }
                        }
                        Divider()
                        Menu("删除快照") {
                            ForEach(service.snapshots) { snapshot in
                                Button(snapshot.name) {
                                    service.deleteSnapshot(id: snapshot.id)
                                }
                            }
                        }
                    }
                    .menuStyle(.borderedButton)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 2)

            // --- Info text ---
            Text("此应用程序所做设置受到保护。")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
        }
        .sheet(isPresented: $showSnapshotSheet) {
            SaveSnapshotSheet(name: $snapshotName) {
                service.saveSnapshot(name: snapshotName, displays: displayManager.displays)
            }
        }
        .onChange(of: items.anyEnabled) { enabled in
            if enabled {
                ensureMonitoring()
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func protectionRow(icon: String, label: String, binding: Binding<Bool>) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 16)
                .font(.caption)
            Text(label)
                .font(.body)
            Spacer()
            Toggle("", isOn: binding)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func ensureMonitoring() {
        if !service.isMonitoring {
            service.startMonitoring(displays: displayManager.displays)
        }
    }

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: Date())
    }
}

// MARK: - Save Snapshot Sheet

private struct SaveSnapshotSheet: View {
    @Binding var name: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("保存配置快照")
                .font(.headline)

            TextField("快照名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    onSave()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 300)
    }
}
