import SwiftUI

struct DisplayModeListView: View {
    @ObservedObject var display: DisplayInfo
    @State private var favorites: Set<Int32> = []
    @State private var filterHiDPIOnly: Bool = false
    @State private var isSwitching: Bool = false
    @State private var flashModeID: Int32? = nil

    private var modes: [DisplayMode] {
        if filterHiDPIOnly {
            return display.availableModes.filter { $0.isHiDPI }
        }
        return display.availableModes
    }

    // Native + non-scaled HiDPI (isNative) modes
    private var defaultModes: [DisplayMode] {
        modes.filter { $0.isNative || (!$0.isHiDPI && $0.isNative) || ($0.isNative) }
            .filter { !($0.isHiDPI && !$0.isNative) }
    }

    // HiDPI scaled modes (HiDPI but not native resolution)
    private var hiDPIScaledModes: [DisplayMode] {
        modes.filter { $0.isHiDPI && !$0.isNative }
    }

    // Non-HiDPI, non-native modes
    private var otherModes: [DisplayMode] {
        modes.filter { !$0.isNative && !$0.isHiDPI }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("显示模式")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { HiDPIService.shared.refreshModes(for: display) }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("刷新模式列表")

                Button(action: { filterHiDPIOnly.toggle() }) {
                    Image(systemName: filterHiDPIOnly ? "line.horizontal.3.decrease.circle.fill" : "line.horizontal.3.decrease.circle")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("只显示 HiDPI 模式")
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 2)

            if !defaultModes.isEmpty {
                SectionHeader(title: "默认及原生模式")
                ForEach(defaultModes) { mode in
                    ModeRow(
                        mode: mode,
                        isCurrent: mode.id == display.currentDisplayMode?.id,
                        isFavorite: favorites.contains(mode.id),
                        isSwitching: isSwitching,
                        isFlashing: flashModeID == mode.id,
                        onTap: { switchTo(mode) },
                        onFavorite: { toggleFavorite(mode) }
                    )
                }
            }

            if !hiDPIScaledModes.isEmpty {
                SectionHeader(title: "HiDPI 缩放模式")
                ForEach(hiDPIScaledModes) { mode in
                    ModeRow(
                        mode: mode,
                        isCurrent: mode.id == display.currentDisplayMode?.id,
                        isFavorite: favorites.contains(mode.id),
                        isSwitching: isSwitching,
                        isFlashing: flashModeID == mode.id,
                        onTap: { switchTo(mode) },
                        onFavorite: { toggleFavorite(mode) }
                    )
                }
            }

            if !otherModes.isEmpty {
                SectionHeader(title: "其他可用模式")
                ForEach(otherModes) { mode in
                    ModeRow(
                        mode: mode,
                        isCurrent: mode.id == display.currentDisplayMode?.id,
                        isFavorite: favorites.contains(mode.id),
                        isSwitching: isSwitching,
                        isFlashing: flashModeID == mode.id,
                        onTap: { switchTo(mode) },
                        onFavorite: { toggleFavorite(mode) }
                    )
                }
            }

            if modes.isEmpty {
                Text("没有可用的显示模式")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
    }

    private func switchTo(_ mode: DisplayMode) {
        guard !isSwitching else { return }

        if mode.id == display.currentDisplayMode?.id {
            withAnimation(.easeInOut(duration: 0.15)) {
                flashModeID = mode.id
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    flashModeID = nil
                }
            }
            return
        }

        isSwitching = true
        Task { @MainActor in
            let success = await ResolutionService.shared.setDisplayMode(mode, for: display.displayID)
            if success {
                display.currentDisplayMode = mode
            }
            isSwitching = false
        }
    }

    private func toggleFavorite(_ mode: DisplayMode) {
        if favorites.contains(mode.id) {
            favorites.remove(mode.id)
        } else {
            favorites.insert(mode.id)
        }
    }
}

// MARK: - Sub-views

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 1)
    }
}

private struct ModeRow: View {
    let mode: DisplayMode
    let isCurrent: Bool
    let isFavorite: Bool
    let isSwitching: Bool
    let isFlashing: Bool
    let onTap: () -> Void
    let onFavorite: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isCurrent ? "circle.fill" : "circle")
                .font(.caption2)
                .foregroundColor(isCurrent ? .accentColor : .secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(mode.resolutionString)
                    .font(.caption)
                    .foregroundColor(isCurrent ? .primary : .secondary)
                    .monospacedDigit()
                if mode.isHiDPI && !mode.isNative {
                    Text("@ \(mode.pixelWidth)×\(mode.pixelHeight)px")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }

            if mode.isHiDPI {
                TagBadge(text: "HiDPI", color: .blue)
            }
            if mode.isNative {
                TagBadge(text: "原生", color: .green)
            }

            Spacer()

            Text(mode.refreshRateString)
                .font(.caption2)
                .foregroundColor(.secondary)
                .monospacedDigit()

            Button(action: onFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.caption2)
                    .foregroundColor(isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(
            isFlashing
                ? Color.accentColor.opacity(0.25)
                : (isCurrent ? Color.accentColor.opacity(0.07) : Color.clear)
        )
        .onTapGesture {
            guard !isSwitching else { return }
            onTap()
        }
    }
}

private struct TagBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundColor(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.12))
            .cornerRadius(3)
    }
}
