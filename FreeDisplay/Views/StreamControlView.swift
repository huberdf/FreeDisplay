import SwiftUI

/// "屏幕串流" section in DisplayDetailView.
/// Manages one StreamWindowController per display.
@MainActor
struct StreamControlView: View {
    @ObservedObject var display: DisplayInfo

    @State private var viewModel: StreamViewModel?
    @State private var windowController: StreamWindowController?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Start / Stop button
            startStopRow

            if let vm = viewModel {
                Divider().padding(.vertical, 2)
                optionsSection(vm: vm)
            }
        }
    }

    // MARK: - Start/Stop

    private var startStopRow: some View {
        HStack {
            let capturing = viewModel?.isCapturing == true
            Button(action: toggleCapture) {
                HStack(spacing: 6) {
                    Image(systemName: capturing ? "stop.circle.fill" : "play.circle.fill")
                        .foregroundColor(capturing ? .red : .green)
                    Text(capturing ? "停止串流" : "开始串流")
                        .font(.body)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            Spacer()

            if viewModel?.isCapturing == true {
                Button(action: showWindow) {
                    Image(systemName: "rectangle.on.rectangle")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .help("显示串流窗口")
            }
        }
    }

    // MARK: - Options

    @ViewBuilder
    private func optionsSection(vm: StreamViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cursor
            optionToggle("显示鼠标指针", systemImage: "cursorarrow", isOn: Binding(
                get: { vm.config.showCursor },
                set: { vm.config.showCursor = $0; vm.service.restart(showCursor: $0) }
            ))

            // Flip buttons
            HStack(spacing: 8) {
                Text("翻转")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 12)
                Spacer()
                Button(action: { vm.config.flipH.toggle() }) {
                    Text("水平")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(vm.config.flipH ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                Button(action: { vm.config.flipV.toggle() }) {
                    Text("垂直")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(vm.config.flipV ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1))
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
                    Button(action: { vm.config.rotation = deg }) {
                        Text("\(deg)°")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(vm.config.rotation == deg ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 12)
            }
            .padding(.vertical, 5)

            // Crop
            optionToggle("启用裁剪", systemImage: "crop", isOn: Binding(
                get: { vm.config.cropEnabled },
                set: { vm.config.cropEnabled = $0 }
            ))
            if vm.config.cropEnabled {
                sliderRow(label: "裁剪边距", value: Binding(
                    get: { vm.config.cropInset },
                    set: { vm.config.cropInset = $0 }
                ), range: 0...40, format: "%.0f%%")
            }

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
                Picker("", selection: Binding(
                    get: { vm.config.filterName },
                    set: { vm.config.filterName = $0 }
                )) {
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
            }
            .padding(.vertical, 5)

            // Transparency
            sliderRow(label: "透明度", value: Binding(
                get: { vm.config.alphaValue },
                set: { vm.config.alphaValue = $0; windowController?.updateAlpha($0) }
            ), range: 0.1...1.0, format: "%.0f%%", scale: 100)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func optionToggle(_ label: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundColor(.secondary)
                .frame(width: 16)
                .padding(.leading, 12)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .padding(.trailing, 12)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func sliderRow(label: String, value: Binding<Double>, range: ClosedRange<Double>, format: String, scale: Double = 1.0) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 12)
            Slider(value: value, in: range)
                .controlSize(.small)
            Text(String(format: format, value.wrappedValue * scale))
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 12)
        }
        .padding(.vertical, 3)
    }

    // MARK: - Actions

    private func toggleCapture() {
        if viewModel == nil {
            let vm = StreamViewModel(displayID: display.displayID)
            viewModel = vm
            windowController = StreamWindowController(viewModel: vm)
        }
        guard let vm = viewModel else { return }
        if vm.isCapturing {
            vm.stopCapture()
            windowController?.close()
        } else {
            vm.startCapture()
            windowController?.show()
        }
    }

    private func showWindow() {
        windowController?.show()
    }
}
