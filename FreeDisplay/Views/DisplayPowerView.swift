import SwiftUI

struct DisplayPowerView: View {
    @ObservedObject var display: DisplayInfo
    @EnvironmentObject var displayManager: DisplayManager
    @ObservedObject private var powerService = DisplayPowerService.shared
    @ObservedObject private var ddcService = DDCService.shared
    @ObservedObject private var connectionService = DisplayConnectionService.shared
    @State private var status: DisplayPowerStatus?
    @State private var didLoadStatus = false
    @State private var isLoading = false
    @State private var pendingCommand: DisplayPowerCommand?
    @State private var errorMessage: String?
    @State private var wakeFailedAfterStandby = false
    @State private var powerVCPUnsafe = false
    @State private var didSkipPowerStatusRead = false

    private var activePhysicalDisplayCount: Int {
        displayManager.displays.filter {
            $0.isOnline
                && $0.isEnabled
                && !VirtualDisplayService.shared.isVirtualDisplay($0.displayID)
        }.count
    }

    private var statusText: String {
        if isLoading { return "处理中" }
        if usesTopologyConnection {
            return connectionService.isTopologyControlAvailable ? "拓扑控制" : "拓扑待接入"
        }
        guard let status else { return didLoadStatus ? "不可读取" : "DDC 电源" }
        return status.title
    }

    private var statusColor: Color {
        if usesTopologyConnection { return .blue }
        guard let mode = status?.mode else { return .secondary }
        switch mode {
        case .on: return .green
        case .standby, .suspend, .off: return .orange
        case .hardOff: return .red
        }
    }

    private var isDDCUnavailable: Bool {
        BrightnessService.shared.isDDCAvailable(for: display.displayID) == false
    }

    private var isPowerStatusUnreadable: Bool {
        didLoadStatus && status == nil
    }

    private var hasLocalPowerDownRequest: Bool {
        powerService.hasLocalPowerDownRequest(for: display)
    }

    private var hasD6ReadUnreliable: Bool {
        powerService.isD6ReadUnreliable(for: display)
    }

    private var hasUnsafeDDCMapping: Bool {
        isPowerStatusUnreadable && ddcService.mappingWarning != nil
    }

    private var usesTopologyConnection: Bool {
        powerVCPUnsafe
            || BrightnessService.shared.isHardwareDDCDisabled(for: display.displayID)
            || powerService.prefersTopologyPowerControl(for: display)
    }

    private var shouldUseReconnectAction: Bool {
        isPowerStatusUnreadable && !hasLocalPowerDownRequest
    }

    private var isReconnectDisabled: Bool {
        isLoading || display.isBuiltin
    }

    private var wakeFailureKey: String {
        "fd.power.wakeFailedAfterStandby.\(display.displayUUID)"
    }

    private var powerUnsafeKey: String {
        "fd.power.powerVCPUnsafe.\(display.displayUUID)"
    }

    private var physicalPowerUnsafeKey: String {
        "fd.power.powerVCPUnsafe.physical.v\(display.vendorNumber)-m\(display.modelNumber)-s\(display.serialNumber)"
    }

    private var diagnosticIdentity: String {
        "name=\"\(display.name)\" displayID=\(display.displayID) uuid=\(display.displayUUID) vendor=\(display.vendorNumber) model=\(display.modelNumber) serial=\(display.serialNumber)"
    }

    private func reloadPowerSafetyFlags() {
        _ = BrightnessService.shared.markHardwareDDCDisabledIfKnownHighRisk(display: display)

        let defaults = UserDefaults.standard
        let wakeFailed = defaults.bool(forKey: wakeFailureKey)
        if wakeFailed {
            defaults.set(true, forKey: powerUnsafeKey)
            defaults.set(true, forKey: physicalPowerUnsafeKey)
        }
        let unsafeByUUID = defaults.bool(forKey: powerUnsafeKey)
        let unsafeByPhysicalID = defaults.bool(forKey: physicalPowerUnsafeKey)
        wakeFailedAfterStandby = wakeFailed
        powerVCPUnsafe = wakeFailed || unsafeByUUID || unsafeByPhysicalID
        if powerVCPUnsafe {
            BrightnessService.shared.markHardwareDDCDisabled(
                for: display.displayID,
                reason: "power-vcp-unsafe"
            )
        }
        PowerDiagnostics.log("power-view safety \(diagnosticIdentity) wakeFailed=\(wakeFailed) unsafeUUID=\(unsafeByUUID) unsafePhysical=\(unsafeByPhysicalID)")
    }

    private func markPowerVCPUnsafe(reason: String) {
        powerVCPUnsafe = true
        UserDefaults.standard.set(true, forKey: powerUnsafeKey)
        UserDefaults.standard.set(true, forKey: physicalPowerUnsafeKey)
        BrightnessService.shared.markHardwareDDCDisabled(
            for: display.displayID,
            reason: reason
        )
        PowerDiagnostics.log("power-view mark-unsafe \(diagnosticIdentity) reason=\(reason)")
    }

    private func isActionDisabled(_ command: DisplayPowerCommand) -> Bool {
        if isLoading { return true }
        if isDDCUnavailable && !(command == .wake && hasLocalPowerDownRequest) { return true }
        if hasUnsafeDDCMapping { return true }
        if powerVCPUnsafe { return true }
        if command == .wake {
            if hasLocalPowerDownRequest { return false }
            guard let mode = status?.mode else {
                return true
            }
            return mode == .on
        }
        if command == .sleep {
            if wakeFailedAfterStandby { return true }
            if hasLocalPowerDownRequest { return true }
            return status?.mode != .on
        }
        if command == .hardOff {
            if hasD6ReadUnreliable { return true }
            return status?.mode != .on
        }
        return isPowerStatusUnreadable
    }

    private var automaticMessage: String? {
        guard errorMessage == nil else { return nil }
        if wakeFailedAfterStandby {
            return "这台显示器待机后没有响应软件唤醒，已禁用睡眠以避免再次进入不可恢复状态。"
        }
        if usesTopologyConnection {
            if connectionService.isTopologyControlAvailable {
                if powerService.prefersTopologyPowerControl(for: display) {
                    return "这台显示器的 DDC 待机可以生效，但 DDC 唤醒不能可靠恢复画面；FreeDisplay 已改用拓扑断开/重连，不影响亮度等普通 DDC 控制。"
                }
                return "这台显示器已切换到拓扑断开/重连模式，FreeDisplay 不会发送任何硬件 DDC 指令。"
            }
            if powerService.prefersTopologyPowerControl(for: display) {
                return "这台显示器的 DDC 唤醒不可靠；当前系统没有可用的拓扑控制符号，建议避免使用 DDC 睡眠。"
            }
            return "这台显示器的 DDC 通道已标记为高风险；现在只保留软件亮度。断开/重连的安全壳已就绪，真正控制需要下一步接入 CoreDisplay/WindowServer 私有 API。"
        }
        if hasD6ReadUnreliable {
            if hasLocalPowerDownRequest {
                return "这台显示器的 VCP 0xD6 读值不可靠；FreeDisplay 会保留本次待机后的唤醒按钮，并暂时禁用硬件关机。"
            }
            return "这台显示器的 VCP 0xD6 读值不可靠；睡眠仍可用，但硬件关机已禁用以降低恢复风险。"
        }
        if hasLocalPowerDownRequest {
            return "FreeDisplay 已记录本次电源命令；如果显示器未自动恢复，唤醒按钮会继续保留。"
        }
        if isDDCUnavailable {
            return "未检测到这台显示器的 DDC/CI 硬件通道，当前只能使用软件亮度。可以先尝试重连显示链路；若仍不可用，请检查显示器菜单里的 DDC/CI 或连接方式。"
        }
        if didLoadStatus && status == nil {
            if ddcService.mappingWarning != nil {
                return "无法可靠确认这台显示器对应的 DDC 通道，已阻止电源控制以避免误控其他显示器。"
            }
            if didSkipPowerStatusRead {
                return "刷新只重新检测了 DDC 通道，没有发送 VCP 0xD6 电源状态请求；为避免触发异常待机，睡眠、唤醒和关机会暂时禁用。"
            }
            if hasLocalPowerDownRequest {
                return "无法读取 VCP 0xD6 电源状态；已保留本次睡眠后的唤醒按钮，睡眠和关机会暂时禁用。"
            }
            return "无法读取 VCP 0xD6 电源状态；请先尝试重连显示链路，DDC 睡眠、唤醒和关机会暂时禁用。"
        }
        return nil
    }

    var body: some View {
        if display.isBuiltin {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    MenuItemIcon(systemName: "power.circle.fill", color: .red)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("显示器电源")
                            .font(.body)
                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(statusColor)
                    }

                    Spacer()

                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 18, height: 18)
                    } else {
                        Button {
                            refreshStatus()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(usesTopologyConnection ? "刷新显示连接状态" : "重新检测 DDC 通道")
                    }
                }

                if usesTopologyConnection {
                    HStack(spacing: 6) {
                        DisplayPowerActionButton(
                            title: "断开",
                            systemImage: "rectangle.slash",
                            tint: .indigo,
                            isDisabled: isLoading
                        ) {
                            performTopologyAction(.disconnect)
                        }

                        DisplayPowerActionButton(
                            title: "重连",
                            systemImage: "arrow.triangle.2.circlepath",
                            tint: .blue,
                            isDisabled: isLoading
                        ) {
                            performTopologyAction(.reconnect)
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        DisplayPowerActionButton(
                            title: "睡眠",
                            systemImage: "moon.zzz.fill",
                            tint: .indigo,
                            isDisabled: isActionDisabled(.sleep)
                        ) {
                            request(.sleep)
                        }

                        DisplayPowerActionButton(
                            title: shouldUseReconnectAction ? "重连" : "唤醒",
                            systemImage: shouldUseReconnectAction ? "arrow.triangle.2.circlepath" : "sun.max.fill",
                            tint: shouldUseReconnectAction ? .blue : .orange,
                            isDisabled: shouldUseReconnectAction ? isReconnectDisabled : isActionDisabled(.wake)
                        ) {
                            if shouldUseReconnectAction {
                                performReinitialize()
                            } else {
                                perform(.wake)
                            }
                        }

                        DisplayPowerActionButton(
                            title: "关机",
                            systemImage: "power",
                            tint: .red,
                            isDisabled: isActionDisabled(.hardOff)
                        ) {
                            request(.hardOff)
                        }
                    }
                }

                if let pendingCommand {
                    DisplayPowerConfirmRow(
                        command: pendingCommand,
                        message: confirmMessage(for: pendingCommand),
                        onCancel: {
                            self.pendingCommand = nil
                        },
                        onConfirm: {
                            perform(pendingCommand)
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if let errorMessage {
                    DisplayPowerMessageRow(
                        systemImage: "exclamationmark.triangle.fill",
                        message: errorMessage,
                        tint: .orange,
                        onDismiss: {
                            self.errorMessage = nil
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else if let automaticMessage {
                    DisplayPowerMessageRow(
                        systemImage: "info.circle.fill",
                        message: automaticMessage,
                        tint: .blue,
                        onDismiss: nil
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .task(id: display.displayID) {
                reloadPowerSafetyFlags()
                await loadStatus()
            }
            .onChange(of: displayManager.displayConfigurationRevision) { _, _ in
                pendingCommand = nil
                errorMessage = nil
                status = nil
                didLoadStatus = false
                didSkipPowerStatusRead = false
                reloadPowerSafetyFlags()
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    await loadStatus()
                }
            }
        }
    }

    private func request(_ command: DisplayPowerCommand) {
        guard !isDDCUnavailable else {
            pendingCommand = nil
            errorMessage = "这台显示器当前没有可用的 DDC/CI 硬件通道，无法发送睡眠或关机命令。"
            return
        }
        guard !isPowerStatusUnreadable else {
            pendingCommand = nil
            errorMessage = "无法读取这台显示器的电源状态。为避免误操作，FreeDisplay 已暂时阻止睡眠和关机。"
            return
        }
        guard !(command == .sleep && wakeFailedAfterStandby) else {
            pendingCommand = nil
            errorMessage = "这台显示器待机后无法通过 FreeDisplay 唤醒，已阻止再次发送睡眠命令。"
            return
        }
        guard command != .sleep || status?.mode == .on else {
            pendingCommand = nil
            errorMessage = "这台显示器当前不是开机状态，FreeDisplay 已阻止重复发送睡眠命令。"
            return
        }
        guard command != .hardOff || status?.mode == .on else {
            pendingCommand = nil
            errorMessage = "这台显示器当前不是开机状态，FreeDisplay 已阻止发送硬件关机命令。"
            return
        }
        guard command != .hardOff || !hasD6ReadUnreliable else {
            pendingCommand = nil
            errorMessage = "这台显示器的 DDC 电源读值不可靠，FreeDisplay 已禁用硬件关机以降低无法恢复的风险。"
            return
        }
        guard !powerVCPUnsafe else {
            pendingCommand = nil
            errorMessage = "这台显示器的 DDC 电源控制已标记为高风险，FreeDisplay 已阻止这次操作。"
            return
        }
        guard activePhysicalDisplayCount > 1 else {
            pendingCommand = nil
            errorMessage = "为避免关掉最后一个可用显示器，FreeDisplay 已阻止这次操作。"
            return
        }
        errorMessage = nil
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            pendingCommand = command
        }
    }

    private func perform(_ command: DisplayPowerCommand) {
        guard !isLoading else { return }
        guard !isDDCUnavailable || (command == .wake && hasLocalPowerDownRequest) else {
            pendingCommand = nil
            errorMessage = "这台显示器当前没有可用的 DDC/CI 硬件通道，无法发送电源命令。"
            return
        }
        guard !(command != .wake && isPowerStatusUnreadable) else {
            pendingCommand = nil
            errorMessage = "无法读取这台显示器的电源状态。为避免误操作，FreeDisplay 已暂时阻止睡眠和关机。"
            return
        }
        guard command == .wake || status?.mode == .on else {
            pendingCommand = nil
            errorMessage = "这台显示器当前不是开机状态，FreeDisplay 已阻止发送新的关机/睡眠命令。"
            return
        }
        guard command != .hardOff || !hasD6ReadUnreliable else {
            pendingCommand = nil
            errorMessage = "这台显示器的 DDC 电源读值不可靠，FreeDisplay 已禁用硬件关机以降低无法恢复的风险。"
            return
        }
        guard !hasUnsafeDDCMapping else {
            pendingCommand = nil
            errorMessage = "这台显示器的 DDC 通道没有通过身份校验，FreeDisplay 已阻止发送命令。"
            return
        }
        guard !powerVCPUnsafe else {
            pendingCommand = nil
            errorMessage = "这台显示器的 DDC 电源控制已标记为高风险，FreeDisplay 已阻止发送命令。"
            return
        }
        pendingCommand = nil
        errorMessage = nil
        isLoading = true

        Task {
            let success = await powerService.setPowerMode(command.mode, for: display)
            await MainActor.run {
                isLoading = false
                if success {
                    didLoadStatus = true
                    didSkipPowerStatusRead = false
                    status = DisplayPowerStatus(
                        mode: command.mode,
                        rawValue: command.mode.rawValue,
                        source: .localCommand
                    )
                    if command == .wake {
                        wakeFailedAfterStandby = false
                        UserDefaults.standard.removeObject(forKey: wakeFailureKey)
                    }
                } else {
                    if command == .wake && (isPowerStatusUnreadable || hasLocalPowerDownRequest) {
                        wakeFailedAfterStandby = true
                        UserDefaults.standard.set(true, forKey: wakeFailureKey)
                        markPowerVCPUnsafe(reason: "wake-failed-after-standby")
                    }
                    errorMessage = errorText(forFailedCommand: command)
                }
            }
        }
    }

    private func refreshStatus() {
        guard !isLoading else { return }
        PowerDiagnostics.log("power-refresh click \(diagnosticIdentity) powerUnsafe=\(powerVCPUnsafe) wakeFailed=\(wakeFailedAfterStandby)")
        if usesTopologyConnection {
            refreshTopologyStatus()
            return
        }
        DDCService.shared.clearCache(for: display.displayID)
        errorMessage = nil
        Task { await loadStatus(forceDDCProbe: true) }
    }

    private func loadStatus(forceDDCProbe: Bool = false) async {
        let preservedStatus = await MainActor.run { () -> DisplayPowerStatus? in
            isLoading = true
            return status
        }

        if usesTopologyConnection {
            PowerDiagnostics.log("topology-status skipped-ddc \(diagnosticIdentity)")
            await MainActor.run {
                status = nil
                didSkipPowerStatusRead = true
                didLoadStatus = true
                isLoading = false
            }
            return
        }

        if forceDDCProbe {
            let available = await BrightnessService.shared.ensureDDCAvailability(
                for: display.displayID,
                forceProbe: true
            )
            PowerDiagnostics.log("power-refresh probe-result \(diagnosticIdentity) ddcAvailable=\(available) skippedPowerVCP=0xD6")
            await MainActor.run {
                if let localStatus = powerService.localPowerDownStatus(for: display) {
                    status = localStatus
                } else if !available {
                    status = nil
                } else {
                    status = preservedStatus
                }
                didSkipPowerStatusRead = true
                didLoadStatus = true
                isLoading = false
            }
            return
        }

        if powerVCPUnsafe {
            PowerDiagnostics.log("power-status skipped-unsafe \(diagnosticIdentity)")
            await MainActor.run {
                status = nil
                didSkipPowerStatusRead = true
                didLoadStatus = true
                isLoading = false
            }
            return
        }

        let newStatus = await powerService.currentStatus(
            for: display,
            forceDDCProbe: forceDDCProbe
        )
        await MainActor.run {
            status = newStatus
            didSkipPowerStatusRead = false
            didLoadStatus = true
            isLoading = false
        }
    }

    private func refreshTopologyStatus() {
        pendingCommand = nil
        errorMessage = nil
        isLoading = true
        PowerDiagnostics.log("topology-refresh click \(diagnosticIdentity)")

        Task {
            await MainActor.run {
                displayManager.refreshDisplays(invalidateTransportCaches: false)
                status = nil
                didSkipPowerStatusRead = true
                didLoadStatus = true
                isLoading = false
            }
        }
    }

    private func performTopologyAction(_ action: DisplayConnectionAction) {
        guard !isLoading else { return }
        pendingCommand = nil
        errorMessage = nil
        isLoading = true

        Task {
            let result: DisplayConnectionResult
            switch action {
            case .disconnect:
                result = await connectionService.requestDisconnect(
                    display: display,
                    activePhysicalDisplayCount: activePhysicalDisplayCount
                )
            case .reconnect:
                result = await connectionService.requestReconnect(
                    display: display,
                    activePhysicalDisplayCount: activePhysicalDisplayCount
                )
            }

            await MainActor.run {
                if result.success {
                    if case .reconnect = action {
                        powerService.clearLocalPowerDownState(for: display)
                    }
                    displayManager.refreshDisplays(invalidateTransportCaches: true)
                } else {
                    errorMessage = result.userMessage
                }
                status = nil
                didSkipPowerStatusRead = true
                didLoadStatus = true
                isLoading = false
            }
        }
    }

    private func performReinitialize() {
        guard !isLoading else { return }
        pendingCommand = nil
        errorMessage = nil
        isLoading = true

        let displayID = display.displayID
        Task {
            let success = await powerService.reinitializeDisplayLink(for: displayID)
            await MainActor.run {
                displayManager.refreshDisplays(invalidateTransportCaches: true)
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            let ddcAvailable = await BrightnessService.shared.ensureDDCAvailability(
                for: displayID,
                forceProbe: true
            )

            await MainActor.run {
                status = success && ddcAvailable
                    ? DisplayPowerStatus(mode: .on, rawValue: DisplayPowerMode.on.rawValue)
                    : nil
                didSkipPowerStatusRead = true
                didLoadStatus = true
                isLoading = false
                if success && ddcAvailable {
                    powerService.clearLocalPowerDownState(for: display)
                    wakeFailedAfterStandby = false
                    UserDefaults.standard.removeObject(forKey: wakeFailureKey)
                }
                if !success {
                    errorMessage = "公开重连没有完成；如果显示器仍黑屏，请先用 BetterDisplay 的 reconnect 或实体按键恢复。"
                }
            }
        }
    }

    private func confirmMessage(for command: DisplayPowerCommand) -> String {
        switch command {
        case .sleep:
            if display.isMain {
                return "这台显示器当前是主屏。继续后会发送 DDC 待机命令，若显示器支持，屏幕会变黑。"
            }
            return "继续后会发送 DDC 待机命令；如果这台显示器不支持，命令可能不会生效。"
        case .hardOff:
            if display.isMain {
                return "这台显示器当前是主屏。硬件关机后，部分显示器只能通过实体按键重新打开。"
            }
            return "部分显示器在硬件关机后只能通过实体按键重新打开。"
        case .wake:
            return ""
        }
    }

    private func errorText(forFailedCommand command: DisplayPowerCommand) -> String {
        if command == .wake {
            return "显示器处于待机，但没有响应软件唤醒；这台显示器可能需要实体电源键恢复。"
        }
        return "显示器没有响应 DDC 电源命令，可能是不支持 VCP 0xD6，或当前连接链路不允许 DDC 写入。"
    }
}

private struct DisplayPowerConfirmRow: View {
    let command: DisplayPowerCommand
    let message: String
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @State private var cancelHovered = false
    @State private var confirmHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: command == .hardOff ? "power" : "moon.zzz.fill")
                    .font(.caption)
                    .foregroundColor(command == .hardOff ? .red : .indigo)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text(command.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
            }

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(action: onCancel) {
                    Text("取消")
                        .font(.caption)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(cancelHovered ? 0.18 : 0.12))
                        )
                }
                .buttonStyle(.plain)
                .onHover { cancelHovered = $0 }

                Button(action: onConfirm) {
                    Text("继续")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill((command == .hardOff ? Color.red : Color.indigo).opacity(confirmHovered ? 0.9 : 0.78))
                        )
                }
                .buttonStyle(.plain)
                .onHover { confirmHovered = $0 }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke((command == .hardOff ? Color.red : Color.indigo).opacity(0.22), lineWidth: 1)
        )
    }
}

private struct DisplayPowerMessageRow: View {
    let systemImage: String
    let message: String
    let tint: Color
    let onDismiss: (() -> Void)?
    @State private var closeHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundColor(tint)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundColor(closeHovered ? .primary : .secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { closeHovered = $0 }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.opacity(0.08))
        )
    }
}

private struct DisplayPowerActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isDisabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundColor(isDisabled ? .secondary : tint)
            .frame(maxWidth: .infinity, minHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(tint.opacity(isHovered && !isDisabled ? 0.14 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(tint.opacity(isDisabled ? 0.1 : 0.2), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .help(title)
    }
}
