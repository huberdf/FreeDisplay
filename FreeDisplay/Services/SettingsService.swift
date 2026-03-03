import Foundation
import CoreGraphics
import Combine

/// Centralized settings persistence service.
/// Simple settings use UserDefaults via @AppStorage-compatible keys.
/// Complex configurations are stored as JSON in ~/Library/Application Support/FreeDisplay/.
@MainActor
final class SettingsService: ObservableObject, @unchecked Sendable {
    static let shared = SettingsService()

    private let defaults = UserDefaults.standard
    private let supportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("FreeDisplay", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        loadAll()
    }

    // MARK: - Keys

    private enum Keys {
        static let launchAtLogin          = "launchAtLogin"
        static let menuWidth              = "menuWidth"
        static let showCombinedBrightness = "showCombinedBrightness"
        static let ddcCacheTTL            = "ddcCacheTTL"
        static let checkUpdatesOnLaunch   = "checkUpdatesOnLaunch"
        static let colorPickerHistory     = "colorPickerHistory"
        // Per-display keys use prefix + displayID
        static let brightnessPrefix       = "brightness_"
        static let contrastPrefix         = "contrast_"
        static let favoriteModesPrefix    = "favModes_"
    }

    // MARK: - Published Settings

    @Published var launchAtLogin: Bool = false {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    @Published var menuWidth: Double = 320 {
        didSet { defaults.set(menuWidth, forKey: Keys.menuWidth) }
    }

    @Published var showCombinedBrightness: Bool = true {
        didSet { defaults.set(showCombinedBrightness, forKey: Keys.showCombinedBrightness) }
    }

    @Published var ddcCacheTTL: Double = 5.0 {
        didSet { defaults.set(ddcCacheTTL, forKey: Keys.ddcCacheTTL) }
    }

    @Published var checkUpdatesOnLaunch: Bool = true {
        didSet { defaults.set(checkUpdatesOnLaunch, forKey: Keys.checkUpdatesOnLaunch) }
    }

    /// Recently sampled colors (hex strings, newest first, max 20).
    @Published var colorPickerHistory: [String] = [] {
        didSet {
            defaults.set(colorPickerHistory, forKey: Keys.colorPickerHistory)
        }
    }

    // MARK: - Per-Display Settings

    func brightness(for displayID: CGDirectDisplayID) -> Double? {
        let key = Keys.brightnessPrefix + "\(displayID)"
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.double(forKey: key)
    }

    func setBrightness(_ value: Double, for displayID: CGDirectDisplayID) {
        defaults.set(value, forKey: Keys.brightnessPrefix + "\(displayID)")
    }

    func contrast(for displayID: CGDirectDisplayID) -> Double? {
        let key = Keys.contrastPrefix + "\(displayID)"
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.double(forKey: key)
    }

    func setContrast(_ value: Double, for displayID: CGDirectDisplayID) {
        defaults.set(value, forKey: Keys.contrastPrefix + "\(displayID)")
    }

    func favoriteModes(for displayID: CGDirectDisplayID) -> [String] {
        return defaults.stringArray(forKey: Keys.favoriteModesPrefix + "\(displayID)") ?? []
    }

    func setFavoriteModes(_ modes: [String], for displayID: CGDirectDisplayID) {
        defaults.set(modes, forKey: Keys.favoriteModesPrefix + "\(displayID)")
    }

    // MARK: - Color History

    func addColorToHistory(_ hex: String) {
        var history = colorPickerHistory.filter { $0 != hex }
        history.insert(hex, at: 0)
        if history.count > 20 { history = Array(history.prefix(20)) }
        colorPickerHistory = history
    }

    // MARK: - JSON Persistence Helpers

    func save<T: Encodable>(_ value: T, filename: String) {
        let url = supportDir.appendingPathComponent(filename)
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[SettingsService] Failed to save \(filename): \(error)")
        }
    }

    func load<T: Decodable>(_ type: T.Type, filename: String) -> T? {
        let url = supportDir.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: - Load All

    private func loadAll() {
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        menuWidth = defaults.object(forKey: Keys.menuWidth) != nil
            ? defaults.double(forKey: Keys.menuWidth) : 320
        showCombinedBrightness = defaults.object(forKey: Keys.showCombinedBrightness) != nil
            ? defaults.bool(forKey: Keys.showCombinedBrightness) : true
        ddcCacheTTL = defaults.object(forKey: Keys.ddcCacheTTL) != nil
            ? defaults.double(forKey: Keys.ddcCacheTTL) : 5.0
        checkUpdatesOnLaunch = defaults.object(forKey: Keys.checkUpdatesOnLaunch) != nil
            ? defaults.bool(forKey: Keys.checkUpdatesOnLaunch) : true
        colorPickerHistory = defaults.stringArray(forKey: Keys.colorPickerHistory) ?? []
    }
}
