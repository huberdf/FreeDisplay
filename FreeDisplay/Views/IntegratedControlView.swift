import SwiftUI

/// Expandable "集成控制" section: reads all common DDC VCP codes from the display
/// and shows the values. Only meaningful for external (DDC-capable) displays.
struct IntegratedControlView: View {
    @ObservedObject var display: DisplayInfo
    @State private var isReading: Bool = false

    private let vcpNames: [UInt8: String] = [
        0x10: "亮度",
        0x12: "对比度",
        0x14: "色温预设",
        0x16: "红色增益",
        0x18: "绿色增益",
        0x1A: "蓝色增益",
        0x60: "输入源",
        0x62: "音量",
        0x87: "色彩饱和度",
        0xD6: "电源模式",
        0xDC: "显示模式"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Read button
            HStack {
                Button(action: readFromDevice) {
                    HStack(spacing: 6) {
                        if isReading {
                            ProgressView()
                                .scaleEffect(0.65)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .frame(width: 14, height: 14)
                        }
                        Text("从设备读取并更新")
                    }
                }
                .disabled(display.isBuiltin || isReading)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)

            // DDC values table
            if !display.ddcValues.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(display.ddcValues.sorted(by: { $0.key < $1.key }), id: \.key) { code, value in
                        HStack {
                            Text(vcpNames[code] ?? String(format: "0x%02X", code))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .leading)
                            Text("\(value)")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 1)
                    }
                }
                .padding(.bottom, 4)
            } else if display.isBuiltin {
                Text("内建显示屏不支持 DDC 集成控制")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }

            Button("配置集成控制项...") {}
                .disabled(true)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
        }
    }

    private func readFromDevice() {
        isReading = true
        DDCService.shared.readBatchVCPCodes(displayID: display.displayID) { values in
            display.ddcValues = values
            isReading = false
        }
    }
}
