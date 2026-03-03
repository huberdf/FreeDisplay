import SwiftUI

struct DisplayDetailView: View {
    @ObservedObject var display: DisplayInfo
    @EnvironmentObject var displayManager: DisplayManager
    @State private var showModeList: Bool = false
    @State private var showRotation: Bool = false
    @State private var showColorProfile: Bool = false
    @State private var showColorMode: Bool = false
    @State private var showImageAdjustment: Bool = false
    @State private var showIntegratedControl: Bool = false
    @State private var showManageDisplay: Bool = false
    @State private var showMirror: Bool = false
    @State private var showStream: Bool = false
    @State private var showPiP: Bool = false
    @State private var showHiDPIVirtual: Bool = false
    @State private var showConfigProtection: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brightness slider (Phase 2)
            BrightnessSliderView(display: display)
                .padding(.leading, -12) // compensate for outer leading padding

            Divider()
                .padding(.vertical, 2)

            // Resolution slider (Phase 3)
            ResolutionSliderView(display: display)
                .padding(.leading, -12) // compensate for outer leading padding

            // Display mode list toggle row
            HStack {
                MenuItemIcon(systemName: "rectangle.on.rectangle")
                Text("显示模式")
                    .font(.body)
                if let mode = display.currentDisplayMode {
                    Text(mode.resolutionString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if display.currentDisplayMode?.isHiDPI == true {
                    Text("HiDPI")
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.12))
                        .cornerRadius(3)
                }
                Spacer()
                Image(systemName: showModeList ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .animation(.easeInOut(duration: 0.18), value: showModeList)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showModeList.toggle() } }

            if showModeList {
                DisplayModeListView(display: display)
                    .padding(.leading, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Screen rotation section (Phase 4)
            HStack {
                MenuItemIcon(systemName: "rotate.right")
                Text("屏幕旋转")
                    .font(.body)
                Spacer()
                Text("\(Int(display.rotation))°")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Image(systemName: showRotation ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .animation(.easeInOut(duration: 0.18), value: showRotation)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showRotation.toggle() } }

            if showRotation {
                RotationView(display: display)
                    .padding(.leading, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Color profile section (Phase 5)
            HStack {
                MenuItemIcon(systemName: "paintpalette.fill", color: .purple)
                Text("颜色描述文件")
                    .font(.body)
                Spacer()
                Text(ColorProfileService.shared.currentColorSpaceName(for: display.displayID))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Image(systemName: showColorProfile ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .animation(.easeInOut(duration: 0.18), value: showColorProfile)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showColorProfile.toggle() } }

            if showColorProfile {
                ColorProfileView(display: display)
                    .padding(.leading, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Color mode section (Phase 5)
            HStack {
                MenuItemIcon(systemName: "wand.and.rays", color: .indigo)
                Text("色彩模式")
                    .font(.body)
                Spacer()
                Text(ColorProfileService.shared.colorModeDescription(for: display.displayID))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Image(systemName: showColorMode ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .animation(.easeInOut(duration: 0.18), value: showColorMode)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showColorMode.toggle() } }

            if showColorMode {
                ColorModeView(display: display)
                    .padding(.leading, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Image adjustment section (Phase 6)
            HStack {
                MenuItemIcon(systemName: "slider.horizontal.3")
                Text("图像调整")
                    .font(.body)
                Spacer()
                Image(systemName: showImageAdjustment ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .animation(.easeInOut(duration: 0.18), value: showImageAdjustment)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showImageAdjustment.toggle() } }

            if showImageAdjustment {
                ImageAdjustmentView(display: display)
                    .padding(.leading, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // --- Phase 7: 显示器高级管理 ---

            // Set as main display (Phase 7)
            MainDisplayView(display: display)

            // Notch management (Phase 7, built-in with notch only)
            NotchView(display: display)

            // Integrated DDC control (Phase 7)
            HStack {
                MenuItemIcon(systemName: "cpu", color: .teal)
                Text("集成控制")
                    .font(.body)
                Spacer()
                Image(systemName: showIntegratedControl ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .animation(.easeInOut(duration: 0.18), value: showIntegratedControl)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showIntegratedControl.toggle() } }

            if showIntegratedControl {
                IntegratedControlView(display: display)
                    .padding(.leading, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Manage display settings (Phase 7)
            HStack {
                MenuItemIcon(systemName: "gearshape.fill", color: .gray)
                Text("管理显示器")
                    .font(.body)
                Spacer()
                Image(systemName: showManageDisplay ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .animation(.easeInOut(duration: 0.18), value: showManageDisplay)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showManageDisplay.toggle() } }

            if showManageDisplay {
                ManageDisplayView(display: display)
                    .padding(.leading, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Screen mirroring section (Phase 8)
            HStack {
                MenuItemIcon(systemName: "rectangle.2.swap")
                Text("屏幕镜像")
                    .font(.body)
                Spacer()
                Image(systemName: showMirror ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .animation(.easeInOut(duration: 0.18), value: showMirror)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showMirror.toggle() } }

            if showMirror {
                MirrorView(display: display)
                    .padding(.leading, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Screen streaming section (Phase 9)
            HStack {
                MenuItemIcon(systemName: "play.rectangle.fill", color: .red)
                Text("屏幕串流")
                    .font(.body)
                Spacer()
                Image(systemName: showStream ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .animation(.easeInOut(duration: 0.18), value: showStream)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showStream.toggle() } }

            if showStream {
                StreamControlView(display: display)
                    .padding(.leading, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Picture-in-Picture section (Phase 9)
            HStack {
                MenuItemIcon(systemName: "pip.fill", color: .red)
                Text("画中画")
                    .font(.body)
                Spacer()
                Image(systemName: showPiP ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .animation(.easeInOut(duration: 0.18), value: showPiP)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showPiP.toggle() } }

            if showPiP {
                PiPControlView(display: display)
                    .padding(.leading, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // HiDPI via virtual display (Phase 10, external displays only)
            if !display.isBuiltin {
                HiDPIVirtualRowView(display: display)
            }

            Divider()
                .padding(.vertical, 2)

            // Config protection section (Phase 11)
            HStack {
                MenuItemIcon(systemName: "lock.shield.fill", color: .green)
                Text("配置保护")
                    .font(.body)
                Spacer()
                Image(systemName: showConfigProtection ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .animation(.easeInOut(duration: 0.18), value: showConfigProtection)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showConfigProtection.toggle() } }

            if showConfigProtection {
                ConfigProtectionView(display: display)
                    .environmentObject(displayManager)
                    .padding(.leading, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.leading, 32)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
}

// MARK: - HiDPI Virtual Row

/// "高分辨率 (HiDPI)" toggle row — creates a backing virtual display and mirrors this display
/// to it so macOS exposes HiDPI scaled resolutions for the external display.
struct HiDPIVirtualRowView: View {
    @ObservedObject var display: DisplayInfo
    @StateObject private var service = VirtualDisplayService.shared

    private var isEnabled: Bool {
        service.isHiDPIVirtualEnabled(for: display.displayID)
    }

    var body: some View {
        HStack {
            MenuItemIcon(systemName: "plus.circle.fill")
            Text("高分辨率 (HiDPI)")
                .font(.body)
            Spacer()
            if #available(macOS 14, *) {
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        if newValue {
                            service.enableHiDPIVirtual(
                                for: display.displayID,
                                physicalWidth: display.pixelWidth,
                                physicalHeight: display.pixelHeight
                            )
                        } else {
                            service.disableHiDPIVirtual(for: display.displayID)
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
            } else {
                Text("需要 macOS 14+")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}
