import CoreGraphics
import Foundation

/// Manages virtual display configurations and (when private API access is approved) creates
/// CGVirtualDisplay instances.
///
/// NOTE: CGVirtualDisplay is exported by CoreGraphics but not declared in public Swift/ObjC headers
/// as of macOS 26 SDK. Creating actual virtual displays requires using the private API.
/// See docs/BLOCKING.md — B-002 for details. Until resolved, create/activate always return false.
@MainActor
final class VirtualDisplayService: ObservableObject, @unchecked Sendable {
    static let shared = VirtualDisplayService()
    private init() {
        loadConfigs()
    }

    // MARK: - Config Model

    struct VirtualDisplayConfig: Codable, Identifiable, Equatable {
        let id: UUID
        var name: String
        var width: Int
        var height: Int
        var refreshRate: Double
        var hiDPI: Bool
        var autoCreate: Bool

        init(id: UUID = UUID(), name: String, width: Int, height: Int,
             refreshRate: Double = 60.0, hiDPI: Bool = true, autoCreate: Bool = true) {
            self.id = id
            self.name = name
            self.width = width
            self.height = height
            self.refreshRate = refreshRate
            self.hiDPI = hiDPI
            self.autoCreate = autoCreate
        }
    }

    // MARK: - State

    @Published var configs: [VirtualDisplayConfig] = []

    /// Active config IDs — populated only when CGVirtualDisplay private API is available.
    @Published private(set) var activeConfigIDs: Set<UUID> = []

    /// HiDPI virtual display sessions: physical displayID → config UUID.
    @Published private(set) var hiDPIActiveDisplayIDs: Set<CGDirectDisplayID> = []

    private let configsKey = "VirtualDisplayConfigs"

    // MARK: - Queries

    func isActive(_ configID: UUID) -> Bool {
        activeConfigIDs.contains(configID)
    }

    func isHiDPIVirtualEnabled(for physicalID: CGDirectDisplayID) -> Bool {
        hiDPIActiveDisplayIDs.contains(physicalID)
    }

    // MARK: - Create / Destroy

    /// Attempts to create a virtual display.
    /// Returns false until CGVirtualDisplay private API usage is approved (see BLOCKING.md B-002).
    @discardableResult
    func create(config: VirtualDisplayConfig) -> Bool {
        // CGVirtualDisplay private API not yet enabled — see BLOCKING.md B-002
        return false
    }

    func destroy(id: UUID) {
        activeConfigIDs.remove(id)
    }

    // MARK: - Config Management

    func addAndCreate(_ config: VirtualDisplayConfig) {
        if !configs.contains(where: { $0.id == config.id }) {
            configs.append(config)
            saveConfigs()
        }
        create(config: config)
    }

    func removeConfig(id: UUID) {
        destroy(id: id)
        configs.removeAll { $0.id == id }
        saveConfigs()
    }

    // MARK: - HiDPI via Virtual Display + Mirror

    /// Enables HiDPI for an external display via a virtual display.
    /// Returns false until CGVirtualDisplay private API usage is approved (see BLOCKING.md B-002).
    @discardableResult
    func enableHiDPIVirtual(for physicalID: CGDirectDisplayID,
                             physicalWidth: Int,
                             physicalHeight: Int) -> Bool {
        // CGVirtualDisplay private API not yet enabled — see BLOCKING.md B-002
        return false
    }

    func disableHiDPIVirtual(for physicalID: CGDirectDisplayID) {
        hiDPIActiveDisplayIDs.remove(physicalID)
    }

    // MARK: - Persistence

    private func loadConfigs() {
        guard let data = UserDefaults.standard.data(forKey: configsKey),
              let decoded = try? JSONDecoder().decode([VirtualDisplayConfig].self, from: data)
        else { return }
        configs = decoded
    }

    private func saveConfigs() {
        guard let data = try? JSONEncoder().encode(configs) else { return }
        UserDefaults.standard.set(data, forKey: configsKey)
    }
}
