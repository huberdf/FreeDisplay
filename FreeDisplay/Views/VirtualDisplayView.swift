import SwiftUI
import CoreGraphics

/// "虚拟显示器" management section shown in the MenuBarView tools area.
/// Lists all saved virtual display configurations and allows creating / deleting them.
struct VirtualDisplayView: View {
    @StateObject private var service = VirtualDisplayService.shared
    @State private var showCreateForm = false

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
                }
            }

            // "+" create button
            Button(action: { showCreateForm.toggle() }) {
                HStack {
                    Image(systemName: showCreateForm ? "minus.circle.fill" : "plus.circle.fill")
                        .foregroundColor(.blue)
                    Text(showCreateForm ? "取消" : "创建虚拟显示器")
                        .font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            if showCreateForm {
                CreateVirtualDisplayForm(onConfirm: { config in
                    service.addAndCreate(config)
                    showCreateForm = false
                })
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
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
            Button(action: { service.removeConfig(id: config.id) }) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - Create Form

/// Inline form for creating a new virtual display configuration.
struct CreateVirtualDisplayForm: View {
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
                    .frame(width: 50, alignment: .leading)
                TextField("显示器名称", text: $name)
                    .textFieldStyle(.plain)
                    .font(.caption)
            }

            // Resolution preset picker
            HStack {
                Text("分辨率")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .leading)
                Picker("", selection: $selectedPreset) {
                    ForEach(presets.indices, id: \.self) { i in
                        Text(presets[i].label).tag(i)
                    }
                }
                .pickerStyle(.menu)
                .font(.caption)
                .labelsHidden()
            }

            // HiDPI toggle
            HStack {
                Text("HiDPI")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .leading)
                Toggle("", isOn: $hiDPI)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
                Text("启用高分辨率缩放")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Auto-create toggle
            HStack {
                Text("自动")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .leading)
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
                Text("创建")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private func confirm() {
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
