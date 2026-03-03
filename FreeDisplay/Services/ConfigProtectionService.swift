import CoreGraphics
import Foundation

// MARK: - Display Config Snapshot

/// A snapshot of a single display's configuration, used for protection and restore.
struct DisplayConfig: Codable {
    let displayID: UInt32
    let displayName: String
    let width: Int
    let height: Int
    let refreshRate: Double
    let rotation: Double
    let colorProfileName: String
    let brightness: Double
    let contrast: Double
    let hdrEnabled: Bool
    let isMain: Bool
    let isMirrored: Bool
    let mirrorSource: UInt32?
    let originX: Double
    let originY: Double

    @MainActor
    init(from displayInfo: DisplayInfo) {
        displayID = displayInfo.displayID
        displayName = displayInfo.name
        width = Int(displayInfo.bounds.width)
        height = Int(displayInfo.bounds.height)
        refreshRate = displayInfo.currentDisplayMode?.refreshRate ?? 60.0
        rotation = displayInfo.rotation
        colorProfileName = ColorProfileService.shared.currentColorSpaceName(for: displayInfo.displayID)
        brightness = displayInfo.brightness
        contrast = 50.0 // placeholder – GammaService doesn't expose contrast directly yet
        hdrEnabled = false // placeholder
        isMain = displayInfo.isMain
        isMirrored = CGDisplayIsInMirrorSet(displayInfo.displayID) != 0
        mirrorSource = {
            let src = CGDisplayMirrorsDisplay(displayInfo.displayID)
            return src != kCGNullDirectDisplay ? src : nil
        }()
        originX = displayInfo.bounds.origin.x
        originY = displayInfo.bounds.origin.y
    }
}

// MARK: - Protected Items

struct ProtectedItems: Codable, Equatable {
    var resolution: Bool = false
    var refreshRate: Bool = false
    var colorMode: Bool = false
    var hdrColorMode: Bool = false
    var rotation: Bool = false
    var colorProfile: Bool = false
    var hdrColorProfile: Bool = false
    var hdrStatus: Bool = false
    var mirror: Bool = false
    var mainDisplay: Bool = false

    var anyEnabled: Bool {
        resolution || refreshRate || colorMode || hdrColorMode ||
        rotation || colorProfile || hdrColorProfile || hdrStatus ||
        mirror || mainDisplay
    }

    mutating func enableAll() {
        resolution = true; refreshRate = true; colorMode = true; hdrColorMode = true
        rotation = true; colorProfile = true; hdrColorProfile = true; hdrStatus = true
        mirror = true; mainDisplay = true
    }

    mutating func disableAll() {
        resolution = false; refreshRate = false; colorMode = false; hdrColorMode = false
        rotation = false; colorProfile = false; hdrColorProfile = false; hdrStatus = false
        mirror = false; mainDisplay = false
    }
}

// MARK: - Named Snapshot

struct NamedSnapshot: Codable, Identifiable {
    let id: UUID
    var name: String
    let configs: [DisplayConfig]
    let createdAt: Date

    init(id: UUID = UUID(), name: String, configs: [DisplayConfig]) {
        self.id = id
        self.name = name
        self.configs = configs
        self.createdAt = Date()
    }
}

// MARK: - Global C Callback for Config Protection

private func configProtectionCallback(
    displayID: CGDirectDisplayID,
    flags: CGDisplayChangeSummaryFlags,
    userInfo: UnsafeMutableRawPointer?
) {
    guard let ptr = userInfo else { return }
    let service = Unmanaged<ConfigProtectionService>.fromOpaque(ptr).takeUnretainedValue()

    // Only act on the "end" phase to avoid mid-transition state.
    guard flags.contains(.beginConfigurationFlag) == false else { return }

    Task { @MainActor in
        service.handleDisplayChange(displayID: displayID, flags: flags)
    }
}

// MARK: - ConfigProtectionService

@MainActor
final class ConfigProtectionService: ObservableObject, @unchecked Sendable {
    static let shared = ConfigProtectionService()
    private init() {
        loadSnapshots()
        loadProtectedItems()
    }

    // MARK: - State

    /// Named snapshots saved to disk.
    @Published var snapshots: [NamedSnapshot] = []

    /// Per-display protection settings.  Key = CGDirectDisplayID as UInt32.
    @Published var protectedItems: [UInt32: ProtectedItems] = [:]

    /// Whether config protection monitoring is active.
    @Published var isMonitoring: Bool = false

    nonisolated(unsafe) private var callbackContext: UnsafeMutableRawPointer?

    // MARK: - Snapshot Management

    func saveSnapshot(name: String, displays: [DisplayInfo]) {
        let configs = displays.map { DisplayConfig(from: $0) }
        let snapshot = NamedSnapshot(name: name, configs: configs)
        snapshots.append(snapshot)
        persistSnapshots()
    }

    func deleteSnapshot(id: UUID) {
        snapshots.removeAll { $0.id == id }
        persistSnapshots()
    }

    func restoreSnapshot(_ snapshot: NamedSnapshot, displays: [DisplayInfo]) {
        for config in snapshot.configs {
            guard let display = displays.first(where: { $0.displayID == config.displayID }) else { continue }
            applyConfig(config, to: display)
        }
    }

    // MARK: - Protection Monitoring

    func startMonitoring(displays: [DisplayInfo]) {
        guard !isMonitoring else { return }

        // Take a baseline snapshot for each display if none exist
        for display in displays {
            if protectedItems[display.displayID] == nil {
                protectedItems[display.displayID] = ProtectedItems()
            }
        }

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        callbackContext = ctx
        CGDisplayRegisterReconfigurationCallback(configProtectionCallback, ctx)
        isMonitoring = true
    }

    func stopMonitoring() {
        guard isMonitoring, let ctx = callbackContext else { return }
        CGDisplayRemoveReconfigurationCallback(configProtectionCallback, ctx)
        callbackContext = nil
        isMonitoring = false
    }

    /// Called from the C callback. Checks what changed and restores if protected.
    func handleDisplayChange(displayID: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags) {
        guard let items = protectedItems[displayID], items.anyEnabled else { return }

        // Find the most recent snapshot that contains this display
        guard let snapshot = snapshots.last,
              let savedConfig = snapshot.configs.first(where: { $0.displayID == displayID })
        else { return }

        var needsRestore = false

        if items.resolution && flags.contains(.setModeFlag) {
            needsRestore = true
        }
        if items.refreshRate && flags.contains(.setModeFlag) {
            needsRestore = true
        }
        if items.rotation && flags.contains(.setModeFlag) {
            needsRestore = true
        }
        if items.mirror && flags.contains(.mirrorFlag) {
            needsRestore = true
        }
        if items.mainDisplay && flags.contains(.setMainFlag) {
            needsRestore = true
        }

        if needsRestore {
            // Slight delay to let system finish the change before we restore
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                self.applyConfigByID(savedConfig)
            }
        }
    }

    // MARK: - Per-Display Protection Items

    func items(for displayID: CGDirectDisplayID) -> ProtectedItems {
        protectedItems[displayID] ?? ProtectedItems()
    }

    func updateItems(_ items: ProtectedItems, for displayID: CGDirectDisplayID) {
        protectedItems[displayID] = items
        saveProtectedItems()
    }

    // MARK: - Restore Logic

    private func applyConfig(_ config: DisplayConfig, to display: DisplayInfo) {
        let items = protectedItems[config.displayID] ?? ProtectedItems()

        // Restore resolution + refresh rate
        if items.resolution || items.refreshRate {
            if let mode = display.availableModes.first(where: {
                $0.width == config.width && $0.height == config.height &&
                (items.refreshRate ? abs($0.refreshRate - config.refreshRate) < 0.5 : true)
            }) {
                ResolutionService.shared.setDisplayMode(mode, for: display.displayID)
            }
        }

        // Restore rotation
        if items.rotation {
            if Int(display.rotation) != Int(config.rotation) {
                RotationService.shared.setRotation(Int(config.rotation), for: display.displayID)
            }
        }
    }

    private func applyConfigByID(_ config: DisplayConfig) {
        // We don't have a direct DisplayInfo here, so rebuild from CoreGraphics
        let items = protectedItems[config.displayID] ?? ProtectedItems()

        if items.resolution || items.refreshRate {
            let modes = DisplayMode.availableModes(for: config.displayID)
            if let mode = modes.first(where: {
                $0.width == config.width && $0.height == config.height &&
                (items.refreshRate ? abs($0.refreshRate - config.refreshRate) < 0.5 : true)
            }) {
                ResolutionService.shared.setDisplayMode(mode, for: config.displayID)
            }
        }

        if items.rotation {
            RotationService.shared.setRotation(Int(config.rotation), for: config.displayID)
        }
    }

    // MARK: - Persistence: Snapshots

    private var snapshotsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("FreeDisplay/configs", isDirectory: true)
    }

    private var snapshotsFileURL: URL {
        snapshotsDirectory.appendingPathComponent("snapshots.json")
    }

    private func loadSnapshots() {
        try? FileManager.default.createDirectory(at: snapshotsDirectory, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: snapshotsFileURL),
              let decoded = try? JSONDecoder().decode([NamedSnapshot].self, from: data)
        else { return }
        snapshots = decoded
    }

    private func persistSnapshots() {
        try? FileManager.default.createDirectory(at: snapshotsDirectory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        try? data.write(to: snapshotsFileURL, options: .atomicWrite)
    }

    // MARK: - Persistence: Protected Items

    private let protectedItemsKey = "ConfigProtectionItems"

    private func loadProtectedItems() {
        guard let data = UserDefaults.standard.data(forKey: protectedItemsKey),
              let decoded = try? JSONDecoder().decode([UInt32: ProtectedItems].self, from: data)
        else { return }
        protectedItems = decoded
    }

    private func saveProtectedItems() {
        guard let data = try? JSONEncoder().encode(protectedItems) else { return }
        UserDefaults.standard.set(data, forKey: protectedItemsKey)
    }
}
