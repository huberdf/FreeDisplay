import SwiftUI
import CoreGraphics

/// "虚拟显示器" management section shown in the MenuBarView tools area.
/// Lists all saved virtual display configurations and allows creating / deleting them.
struct VirtualDisplayView: View {
    @StateObject private var service = VirtualDisplayService.shared
    @State private var showCreateForm = false
    @State private var configToDelete: UUID?
    @State private var isCreating: Bool = false
    @State private var createError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if service.configs.isEmpty {
                Text("暂无虚拟显示器")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ForEach(service.configs) { config in
                    configRow(config: config)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                }
            }

            // "+" create button
            Button(action: { showCreateForm.toggle() }) {
                HStack {
                    Image(systemName: showCreateForm ? "minus.circle.fill" : "plus.circle.fill")
                        .foregroundColor(.accentColor)
                    Text(showCreateForm ? "取消" : "创建虚拟显示器")
                        .font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .help("创建新的虚拟显示器")

            if let err = createError {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            if showCreateForm {
                CreateVirtualDisplayForm(isCreating: $isCreating, onConfirm: { config in
                    isCreating = true
                    createError = nil
                    Task { @MainActor in
                        let success = await service.addAndCreate(config)
                        isCreating = false
                        if success {
                            showCreateForm = false
                        } else {
                            createError = "虚拟显示器创建失败，请重试"
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 3_000_000_000)
                                createError = nil
                            }
                        }
                    }
                })
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .alert("确认删除", isPresented: Binding(
            get: { configToDelete != nil },
            set: { if !$0 { configToDelete = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let id = configToDelete {
                    service.removeConfig(id: id)
                }
                configToDelete = nil
            }
            Button("取消", role: .cancel) {
                configToDelete = nil
            }
        } message: {
            if let id = configToDelete, service.isActive(id) {
                Text("此虚拟显示器当前处于活跃状态，删除后将立即停用。")
            } else {
                Text("确认删除此虚拟显示器配置？")
            }
        }
    }

    // MARK: - Config Row

    @ViewBuilder
    private func configRow(config: VirtualDisplayService.VirtualDisplayConfig) -> some View {
        let active = service.isActive(config.id)

        HStack(spacing: 8) {
            Image(systemName: "display.2")
                .foregroundColor(active ? .blue : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(config.name)
                    .font(.body)
                    .lineLimit(1)
                Text("\(config.width)×\(config.height)\(config.hiDPI ? " · HiDPI" : "") · \(Int(config.refreshRate))Hz")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Active / inactive badge
            if active {
                Text("活跃")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .cornerRadius(4)
            }

            // Delete button
            Button(action: {
                configToDelete = config.id
            }) {
                Label("删除", systemImage: "trash")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("删除此虚拟显示器")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.secondary.opacity(0.08))
        )
        .contextMenu {
            Button(role: .destructive) {
                configToDelete = config.id
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

// MARK: - Create Form

/// Inline form for creating a new virtual display configuration.
struct CreateVirtualDisplayForm: View {
    @Binding var isCreating: Bool
    let onConfirm: (VirtualDisplayService.VirtualDisplayConfig) -> Void

    @State private var name: String = "虚拟显示器"
    @State private var selectedPreset: Int = 0
    @State private var hiDPI: Bool = true
    @State private var autoCreate: Bool = true

    private let presets: [(label: String, width: Int, height: Int)] = [
        ("1920×1080 (FHD)", 1920, 1080),
        ("2560×1440 (QHD)", 2560, 1440),
        ("3840×2160 (4K)",  3840, 2160),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Name field
            HStack {
                Text("名称")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .leading)
                TextField("显示器名称", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }

            // Resolution preset picker
            HStack {
                Text("分辨率")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .leading)
                Picker("", selection: $selectedPreset) {
                    ForEach(presets.indices, id: \.self) { i in
                        Text(presets[i].label).tag(i)
                    }
                }
                .pickerStyle(.menu)
                .font(.caption)
                .labelsHidden()
                .help("选择虚拟显示器分辨率")
            }

            // HiDPI toggle
            HStack {
                Text("HiDPI")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .leading)
                Toggle("", isOn: $hiDPI)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
                    .help("启用高分辨率模式（Retina）")
                Text("启用高分辨率缩放")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Auto-create toggle
            HStack {
                Text("自动")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .leading)
                Toggle("", isOn: $autoCreate)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
                Text("启动时自动创建")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Confirm button
            Button(action: confirm) {
                HStack(spacing: 6) {
                    if isCreating {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                    }
                    Text(isCreating ? "创建中..." : "创建")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isCreating)
        }
        .padding(.vertical, 4)
    }

    private func confirm() {
        guard !isCreating else { return }
        let preset = presets[selectedPreset]
        let config = VirtualDisplayService.VirtualDisplayConfig(
            name: name.isEmpty ? "虚拟显示器" : name,
            width: preset.width,
            height: preset.height,
            refreshRate: 60,
            hiDPI: hiDPI,
            autoCreate: autoCreate
        )
        onConfirm(config)
    }
}
