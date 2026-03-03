import SwiftUI

/// "画中画" section in DisplayDetailView.
/// Creates and manages a PiP floating window for a display.
@MainActor
struct PiPControlView: View {
    @ObservedObject var display: DisplayInfo

    @State private var viewModel: StreamViewModel?
    @State private var pipController: PiPWindowController?

    // PiP options state (mirrored from pipController for reactive UI)
    @State private var pipLevel: PiPWindowLevel = .floating
    @State private var showTitleBar: Bool = false
    @State private var isMovable: Bool = true
    @State private var isResizable: Bool = true
    @State private var ignoresMouse: Bool = false
    @State private var hasShadow: Bool = true
    @State private var snapsToQuarters: Bool = false
    @State private var alphaValue: Double = 1.0
    @State private var showCursor: Bool = true
    @State private var flipH: Bool = false
    @State private var flipV: Bool = false
    @State private var rotation: Int = 0
    @State private var filterName: String = "none"

    private var isActive: Bool { pipController?.isVisible == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Enable / Disable PiP
            HStack {
                Button(action: togglePiP) {
                    HStack(spacing: 6) {
                        Image(systemName: isActive ? "pip.exit" : "pip.enter")
                            .foregroundColor(isActive ? .red : .blue)
                        Text(isActive ? "关闭画中画" : "开启画中画")
                            .font(.body)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                Spacer()
            }

            if isActive {
                Divider().padding(.vertical, 2)
                pipOptionsSection
            }
        }
    }

    // MARK: - PiP Options

    private var pipOptionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Window level
            HStack {
                Image(systemName: "square.3.layers.3d.top.filled")
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                    .padding(.leading, 12)
                Text("窗口层级")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $pipLevel) {
                    ForEach(PiPWindowLevel.allCases, id: \.rawValue) { level in
                        Text(level.localizedName).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 100)
                .padding(.trailing, 12)
                .onChange(of: pipLevel) { _, newVal in
                    pipController?.pipLevel = newVal
                }
            }
            .padding(.vertical, 5)

            // Title bar
            pipToggle("显示标题栏", systemImage: "macwindow", value: $showTitleBar) {
                pipController?.showTitleBar = showTitleBar
            }

            // Movable
            pipToggle("允许移动", systemImage: "arrow.up.and.down.and.arrow.left.and.right", value: $isMovable) {
                pipController?.isMovable = isMovable
            }

            // Resizable
            pipToggle("允许调整大小", systemImage: "arrow.up.left.and.arrow.down.right", value: $isResizable) {
                pipController?.isResizable = isResizable
            }

            // Snap to quarters
            pipToggle("吸附 25% 增量", systemImage: "rectangle.grid.2x2", value: $snapsToQuarters) {
                pipController?.snapsToQuarters = snapsToQuarters
            }

            // Mouse passthrough
            pipToggle("鼠标点击穿透", systemImage: "cursorarrow.slash", value: $ignoresMouse) {
                pipController?.ignoresMouse = ignoresMouse
            }

            // Shadow
            pipToggle("窗口阴影", systemImage: "shadow", value: $hasShadow) {
                pipController?.hasShadow = hasShadow
            }

            Divider().padding(.vertical, 2)

            // Content options
            pipToggle("显示鼠标指针", systemImage: "cursorarrow", value: $showCursor) {
                viewModel?.config.showCursor = showCursor
                viewModel?.service.restart(showCursor: showCursor)
            }

            // Flip
            HStack(spacing: 8) {
                Text("翻转")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 12)
                Spacer()
                Button(action: {
                    flipH.toggle()
                    viewModel?.config.flipH = flipH
                }) {
                    Text("水平")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(flipH ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                Button(action: {
                    flipV.toggle()
                    viewModel?.config.flipV = flipV
                }) {
                    Text("垂直")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(flipV ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
            }
            .padding(.vertical, 5)

            // Rotation
            HStack {
                Text("旋转")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 12)
                Spacer()
                ForEach([0, 90, 180, 270], id: \.self) { deg in
                    Button(action: {
                        rotation = deg
                        viewModel?.config.rotation = deg
                    }) {
                        Text("\(deg)°")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(rotation == deg ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 12)
            }
            .padding(.vertical, 5)

            // Filter
            HStack {
                Image(systemName: "camera.filters")
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                    .padding(.leading, 12)
                Text("视频滤镜")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $filterName) {
                    Text("无").tag("none")
                    Text("灰度").tag("grayscale")
                    Text("模糊").tag("blur")
                    Text("锐化").tag("sharpen")
                    Text("反色").tag("invert")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 80)
                .padding(.trailing, 12)
                .onChange(of: filterName) { _, newVal in
                    viewModel?.config.filterName = newVal
                }
            }
            .padding(.vertical, 5)

            // Transparency
            HStack {
                Text("透明度")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 12)
                Slider(value: $alphaValue, in: 0.1...1.0)
                    .controlSize(.small)
                    .onChange(of: alphaValue) { _, newVal in
                        viewModel?.config.alphaValue = newVal
                        pipController?.updateAlpha(newVal)
                    }
                Text(String(format: "%.0f%%", alphaValue * 100))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .trailing)
                    .padding(.trailing, 12)
            }
            .padding(.vertical, 3)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func pipToggle(_ label: String, systemImage: String, value: Binding<Bool>, onchange: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundColor(.secondary)
                .frame(width: 16)
                .padding(.leading, 12)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Toggle("", isOn: value)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .padding(.trailing, 12)
                .onChange(of: value.wrappedValue) { _, _ in onchange() }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func togglePiP() {
        if pipController?.isVisible == true {
            // Close PiP
            pipController?.close()
            viewModel?.stopCapture()
            pipController = nil
            viewModel = nil
        } else {
            // Open PiP
            let vm = StreamViewModel(displayID: display.displayID)
            vm.config.showCursor = showCursor
            vm.config.flipH = flipH
            vm.config.flipV = flipV
            vm.config.rotation = rotation
            vm.config.filterName = filterName
            vm.config.alphaValue = alphaValue
            viewModel = vm

            let pip = PiPWindowController(viewModel: vm)
            pip.pipLevel = pipLevel
            pip.showTitleBar = showTitleBar
            pip.isMovable = isMovable
            pip.isResizable = isResizable
            pip.ignoresMouse = ignoresMouse
            pip.hasShadow = hasShadow
            pip.snapsToQuarters = snapsToQuarters
            pipController = pip

            vm.startCapture()
            pip.show()
        }
    }
}
