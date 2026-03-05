import SwiftUI

// MARK: - PresetListView

/// Section in MenuBarView showing presets as a segmented toggle for built-ins,
/// plus a list for user-created presets.
struct PresetListView: View {
    @ObservedObject private var presetService = PresetService.shared

    private var builtinPresets: [DisplayPreset] {
        presetService.presets.filter { $0.isBuiltin }
    }

    private var userPresets: [DisplayPreset] {
        presetService.presets.filter { !$0.isBuiltin }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !builtinPresets.isEmpty {
                PresetSegmentedControl(
                    presets: builtinPresets,
                    matchID: presetService.currentPresetMatch(),
                    applyingID: presetService.applyingPresetID,
                    isApplying: presetService.isApplying
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            // User-created presets as rows
            ForEach(userPresets) { preset in
                PresetRow(
                    preset: preset,
                    isCurrentMatch: presetService.currentPresetMatch() == preset.id,
                    isApplying: presetService.applyingPresetID == preset.id
                )
            }

            // Save preset button
            SavePresetView()
        }
    }
}

// MARK: - Segmented Control for built-in presets

private struct PresetSegmentedControl: View {
    let presets: [DisplayPreset]
    let matchID: UUID?
    let applyingID: UUID?
    let isApplying: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(presets) { preset in
                PresetSegmentButton(
                    preset: preset,
                    isActive: matchID == preset.id,
                    isApplyingThis: applyingID == preset.id,
                    isDisabled: isApplying
                )
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.06))
        .cornerRadius(8)
    }
}

private struct PresetSegmentButton: View {
    let preset: DisplayPreset
    let isActive: Bool
    let isApplyingThis: Bool
    let isDisabled: Bool

    @State private var isHovered = false
    @State private var justApplied = false

    var body: some View {
        Button(action: apply) {
            HStack(spacing: 5) {
                if isApplyingThis {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: preset.icon)
                        .font(.caption2)
                        .foregroundColor(isActive ? .white : .secondary)
                }

                Text(preset.name)
                    .font(.caption)
                    .fontWeight(isActive ? .medium : .regular)
                    .foregroundColor(isActive ? .white : .primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        justApplied ? Color.green :
                        isActive ? Color.accentColor :
                        isHovered ? Color.primary.opacity(0.06) : Color.clear
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .help(isActive ? "当前模式" : "切换到\(preset.name)")
    }

    private func apply() {
        guard !isDisabled else { return }
        Task {
            await PresetService.shared.applyPreset(preset)
            withAnimation(.easeIn(duration: 0.15)) { justApplied = true }
            try? await Task.sleep(nanoseconds: 800_000_000)
            withAnimation(.easeOut(duration: 0.3)) { justApplied = false }
        }
    }
}

// MARK: - PresetRow (for user-created presets)

struct PresetRow: View {
    let preset: DisplayPreset
    let isCurrentMatch: Bool
    let isApplying: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            if isApplying {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 20, height: 20)
            } else {
                MenuItemIcon(systemName: preset.icon, color: isCurrentMatch ? .accentColor : .gray)
            }

            Text(preset.name)
                .font(.body)
                .lineLimit(1)

            Spacer()

            if isCurrentMatch {
                Text("当前")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(isHovered ? 0.06 : 0))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !PresetService.shared.isApplying else { return }
            Task { await PresetService.shared.applyPreset(preset) }
        }
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(role: .destructive) {
                PresetService.shared.deletePreset(id: preset.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .disabled(PresetService.shared.isApplying)
    }
}
