import Foundation
import CoreGraphics

enum DisplayPowerMode: UInt16, CaseIterable, Sendable {
    case on = 0x01
    case standby = 0x02
    case suspend = 0x03
    case off = 0x04
    case hardOff = 0x05

    init?(rawDDCValue: UInt16) {
        self.init(rawValue: rawDDCValue)
    }

    var title: String {
        switch self {
        case .on: return "开机"
        case .standby: return "待机"
        case .suspend: return "挂起"
        case .off: return "关闭"
        case .hardOff: return "硬件关机"
        }
    }
}

enum DisplayPowerCommand: Equatable, Identifiable, Sendable {
    case sleep
    case wake
    case hardOff

    var id: String {
        switch self {
        case .sleep: return "sleep"
        case .wake: return "wake"
        case .hardOff: return "hardOff"
        }
    }

    var mode: DisplayPowerMode {
        switch self {
        case .sleep: return .standby
        case .wake: return .on
        case .hardOff: return .hardOff
        }
    }

    var title: String {
        switch self {
        case .sleep: return "睡眠显示器"
        case .wake: return "尝试唤醒"
        case .hardOff: return "硬件关机"
        }
    }
}

enum DisplayPowerStatusSource: Equatable, Sendable {
    case hardwareRead
    case hardwareReadUnreliable
    case localCommand
    case localCommandReadUnreliable
}

struct DisplayPowerStatus: Equatable, Sendable {
    let mode: DisplayPowerMode?
    let rawValue: UInt16?
    let source: DisplayPowerStatusSource

    init(
        mode: DisplayPowerMode?,
        rawValue: UInt16?,
        source: DisplayPowerStatusSource = .hardwareRead
    ) {
        self.mode = mode
        self.rawValue = rawValue
        self.source = source
    }

    var title: String {
        guard let rawValue else { return "未知" }
        if source == .localCommandReadUnreliable {
            switch mode {
            case .standby: return "疑似待机"
            case .suspend: return "疑似挂起"
            case .off: return "疑似关闭"
            case .hardOff: return "疑似硬件关机"
            case .on, nil: break
            }
        }
        if source == .hardwareReadUnreliable, mode == .on {
            return "开机（读值不可靠）"
        }
        if let mode {
            return mode.title
        }
        return "未知 0x\(String(rawValue, radix: 16, uppercase: true))"
    }
}

enum PowerDiagnostics {
    private static let queue = DispatchQueue(label: "com.freedisplay.power-diagnostics", qos: .utility)

    static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"

        queue.async {
            let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Logs", isDirectory: true)
                .appendingPathComponent("FreeDisplay", isDirectory: true)
            let logURL = logsDirectory.appendingPathComponent("power.log")

            try? FileManager.default.createDirectory(
                at: logsDirectory,
                withIntermediateDirectories: true
            )

            guard let data = line.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: logURL.path),
               let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: logURL)
            }
        }
    }
}

@MainActor
final class DisplayPowerService: ObservableObject, @unchecked Sendable {
    static let shared = DisplayPowerService()

    @Published private var stateRevision = 0

    private struct LocalPowerRecord {
        let mode: DisplayPowerMode
        let date: Date
    }

    private var localPowerRecords: [String: LocalPowerRecord] = [:]

    private init() {}

    private func physicalIdentity(for display: DisplayInfo) -> String {
        "v\(display.vendorNumber)-m\(display.modelNumber)-s\(display.serialNumber)"
    }

    private func identityKeys(for display: DisplayInfo) -> [String] {
        [
            "uuid.\(display.displayUUID)",
            "physical.\(physicalIdentity(for: display))"
        ]
    }

    private func d6ReadUnreliableKeys(for display: DisplayInfo) -> [String] {
        [
            "fd.power.d6ReadUnreliable.\(display.displayUUID)",
            "fd.power.d6ReadUnreliable.physical.\(physicalIdentity(for: display))"
        ]
    }

    private func topologyPowerPreferredKeys(for display: DisplayInfo) -> [String] {
        [
            "fd.power.topologyPreferred.\(display.displayUUID)",
            "fd.power.topologyPreferred.physical.\(physicalIdentity(for: display))"
        ]
    }

    private func localPowerRecord(for display: DisplayInfo) -> LocalPowerRecord? {
        for key in identityKeys(for: display) {
            if let record = localPowerRecords[key] {
                return record
            }
        }
        return nil
    }

    func hasLocalPowerDownRequest(for display: DisplayInfo) -> Bool {
        guard let record = localPowerRecord(for: display) else { return false }
        return record.mode != .on
    }

    func localPowerDownStatus(for display: DisplayInfo) -> DisplayPowerStatus? {
        guard let record = localPowerRecord(for: display),
              record.mode != .on else {
            return nil
        }
        return DisplayPowerStatus(
            mode: record.mode,
            rawValue: record.mode.rawValue,
            source: isD6ReadUnreliable(for: display) ? .localCommandReadUnreliable : .localCommand
        )
    }

    func isD6ReadUnreliable(for display: DisplayInfo) -> Bool {
        let defaults = UserDefaults.standard
        return d6ReadUnreliableKeys(for: display).contains { defaults.bool(forKey: $0) }
    }

    func prefersTopologyPowerControl(for display: DisplayInfo) -> Bool {
        let defaults = UserDefaults.standard
        return isKnownDDCWakeUnsafeDisplay(display)
            || topologyPowerPreferredKeys(for: display).contains { defaults.bool(forKey: $0) }
    }

    func markTopologyPowerPreferred(for display: DisplayInfo, reason: String) {
        let defaults = UserDefaults.standard
        let keys = topologyPowerPreferredKeys(for: display)
        let wasMarked = keys.contains { defaults.bool(forKey: $0) }
        keys.forEach { defaults.set(true, forKey: $0) }
        if !wasMarked {
            PowerDiagnostics.log("power-topology-preferred mark name=\"\(display.name)\" displayID=\(display.displayID) reason=\(reason)")
        }
        stateRevision &+= 1
    }

    func markD6ReadUnreliable(for display: DisplayInfo, reason: String) {
        let defaults = UserDefaults.standard
        let keys = d6ReadUnreliableKeys(for: display)
        let wasMarked = keys.contains { defaults.bool(forKey: $0) }
        keys.forEach { defaults.set(true, forKey: $0) }
        if !wasMarked {
            PowerDiagnostics.log("power-d6-read-unreliable mark name=\"\(display.name)\" displayID=\(display.displayID) reason=\(reason)")
        }
        stateRevision &+= 1
    }

    func clearLocalPowerDownState(for display: DisplayInfo) {
        var didRemove = false
        for key in identityKeys(for: display) {
            if localPowerRecords.removeValue(forKey: key) != nil {
                didRemove = true
            }
        }
        if didRemove {
            PowerDiagnostics.log("power-local-state clear name=\"\(display.name)\" displayID=\(display.displayID)")
            stateRevision &+= 1
        }
    }

    private func recordLocalPowerMode(_ mode: DisplayPowerMode, for display: DisplayInfo) {
        if mode == .on {
            clearLocalPowerDownState(for: display)
            return
        }

        let record = LocalPowerRecord(mode: mode, date: Date())
        identityKeys(for: display).forEach {
            localPowerRecords[$0] = record
        }
        PowerDiagnostics.log("power-local-state record name=\"\(display.name)\" displayID=\(display.displayID) mode=\(mode.title)")
        stateRevision &+= 1
    }

    private func reconcileHardwareStatus(
        _ status: DisplayPowerStatus,
        maxValue: UInt16,
        for display: DisplayInfo
    ) -> DisplayPowerStatus {
        if maxValue == 0xFF {
            markD6ReadUnreliable(for: display, reason: "power-vcp-max-0xFF")
        }

        if let localStatus = localPowerDownStatus(for: display) {
            if status.mode == .on {
                markD6ReadUnreliable(
                    for: display,
                    reason: "local-power-down-read-back-on"
                )
                return DisplayPowerStatus(
                    mode: localStatus.mode,
                    rawValue: localStatus.rawValue,
                    source: .localCommandReadUnreliable
                )
            }
            return localStatus
        }

        if isD6ReadUnreliable(for: display), status.mode == .on {
            return DisplayPowerStatus(
                mode: status.mode,
                rawValue: status.rawValue,
                source: .hardwareReadUnreliable
            )
        }

        return status
    }

    private func isKnownDDCWakeUnsafeDisplay(_ display: DisplayInfo) -> Bool {
        let normalizedName = display.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        return normalizedName == "mimonitor"
            && display.vendorNumber == 25_001
            && display.modelNumber == 10_164
    }

    func currentStatus(for displayID: CGDirectDisplayID, forceDDCProbe: Bool = false) async -> DisplayPowerStatus? {
        (await readHardwareStatus(for: displayID, forceDDCProbe: forceDDCProbe))?.status
    }

    func currentStatus(for display: DisplayInfo, forceDDCProbe: Bool = false) async -> DisplayPowerStatus? {
        guard let hardware = await readHardwareStatus(
            for: display.displayID,
            forceDDCProbe: forceDDCProbe
        ) else {
            if let localStatus = localPowerDownStatus(for: display) {
                PowerDiagnostics.log("power-status local-fallback name=\"\(display.name)\" displayID=\(display.displayID) mode=\(localStatus.title)")
                return localStatus
            }
            return nil
        }

        return reconcileHardwareStatus(
            hardware.status,
            maxValue: hardware.maxValue,
            for: display
        )
    }

    private func readHardwareStatus(
        for displayID: CGDirectDisplayID,
        forceDDCProbe: Bool = false
    ) async -> (status: DisplayPowerStatus, maxValue: UInt16)? {
        if forceDDCProbe {
            PowerDiagnostics.log("power-status probe-only displayID=\(displayID) action=read-brightness-vcp-0x10 skip=power-vcp-0xD6")
            _ = await BrightnessService.shared.ensureDDCAvailability(
                for: displayID,
                forceProbe: true
            )
            return nil
        }

        guard await BrightnessService.shared.ensureDDCAvailability(
            for: displayID,
            forceProbe: forceDDCProbe
        ) else {
            PowerDiagnostics.log("power-status unavailable displayID=\(displayID) reason=ddc-brightness-probe-failed")
            return nil
        }

        PowerDiagnostics.log("power-status read displayID=\(displayID) vcp=0xD6")
        return await withCheckedContinuation { (continuation: CheckedContinuation<(status: DisplayPowerStatus, maxValue: UInt16)?, Never>) in
            DDCService.shared.readAsync(
                displayID: displayID,
                command: DDCService.powerVCP
            ) { result in
                guard let result else {
                    PowerDiagnostics.log("power-status read-failed displayID=\(displayID) vcp=0xD6")
                    continuation.resume(returning: nil)
                    return
                }
                let mode = DisplayPowerMode(rawDDCValue: result.current)
                PowerDiagnostics.log("power-status read-ok displayID=\(displayID) vcp=0xD6 current=0x\(String(result.current, radix: 16, uppercase: true)) max=0x\(String(result.max, radix: 16, uppercase: true))")
                continuation.resume(returning: (
                    status: DisplayPowerStatus(mode: mode, rawValue: result.current),
                    maxValue: result.max
                ))
            }
        }
    }

    func setPowerMode(_ mode: DisplayPowerMode, for displayID: CGDirectDisplayID) async -> Bool {
        guard !BrightnessService.shared.isHardwareDDCDisabled(for: displayID) else {
            PowerDiagnostics.log("power-command skipped displayID=\(displayID) reason=ddc-disabled")
            return false
        }

        DDCService.shared.clearCache(for: displayID)
        PowerDiagnostics.log("power-command send displayID=\(displayID) vcp=0xD6 value=0x\(String(mode.rawValue, radix: 16, uppercase: true)) title=\(mode.title)")
        return await withCheckedContinuation { continuation in
            DDCService.shared.writeAsync(
                displayID: displayID,
                command: DDCService.powerVCP,
                value: mode.rawValue
            ) { success in
                PowerDiagnostics.log("power-command result displayID=\(displayID) vcp=0xD6 value=0x\(String(mode.rawValue, radix: 16, uppercase: true)) success=\(success)")
                continuation.resume(returning: success)
            }
        }
    }

    func setPowerMode(_ mode: DisplayPowerMode, for display: DisplayInfo) async -> Bool {
        let success = await setPowerMode(mode, for: display.displayID)
        if success {
            recordLocalPowerMode(mode, for: display)
        }
        return success
    }

    func reinitializeDisplayLink(for displayID: CGDirectDisplayID) async -> Bool {
        PowerDiagnostics.log("display-link reinitialize-start displayID=\(displayID)")
        DDCService.shared.clearCache(for: displayID)
        BrightnessService.shared.invalidateDDCState(for: displayID)

        guard CGDisplayIsOnline(displayID) != 0,
              CGDisplayIsActive(displayID) != 0,
              let mode = CGDisplayCopyDisplayMode(displayID) else {
            PowerDiagnostics.log("display-link reinitialize-failed displayID=\(displayID) reason=display-not-active")
            return false
        }

        let success = await ResolutionService.applyModeSync(mode, on: displayID)

        try? await Task.sleep(nanoseconds: 500_000_000)
        DDCService.shared.clearCache(for: displayID)
        BrightnessService.shared.invalidateDDCState(for: displayID)

        PowerDiagnostics.log("display-link reinitialize-result displayID=\(displayID) success=\(success)")
        return success
    }
}
