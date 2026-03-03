import SwiftUI

// MARK: - Shared Icon Helper

/// A colored rounded-square SF Symbol icon, consistent with macOS Settings style.
struct MenuItemIcon: View {
    let systemName: String
    var color: Color = .blue

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 20, height: 20)
            .background(RoundedRectangle(cornerRadius: 5).fill(color))
    }
}

struct MenuBarView: View {
    @EnvironmentObject var displayManager: DisplayManager
    @StateObject private var updateService = UpdateService.shared
    @StateObject private var settings = SettingsService.shared
    @State private var expandedDisplayIDs: Set<CGDirectDisplayID> = []
    @State private var showArrangement: Bool = false
    @State private var showVirtualDisplays: Bool = false
    @State private var showAutoBrightness: Bool = false
    @State private var showSettings: Bool = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // 显示器列表
                ForEach(displayManager.displays) { display in
                    VStack(spacing: 0) {
                        DisplayRowView(
                            display: display,
                            isExpanded: expandedDisplayIDs.contains(display.displayID),
                            onToggleExpand: {
                                if expandedDisplayIDs.contains(display.displayID) {
                                    expandedDisplayIDs.remove(display.displayID)
                                } else {
                                    expandedDisplayIDs.insert(display.displayID)
                                }
                            }
                        )

                        if expandedDisplayIDs.contains(display.displayID) {
                            DisplayDetailView(display: display)
                        }
                    }
                }

                // 排列显示器 section (Phase 4)
                if displayManager.displays.count > 1 {
                    Divider()
                        .padding(.vertical, 2)

                    HStack {
                        MenuItemIcon(systemName: "rectangle.3.offgrid")
                        Text("排列显示器")
                            .font(.body)
                        Spacer()
                        Image(systemName: showArrangement ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .animation(.easeInOut(duration: 0.18), value: showArrangement)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showArrangement.toggle() } }

                    if showArrangement {
                        ArrangementView()
                            .environmentObject(displayManager)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                Divider()
                    .padding(.vertical, 2)

                // 组合亮度控制（Phase 2）
                if settings.showCombinedBrightness {
                    CombinedBrightnessView(displays: displayManager.displays)
                    Divider()
                        .padding(.vertical, 2)
                }

                // 工具区标题
                HStack {
                    Image(systemName: "ellipsis.circle.fill")
                        .foregroundColor(.secondary)
                    Text("工具")
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 2)

                // 虚拟显示器工具入口 (Phase 10)
                HStack {
                    MenuItemIcon(systemName: "display.2")
                    Text("显示器和虚拟屏幕")
                        .font(.body)
                    Spacer()
                    Image(systemName: showVirtualDisplays ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .animation(.easeInOut(duration: 0.18), value: showVirtualDisplays)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showVirtualDisplays.toggle() } }

                if showVirtualDisplays {
                    VirtualDisplayView()
                        .padding(.leading, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // 自动亮度入口 (Phase 11)
                HStack {
                    MenuItemIcon(systemName: "sun.and.horizon.fill", color: .orange)
                    Text("自动亮度")
                        .font(.body)
                    Spacer()
                    Image(systemName: showAutoBrightness ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .animation(.easeInOut(duration: 0.18), value: showAutoBrightness)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showAutoBrightness.toggle() } }

                if showAutoBrightness {
                    AutoBrightnessView()
                        .padding(.leading, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // 视频滤镜入口 (Phase 12)
                VideoFilterMenuEntry()

                // 系统颜色取色器入口 (Phase 12)
                SystemColorMenuEntry()

                Divider()
                    .padding(.vertical, 2)

                // 设置区 (Phase 12)
                HStack {
                    MenuItemIcon(systemName: "gearshape.fill", color: .gray)
                    Text("设置")
                        .font(.body)
                    Spacer()
                    Image(systemName: showSettings ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .animation(.easeInOut(duration: 0.18), value: showSettings)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showSettings.toggle() } }

                if showSettings {
                    SettingsView()
                        .padding(.leading, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Divider()
                    .padding(.vertical, 2)

                // 更新提示 (Phase 12)
                if updateService.hasUpdate, let ver = updateService.latestVersion {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.green)
                            .frame(width: 20)
                        Text("新版本 v\(ver) 可用")
                            .font(.caption)
                            .foregroundColor(.green)
                        Spacer()
                        Button("查看") { updateService.openReleasePage() }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                }

                // 版本号与退出
                HStack {
                    Text("FreeDisplay v\(updateService.currentVersion)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: {
                        NSApplication.shared.terminate(nil)
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "xmark")
                            Text("退出")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 320)
        .frame(maxHeight: 620)
        .padding(.vertical, 8)
        .task {
            if settings.checkUpdatesOnLaunch {
                await updateService.checkForUpdates()
            }
        }
    }
}

// MARK: - SettingsView (Phase 12: embedded in MenuBarView)

struct SettingsView: View {
    @StateObject private var settings = SettingsService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 开机自启动
            Toggle(isOn: Binding(
                get: { settings.launchAtLogin },
                set: { newValue in
                    if newValue {
                        LaunchService.shared.enable()
                    } else {
                        LaunchService.shared.disable()
                    }
                    settings.launchAtLogin = newValue
                }
            )) {
                HStack(spacing: 6) {
                    Image(systemName: "power")
                        .foregroundColor(.green)
                        .frame(width: 16)
                    Text("开机自动启动")
                        .font(.body)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 12)

            // 显示组合亮度
            Toggle(isOn: $settings.showCombinedBrightness) {
                HStack(spacing: 6) {
                    Image(systemName: "sun.min.fill")
                        .foregroundColor(.yellow)
                        .frame(width: 16)
                    Text("显示组合亮度控制")
                        .font(.body)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 12)

            // 启动时检查更新
            Toggle(isOn: $settings.checkUpdatesOnLaunch) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise.circle")
                        .foregroundColor(.blue)
                        .frame(width: 16)
                    Text("启动时检查更新")
                        .font(.body)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - DisplayRowView

struct DisplayRowView: View {
    @ObservedObject var display: DisplayInfo
    @EnvironmentObject var displayManager: DisplayManager

    let isExpanded: Bool
    let onToggleExpand: () -> Void

    var body: some View {
        HStack {
            // Expand/collapse arrow button
            Button(action: onToggleExpand) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 16)
            }
            .buttonStyle(.plain)

            Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                .foregroundColor(.blue)
            Text(display.name)
                .lineLimit(1)
                .truncationMode(.tail)
            if display.isMain {
                Text("主")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.blue)
                    .cornerRadius(3)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { display.isEnabled },
                set: { _ in displayManager.toggleDisplay(display) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
