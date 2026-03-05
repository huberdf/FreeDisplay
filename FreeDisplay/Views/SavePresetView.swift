import SwiftUI

// MARK: - SavePresetView

/// Section in MenuBarView that lets users save the current display state as a named preset.
struct SavePresetView: View {
    @State private var isShowingSaveForm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toggle button
            Button(action: { isShowingSaveForm.toggle() }) {
                HStack {
                    Image(systemName: isShowingSaveForm ? "minus.circle.fill" : "plus.circle.fill")
                        .foregroundColor(.accentColor)
                    Text(isShowingSaveForm ? "取消" : "保存为预设")
                        .font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .help("将当前显示器配置保存为预设")

            if isShowingSaveForm {
                SavePresetForm(onSaved: { isShowingSaveForm = false })
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - SavePresetForm

/// Inline form for naming and saving the current display state as a preset.
struct SavePresetForm: View {
    let onSaved: () -> Void

    @State private var presetName: String = "我的预设"
    @State private var selectedIcon: String = "display"
    @State private var isSaving: Bool = false
    @State private var saveError: String?

    private let iconOptions: [(symbol: String, label: String)] = [
        ("display", "显示器"),
        ("sparkles.rectangle.stack", "HiDPI"),
        ("rectangle.on.rectangle", "镜像"),
        ("moon.fill", "夜间"),
        ("sun.max.fill", "日间"),
        ("gamecontroller.fill", "游戏"),
        ("person.fill", "个人"),
        ("briefcase.fill", "工作"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Name field
            HStack {
                Text("名称")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .leading)
                TextField("预设名称", text: $presetName)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }

            // Icon picker
            HStack(alignment: .top) {
                Text("图标")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .leading)
                    .padding(.top, 2)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(28), spacing: 4), count: 8),
                    spacing: 4
                ) {
                    ForEach(iconOptions, id: \.symbol) { option in
                        IconOptionButton(
                            symbol: option.symbol,
                            label: option.label,
                            isSelected: selectedIcon == option.symbol
                        ) {
                            selectedIcon = option.symbol
                        }
                    }
                }
            }

            // Error message
            if let err = saveError {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Save button
            Button(action: savePreset) {
                HStack(spacing: 6) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                    }
                    Text(isSaving ? "保存中..." : "保存")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isSaving || presetName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.15), value: saveError)
    }

    private func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        isSaving = true
        saveError = nil

        let preset = PresetService.shared.captureCurrentState(name: name, icon: selectedIcon)
        PresetService.shared.addPreset(preset)

        isSaving = false
        onSaved()
    }
}

// MARK: - IconOptionButton

struct IconOptionButton: View {
    let symbol: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundColor(isSelected ? .white : (isHovered ? .primary : .secondary))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected ? Color.indigo : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}
