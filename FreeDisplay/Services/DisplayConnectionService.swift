import Foundation
import CoreGraphics
import Darwin

enum DisplayConnectionAction: String, Sendable {
    case disconnect
    case reconnect

    var title: String {
        switch self {
        case .disconnect: return "断开"
        case .reconnect: return "重连"
        }
    }
}

struct DisplayConnectionSnapshot: Codable, Identifiable, Sendable {
    let displayUUID: String
    let name: String
    let displayID: CGDirectDisplayID
    let vendorNumber: UInt32
    let modelNumber: UInt32
    let serialNumber: UInt32
    let isMain: Bool
    let pixelWidth: Int
    let pixelHeight: Int
    let boundsX: Double
    let boundsY: Double
    let boundsWidth: Double
    let boundsHeight: Double
    let timestamp: Date

    var id: String {
        "v\(vendorNumber)-m\(modelNumber)-s\(serialNumber)"
    }

    var resolutionText: String {
        "\(pixelWidth)x\(pixelHeight)"
    }
}

struct DisplayConnectionResult: Sendable {
    let success: Bool
    let userMessage: String
}

private enum DisplayTopologyApplyResult: Sendable {
    case applied
    case unavailable
    case timedOut
    case failed(stage: String, code: Int32)
}

private final class DisplayTopologyPrivateBridge: @unchecked Sendable {
    static let shared = DisplayTopologyPrivateBridge()

    private typealias ConfigureDisplayEnabledFn = @convention(c) (
        CGDisplayConfigRef,
        CGDirectDisplayID,
        Int32
    ) -> CGError

    private let configureDisplayEnabled: ConfigureDisplayEnabledFn?
    let symbolName: String?
    let frameworkPath: String?

    var isAvailable: Bool {
        configureDisplayEnabled != nil
    }

    private init() {
        let frameworkPaths = [
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        ]
        let symbolNames = [
            "CGSConfigureDisplayEnabled",
            "SLSConfigureDisplayEnabled"
        ]

        var loadedFunction: ConfigureDisplayEnabledFn?
        var loadedSymbolName: String?
        var loadedFrameworkPath: String?

        for path in frameworkPaths {
            guard let handle = dlopen(path, RTLD_LAZY) else { continue }
            for symbolName in symbolNames {
                guard let symbol = dlsym(handle, symbolName) else { continue }
                loadedFunction = unsafeBitCast(symbol, to: ConfigureDisplayEnabledFn.self)
                loadedSymbolName = symbolName
                loadedFrameworkPath = path
                break
            }
            if loadedFunction != nil { break }
        }

        configureDisplayEnabled = loadedFunction
        symbolName = loadedSymbolName
        frameworkPath = loadedFrameworkPath
    }

    func setDisplay(_ displayID: CGDirectDisplayID, enabled: Bool) async -> DisplayTopologyApplyResult {
        guard let configureDisplayEnabled else {
            return .unavailable
        }

        let enabledFlag: Int32 = enabled ? 1 : 0
        return await CGHelpers.runWithTimeout(seconds: 8, fallback: .timedOut) {
            var config: CGDisplayConfigRef?
            let begin = CGBeginDisplayConfiguration(&config)
            guard begin == .success, let cfg = config else {
                return .failed(stage: "begin", code: Int32(begin.rawValue))
            }

            let configure = configureDisplayEnabled(cfg, displayID, enabledFlag)
            guard configure == .success else {
                CGCancelDisplayConfiguration(cfg)
                return .failed(stage: "configure", code: Int32(configure.rawValue))
            }

            let complete = CGCompleteDisplayConfiguration(cfg, .forSession)
            guard complete == .success else {
                CGCancelDisplayConfiguration(cfg)
                return .failed(stage: "complete", code: Int32(complete.rawValue))
            }

            return .applied
        }
    }
}

@MainActor
final class DisplayConnectionService: ObservableObject, @unchecked Sendable {
    static let shared = DisplayConnectionService()

    private let topologyBridge = DisplayTopologyPrivateBridge.shared

    var isTopologyControlAvailable: Bool {
        topologyBridge.isAvailable
    }

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func remember(display: DisplayInfo) {
        guard !display.isBuiltin, display.isOnline, display.isEnabled else { return }
        save(snapshot: snapshot(for: display), for: display)
    }

    func snapshot(for display: DisplayInfo) -> DisplayConnectionSnapshot {
        DisplayConnectionSnapshot(
            displayUUID: display.displayUUID,
            name: display.name,
            displayID: display.displayID,
            vendorNumber: display.vendorNumber,
            modelNumber: display.modelNumber,
            serialNumber: display.serialNumber,
            isMain: display.isMain,
            pixelWidth: display.pixelWidth,
            pixelHeight: display.pixelHeight,
            boundsX: display.bounds.origin.x,
            boundsY: display.bounds.origin.y,
            boundsWidth: display.bounds.size.width,
            boundsHeight: display.bounds.size.height,
            timestamp: Date()
        )
    }

    func savedSnapshot(for display: DisplayInfo) -> DisplayConnectionSnapshot? {
        let defaults = UserDefaults.standard
        let keys = [
            snapshotKey(for: display),
            physicalSnapshotKey(for: display)
        ]
        for key in keys {
            guard let data = defaults.data(forKey: key),
                  let snapshot = try? decoder.decode(DisplayConnectionSnapshot.self, from: data) else {
                continue
            }
            return snapshot
        }
        return nil
    }

    func offlineSnapshots(
        activeDisplayIDs: Set<CGDirectDisplayID>,
        activePhysicalIDs: Set<String>
    ) -> [DisplayConnectionSnapshot] {
        var latestByPhysicalID: [String: DisplayConnectionSnapshot] = [:]
        let values = UserDefaults.standard.dictionaryRepresentation()

        for (key, value) in values where key.hasPrefix("fd.displayConnection.snapshot.") {
            guard let data = value as? Data,
                  let snapshot = try? decoder.decode(DisplayConnectionSnapshot.self, from: data),
                  !activeDisplayIDs.contains(snapshot.displayID),
                  !activePhysicalIDs.contains(snapshot.id) else {
                continue
            }

            if let existing = latestByPhysicalID[snapshot.id],
               existing.timestamp >= snapshot.timestamp {
                continue
            }

            latestByPhysicalID[snapshot.id] = snapshot
        }

        let snapshots = latestByPhysicalID.values.sorted { $0.timestamp > $1.timestamp }
        PowerDiagnostics.log("display-connection offline-snapshots count=\(snapshots.count) ids=\(snapshots.map { "\($0.name)#\($0.displayID)#\($0.id)" }.joined(separator: ","))")
        return snapshots
    }

    func requestDisconnect(display: DisplayInfo, activePhysicalDisplayCount: Int) async -> DisplayConnectionResult {
        let snapshot = snapshot(for: display)
        save(snapshot: snapshot, for: display)
        PowerDiagnostics.log("display-connection request action=disconnect \(identity(for: display)) activePhysicalDisplayCount=\(activePhysicalDisplayCount)")

        guard !display.isBuiltin else {
            return blocked("内建显示屏不能使用拓扑断开。")
        }
        guard activePhysicalDisplayCount > 1 else {
            return blocked("为避免断开最后一个可用显示器，FreeDisplay 已阻止这次操作。")
        }
        guard isTopologyControlAvailable else {
            return blocked("安全检查和状态快照已就绪，但当前系统没有导出可用的拓扑断开私有符号。")
        }

        return await applyTopologyChange(
            displayID: display.displayID,
            action: .disconnect,
            expectedEnabled: false
        )
    }

    func requestReconnect(display: DisplayInfo, activePhysicalDisplayCount: Int? = nil) async -> DisplayConnectionResult {
        let snapshot = savedSnapshot(for: display)
        PowerDiagnostics.log("display-connection request action=reconnect \(identity(for: display)) hasSnapshot=\(snapshot != nil)")

        guard !display.isBuiltin else {
            return blocked("内建显示屏不能使用拓扑重连。")
        }
        guard snapshot != nil else {
            return blocked("还没有这台显示器的连接快照；请先在显示器在线时刷新或执行一次断开准备。")
        }
        guard isTopologyControlAvailable else {
            return blocked("已找到这台显示器的连接记录，但当前系统没有导出可用的拓扑重连私有符号。")
        }

        if display.isOnline && display.isEnabled {
            if let activePhysicalDisplayCount, activePhysicalDisplayCount <= 1 {
                return blocked("为避免断开最后一个可用显示器，FreeDisplay 已阻止这次重连。")
            }

            PowerDiagnostics.log("display-connection reconnect-cycle-start \(identity(for: display))")
            let disconnect = await applyTopologyChange(
                displayID: display.displayID,
                action: .disconnect,
                expectedEnabled: false
            )
            guard disconnect.success else { return disconnect }

            try? await Task.sleep(nanoseconds: 900_000_000)
        }

        return await applyTopologyChange(
            displayID: display.displayID,
            action: .reconnect,
            expectedEnabled: true
        )
    }

    func requestReconnect(snapshot: DisplayConnectionSnapshot) async -> DisplayConnectionResult {
        PowerDiagnostics.log("display-connection request action=reconnect snapshot name=\"\(snapshot.name)\" displayID=\(snapshot.displayID) uuid=\(snapshot.displayUUID) physical=\(snapshot.id)")

        guard isTopologyControlAvailable else {
            return blocked("已找到这台显示器的离线记录，但当前系统没有导出可用的拓扑重连私有符号。")
        }

        return await applyTopologyChange(
            displayID: snapshot.displayID,
            action: .reconnect,
            expectedEnabled: true
        )
    }

    private func save(snapshot: DisplayConnectionSnapshot, for display: DisplayInfo) {
        guard let data = try? encoder.encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: snapshotKey(for: display))
        UserDefaults.standard.set(data, forKey: physicalSnapshotKey(for: display))
    }

    private func snapshotKey(for display: DisplayInfo) -> String {
        "fd.displayConnection.snapshot.\(display.displayUUID)"
    }

    private func physicalSnapshotKey(for display: DisplayInfo) -> String {
        "fd.displayConnection.snapshot.physical.v\(display.vendorNumber)-m\(display.modelNumber)-s\(display.serialNumber)"
    }

    private func applyTopologyChange(
        displayID: CGDirectDisplayID,
        action: DisplayConnectionAction,
        expectedEnabled: Bool
    ) async -> DisplayConnectionResult {
        PowerDiagnostics.log("display-connection apply-start action=\(action.rawValue) displayID=\(displayID) symbol=\(topologyBridge.symbolName ?? "nil")")

        let result = await topologyBridge.setDisplay(displayID, enabled: expectedEnabled)
        switch result {
        case .applied:
            DDCService.shared.clearAllCaches()
            BrightnessService.shared.invalidateDDCState(for: displayID)

            try? await Task.sleep(nanoseconds: 600_000_000)
            let isActive = CGDisplayIsActive(displayID) != 0
            let isOnline = CGDisplayIsOnline(displayID) != 0
            PowerDiagnostics.log("display-connection apply-ok action=\(action.rawValue) displayID=\(displayID) active=\(isActive) online=\(isOnline)")

            if !expectedEnabled && isActive {
                return DisplayConnectionResult(
                    success: false,
                    userMessage: "系统已接受断开请求，但这台显示器仍处于启用状态。请刷新后再试。"
                )
            }

            if expectedEnabled && !isActive {
                return DisplayConnectionResult(
                    success: false,
                    userMessage: "系统已接受重连请求，但这台显示器还没有恢复为可用状态。请稍等后刷新；若仍无画面，可能需要重新插拔线缆。"
                )
            }

            return DisplayConnectionResult(
                success: true,
                userMessage: action == .disconnect
                    ? "已发送拓扑断开请求，FreeDisplay 没有触碰 DDC 电源通道。"
                    : "已发送拓扑重连请求，FreeDisplay 没有触碰 DDC 电源通道。"
            )
        case .unavailable:
            return blocked("当前系统没有导出可用的拓扑控制符号，无法执行断开/重连。")
        case .timedOut:
            PowerDiagnostics.log("display-connection apply-timeout action=\(action.rawValue) displayID=\(displayID)")
            return DisplayConnectionResult(
                success: false,
                userMessage: "WindowServer 没有及时响应拓扑\(action.title)请求，FreeDisplay 已停止等待。请刷新显示器列表确认当前状态。"
            )
        case .failed(let stage, let code):
            PowerDiagnostics.log("display-connection apply-failed action=\(action.rawValue) displayID=\(displayID) stage=\(stage) code=\(code)")
            return DisplayConnectionResult(
                success: false,
                userMessage: "拓扑\(action.title)失败（\(stage)，错误码 \(code)）。"
            )
        }
    }

    private func identity(for display: DisplayInfo) -> String {
        "name=\"\(display.name)\" displayID=\(display.displayID) uuid=\(display.displayUUID) vendor=\(display.vendorNumber) model=\(display.modelNumber) serial=\(display.serialNumber)"
    }

    private func blocked(_ message: String) -> DisplayConnectionResult {
        PowerDiagnostics.log("display-connection blocked message=\"\(message)\"")
        return DisplayConnectionResult(success: false, userMessage: message)
    }
}
