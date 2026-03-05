import SwiftUI

// MARK: - DisplayDetailView

struct DisplayDetailView: View {
    @ObservedObject var display: DisplayInfo
    @EnvironmentObject var displayManager: DisplayManager
    @State private var showModeList: Bool = false
    @State private var showColorProfile: Bool = false
    @State private var showImageAdjustment: Bool = false
    @State private var colorSpaceName: String = ""

    private func sectionKey(_ name: String) -> String {
        "fd.expanded.\(display.displayUUID).\(name)"
    }

    private func loadExpanded(_ name: String, default value: Bool) -> Bool {
        let key = sectionKey(name)
        guard UserDefaults.standard.object(forKey: key) != nil else { return value }
        return UserDefaults.standard.bool(forKey: key)
    }

    private func saveExpanded(_ name: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: sectionKey(name))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Brightness slider
            BrightnessSliderView(display: display)

            Divider().opacity(0.3).padding(.vertical, 2)

            // HiDPI toggle — before mode list (natural workflow: enable HiDPI → pick resolution)
            HiDPIRowView(display: display)

            // Display mode list toggle row
            ExpandableRow(
                icon: "rectangle.on.rectangle",
                label: "显示模式",
                subtitle: {
                    var parts: [String] = []
                    if let mode = display.currentDisplayMode {
                        parts.append(mode.resolutionString)
                    }
                    if display.currentDisplayMode?.isHiDPI == true {
                        parts.append("HiDPI")
                    }
                    return parts.joined(separator: " · ")
                }(),
                isExpanded: $showModeList
            )

            if showModeList {
                DisplayModeListView(display: display)
                    .padding(.leading, 8)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }

            Divider().opacity(0.3).padding(.vertical, 2)

            // Color profile section
            ExpandableRow(
                icon: "paintpalette.fill",
                iconColor: .purple,
                label: "颜色描述文件",
                subtitle: colorSpaceName,
                isExpanded: $showColorProfile
            )

            if showColorProfile {
                ColorProfileView(display: display)
                    .padding(.leading, 8)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }

            // Image adjustment section
            ExpandableRow(
                icon: "slider.horizontal.3",
                label: "图像调整",
                isExpanded: $showImageAdjustment
            )

            if showImageAdjustment {
                ImageAdjustmentView(display: display)
                    .padding(.leading, 8)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }

            Divider().opacity(0.3).padding(.vertical, 2)

            // Set as main display
            MainDisplayView(display: display)

            // Notch management (built-in with notch only)
            NotchView(display: display)

        }
        .padding(.leading, 32)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .onAppear {
            showModeList = loadExpanded("modeList", default: false)
            showColorProfile = loadExpanded("colorProfile", default: false)
            showImageAdjustment = loadExpanded("imageAdjust", default: false)
        }
        .onChange(of: showModeList) { _, v in saveExpanded("modeList", v) }
        .onChange(of: showColorProfile) { _, v in saveExpanded("colorProfile", v) }
        .onChange(of: showImageAdjustment) { _, v in saveExpanded("imageAdjust", v) }
        .task(id: display.displayID) {
            colorSpaceName = ""
            guard !Task.isCancelled else { return }
            colorSpaceName = ColorProfileService.shared.currentColorSpaceName(for: display.displayID)
        }
    }
}

