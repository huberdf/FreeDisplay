import SwiftUI

/// Expandable section for ICC color profile selection.
/// Lists all installed profiles alphabetically; highlights the active one.
struct ColorProfileView: View {
    @ObservedObject var display: DisplayInfo
    @State private var profiles: [ICCProfile] = []
    @State private var selectedPath: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if profiles.isEmpty {
                Text("正在加载描述文件…")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            } else {
                // Recommended profiles (display-specific or well-known)
                let recommended = recommendedProfiles
                let rest = otherProfiles

                if !recommended.isEmpty {
                    SectionBadge(title: "推荐")
                    ForEach(recommended) { profile in
                        ProfileRow(
                            profile: profile,
                            isSelected: selectedPath == profile.path,
                            onTap: { applyProfile(profile) }
                        )
                    }
                }

                if !rest.isEmpty {
                    SectionBadge(title: "所有描述文件")
                    ForEach(rest) { profile in
                        ProfileRow(
                            profile: profile,
                            isSelected: selectedPath == profile.path,
                            onTap: { applyProfile(profile) }
                        )
                    }
                }
            }
        }
        .onAppear { loadProfiles() }
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

    private func loadProfiles() {
        let svc = ColorProfileService.shared
        profiles = svc.enumerateProfiles()
        let currentName = svc.currentColorSpaceName(for: display.displayID)
        selectedPath = profiles.first { $0.name == currentName }?.path
    }

    private func applyProfile(_ profile: ICCProfile) {
        let success = ColorProfileService.shared.setProfile(profile, for: display.displayID)
        if success {
            selectedPath = profile.path
        }
    }
}

// MARK: - Sub-views

private struct SectionBadge: View {
    let title: String

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
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.caption)
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .frame(width: 14)
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
        .background(isSelected ? Color.blue.opacity(0.05) : Color.clear)
    }
}
