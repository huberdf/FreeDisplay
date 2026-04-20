import SwiftUI

struct DisplayModeListView: View {
    @ObservedObject var display: DisplayInfo
    @State private var isSwitching: Bool = false
    @State private var flashModeID: Int32? = nil
    @State private var switchingModeID: Int32? = nil
    @State private var showAllModes: Bool = false
    @State private var errorMessage: String?

    private var currentMode: DisplayMode? { display.currentDisplayMode }

    /// Group modes by (resolution + HiDPI), sorted by resolution descending.
    private var resolutionGroups: [ResolutionGroup] {
        let base = display.availableModes.filter {
            $0.width >= 1280 && $0.height >= 720
        }

        // Group by resolution + HiDPI
        var grouped: [String: [DisplayMode]] = [:]
        for mode in base {
            let key = "\(mode.width)x\(mode.height)_\(mode.isHiDPI)"
            grouped[key, default: []].append(mode)
        }

        return grouped.map { (key, modes) in
            let sorted = modes.sorted { $0.refreshRate > $1.refreshRate }
            return ResolutionGroup(
                width: sorted[0].width,
                height: sorted[0].height,
                isHiDPI: sorted[0].isHiDPI,
                modes: sorted
            )
        }
        .sorted { lhs, rhs in
            if lhs.width != rhs.width { return lhs.width > rhs.width }
            if lhs.height != rhs.height { return lhs.height > rhs.height }
            if lhs.isHiDPI != rhs.isHiDPI { return lhs.isHiDPI }
            return false
        }
    }

    /// Compact: show top 4 groups
    private var visibleGroups: [ResolutionGroup] {
        showAllModes ? resolutionGroups : Array(resolutionGroups.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
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
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 2)

            if resolutionGroups.isEmpty {
                Text("没有可用的显示模式")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                // Resolution rows
                ForEach(visibleGroups) { group in
                    ResolutionRow(
                        group: group,
                        currentMode: currentMode,
                        isSwitching: isSwitching,
                        switchingModeID: switchingModeID,
                        flashModeID: flashModeID,
                        onSelectMode: { switchTo($0) }
                    )
                }

                // Toggle button
                if resolutionGroups.count > 4 || showAllModes {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) { showAllModes.toggle() }
                    }) {
                        HStack(spacing: 4) {
                            Text(showAllModes ? "收起" : "显示全部 \(resolutionGroups.count) 个")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                            Image(systemName: showAllModes ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.accentColor)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                }
            }

            // Error message
            if let msg = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(.red)
                    Text(msg)
                        .font(.caption2)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.08))
                .cornerRadius(6)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Actions

    private func switchTo(_ mode: DisplayMode) {
        guard !isSwitching else { return }

        if mode.id == currentMode?.id {
            withAnimation(.easeInOut(duration: 0.15)) { flashModeID = mode.id }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 600_000_000)
                withAnimation(.easeInOut(duration: 0.15)) { flashModeID = nil }
            }
            return
        }

        isSwitching = true
        switchingModeID = mode.id
        let displayID = display.displayID
        Task { @MainActor in
            var success = await ResolutionService.shared.setDisplayMode(mode, for: displayID)
            if !success {
                try? await Task.sleep(nanoseconds: 200_000_000)
                success = await ResolutionService.shared.setDisplayMode(mode, for: displayID)
            }
            if success {
                try? await Task.sleep(nanoseconds: 300_000_000)
                let refreshedMode = await Task.detached(priority: .userInitiated) {
                    DisplayMode.currentMode(for: displayID)
                }.value
                if let rm = refreshedMode, rm.width == mode.width && rm.height == mode.height {
                    display.currentDisplayMode = rm
                } else {
                    display.currentDisplayMode = mode
                }
                errorMessage = nil
            } else {
                withAnimation {
                    errorMessage = String(localized: "无法切换到 \(mode.resolutionString)，请重试")
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    withAnimation { errorMessage = nil }
                }
            }
            isSwitching = false
            switchingModeID = nil
        }
    }
}

// MARK: - Data model

private struct ResolutionGroup: Identifiable {
    let width: Int
    let height: Int
    let isHiDPI: Bool
    let modes: [DisplayMode] // sorted by refresh rate descending

    var id: String { "\(width)x\(height)_\(isHiDPI)" }
    var resolutionString: String { "\(width)×\(height)" }
    var hasMultipleRates: Bool { modes.count > 1 }
    var bestMode: DisplayMode { modes[0] }
}

// MARK: - ResolutionRow

private struct ResolutionRow: View {
    let group: ResolutionGroup
    let currentMode: DisplayMode?
    let isSwitching: Bool
    let switchingModeID: Int32?
    let flashModeID: Int32?
    let onSelectMode: (DisplayMode) -> Void

    @State private var isHovered = false
    @State private var showRates = false

    private var isCurrent: Bool {
        group.modes.contains { $0.id == currentMode?.id }
    }

    private var isAnySwitching: Bool {
        group.modes.contains { $0.id == switchingModeID }
    }

    private var isFlashing: Bool {
        group.modes.contains { $0.id == flashModeID }
    }

    /// The active mode within this group (if current resolution matches)
    private var activeMode: DisplayMode? {
        group.modes.first { $0.id == currentMode?.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Resolution row
            HStack(spacing: 6) {
                if isAnySwitching {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                }

                Text(group.resolutionString)
                    .font(.caption)
                    .foregroundColor(isCurrent ? .primary : .secondary)
                    .monospacedDigit()

                if group.isHiDPI {
                    TagBadge(text: "HiDPI", color: .blue)
                }

                // Show current refresh rate
                if let active = activeMode {
                    Text(active.refreshRateString)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                if isCurrent {
                    Text("当前")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .cornerRadius(4)
                }

                Spacer()

                // Show chevron if multiple refresh rates
                if group.hasMultipleRates {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(showRates ? 90 : 0))
                        .animation(.easeInOut(duration: 0.2), value: showRates)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(
                isFlashing ? Color.accentColor.opacity(0.25) :
                isCurrent  ? Color.accentColor.opacity(0.10) :
                isHovered  ? Color.primary.opacity(0.06) : Color.clear
            )
            .onHover { isHovered = $0 }
            .opacity(isSwitching && !isAnySwitching ? 0.45 : 1.0)
            .onTapGesture {
                guard !isSwitching else { return }
                if group.hasMultipleRates {
                    withAnimation(.easeInOut(duration: 0.2)) { showRates.toggle() }
                } else {
                    onSelectMode(group.bestMode)
                }
            }

            // Refresh rate picker (expanded)
            if showRates && group.hasMultipleRates {
                RefreshRatePicker(
                    modes: group.modes,
                    activeMode: activeMode,
                    switchingModeID: switchingModeID,
                    onSelect: onSelectMode
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Refresh Rate Picker

private struct RefreshRatePicker: View {
    let modes: [DisplayMode]
    let activeMode: DisplayMode?
    let switchingModeID: Int32?
    let onSelect: (DisplayMode) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("刷新率")
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack(spacing: 2) {
                ForEach(modes) { mode in
                    RatePill(
                        mode: mode,
                        isActive: mode.id == activeMode?.id,
                        isSwitching: switchingModeID == mode.id,
                        onTap: { onSelect(mode) }
                    )
                }
            }
            .padding(2)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(6)
        }
    }
}

private struct RatePill: View {
    let mode: DisplayMode
    let isActive: Bool
    let isSwitching: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 3) {
                if isSwitching {
                    ProgressView()
                        .scaleEffect(0.4)
                        .frame(width: 10, height: 10)
                }
                Text(mode.refreshRateString)
                    .font(.caption2)
                    .fontWeight(isActive ? .medium : .regular)
                    .foregroundColor(isActive ? .white : .primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        isActive ? Color.accentColor :
                        isHovered ? Color.primary.opacity(0.06) : Color.clear
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - TagBadge

private struct TagBadge: View {
    let text: LocalizedStringKey
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
