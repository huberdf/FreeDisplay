import SwiftUI

/// Expandable section for ICC color profile selection.
/// Lists all installed profiles alphabetically; highlights the active one.
struct ColorProfileView: View {
    @ObservedObject var display: DisplayInfo
    @State private var profiles: [ICCProfile] = []
    @State private var isLoading: Bool = false
    @State private var selectedPath: URL?
    @State private var applyingPath: URL? = nil
    @State private var applyError: String?
    @State private var applySuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(width: 14, height: 14)
                    Text("正在加载描述文件…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            } else if profiles.isEmpty {
                Text("未找到描述文件")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            } else {
                if applySuccess {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("已应用")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                if let error = applyError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }

                // Recommended profiles (display-specific or well-known)
                let recommended = recommendedProfiles
                let rest = otherProfiles

                if !recommended.isEmpty {
                    SectionBadge(title: "推荐")
                    ForEach(recommended) { profile in
                        ProfileRow(
                            profile: profile,
                            isSelected: selectedPath == profile.path,
                            isApplying: applyingPath == profile.path,
                            isDisabled: applyingPath != nil,
                            onTap: { applyProfile(profile) }
                        )
                        .help("切换至此颜色配置文件")
                    }
                }

                if !rest.isEmpty {
                    SectionBadge(title: "所有描述文件")
                    ForEach(rest) { profile in
                        ProfileRow(
                            profile: profile,
                            isSelected: selectedPath == profile.path,
                            isApplying: applyingPath == profile.path,
                            isDisabled: applyingPath != nil,
                            onTap: { applyProfile(profile) }
                        )
                        .help("切换至此颜色配置文件")
                    }
                }
            }
        }
        .task { await loadProfiles() }
    }

    // MARK: - Grouping

    private var recommendedProfiles: [ICCProfile] {
        let keywords = ["sRGB", "P3", "Display", "LCD", "Apple", "Color LCD"]
        return profiles.filter { p in
            keywords.contains { p.name.localizedCaseInsensitiveContains($0) }
        }
    }

    private var otherProfiles: [ICCProfile] {
        let recommended = Set(recommendedProfiles.map(\.path))
        return profiles.filter { !recommended.contains($0.path) }
    }

    // MARK: - Actions

    @MainActor
    private func loadProfiles() async {
        isLoading = true
        let displayID = display.displayID
        let svc = ColorProfileService.shared
        let loaded = await svc.enumerateProfiles()
        let currentURL = svc.currentProfileURL(for: displayID)
        profiles = loaded
        selectedPath = currentURL
        isLoading = false
    }

    @MainActor
    private func applyProfile(_ profile: ICCProfile) {
        guard applyingPath == nil else { return }
        applyError = nil
        applySuccess = false
        Task { @MainActor in
            applyingPath = profile.path
            defer { applyingPath = nil }
            let success = ColorProfileService.shared.setProfile(profile, for: display.displayID)
            if success {
                selectedPath = profile.path
                applySuccess = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    applySuccess = false
                }
            } else {
                applyError = String(localized: "应用失败，请重试")
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    applyError = nil
                }
            }
        }
    }
}

// MARK: - Sub-views

private struct SectionBadge: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue)
            .cornerRadius(4)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }
}

private struct ProfileRow: View {
    let profile: ICCProfile
    let isSelected: Bool
    let isApplying: Bool
    let isDisabled: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                if isApplying {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .font(.caption)
                        .foregroundColor(isSelected ? .blue : .secondary)
                        .frame(width: 14)
                }
                Text(profile.name)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                if profile.colorSpaceType != "RGB" {
                    Text(profile.colorSpaceType)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(3)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled && !isApplying)
        .opacity(isDisabled && !isApplying ? 0.45 : 1.0)
        .background(isSelected ? Color.blue.opacity(0.05) : Color.primary.opacity(isHovered ? 0.06 : 0))
        .onHover { isHovered = $0 }
    }
}
