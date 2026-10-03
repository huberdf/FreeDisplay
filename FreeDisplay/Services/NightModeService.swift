import AppKit
import Foundation

/// Night mode (blue light filter): warms every display's white point through GammaService,
/// either always on or on a daily schedule. Transitions fade so the switch isn't jarring.
@MainActor
final class NightModeService: ObservableObject, @unchecked Sendable {
    static let shared = NightModeService()

    enum Mode: String, CaseIterable {
        case off, on, scheduled
    }

    private enum Keys {
        static let mode    = "fd.nightMode.mode"
        static let start   = "fd.nightMode.startMinutes"
        static let end     = "fd.nightMode.endMinutes"
        static let warmth  = "fd.nightMode.warmth"
    }

    /// Warmth slider range, mapped to colour temperature.
    private static let coolestKelvin = 5500.0
    private static let warmestKelvin = 2700.0

    private let defaults = UserDefaults.standard

    @Published var mode: Mode = .off {
        didSet {
            defaults.set(mode.rawValue, forKey: Keys.mode)
            evaluate(animated: true)
        }
    }

    /// Schedule start, in minutes after midnight (default 22:00).
    @Published var startMinutes: Int = 22 * 60 {
        didSet {
            defaults.set(startMinutes, forKey: Keys.start)
            evaluate(animated: true)
        }
    }

    /// Schedule end, in minutes after midnight (default 07:00). May be earlier than start (overnight).
    @Published var endMinutes: Int = 7 * 60 {
        didSet {
            defaults.set(endMinutes, forKey: Keys.end)
            evaluate(animated: true)
        }
    }

    /// 0 = slightly warm, 1 = very warm.
    @Published var warmth: Double = 0.5 {
        didSet {
            defaults.set(warmth, forKey: Keys.warmth)
            if isActive { applyTint() }
        }
    }

    /// Whether the filter is currently on (after evaluating the mode and schedule).
    @Published private(set) var isActive = false

    /// Current fade position: 0 = no filter, 1 = full warmth.
    private var strength = 0.0
    private var fadeTask: Task<Void, Never>?
    private var scheduleTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    // Property observers don't run during init, so loading doesn't write back or apply.
    private init() {
        mode = Mode(rawValue: defaults.string(forKey: Keys.mode) ?? "") ?? .off
        if defaults.object(forKey: Keys.start) != nil { startMinutes = defaults.integer(forKey: Keys.start) }
        if defaults.object(forKey: Keys.end) != nil { endMinutes = defaults.integer(forKey: Keys.end) }
        if defaults.object(forKey: Keys.warmth) != nil { warmth = defaults.double(forKey: Keys.warmth) }
    }

    /// Applies the saved state and starts watching the clock. Called once at launch.
    func start() {
        evaluate(animated: false)

        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in NightModeService.shared.evaluate(animated: true) }
        }

        // Timers don't fire during sleep, and the clock or time zone can jump: re-check right away.
        // (FreeDisplayApp's wake handler re-applies the tint once WindowServer has settled.)
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in NightModeService.shared.evaluate(animated: false) }
        })
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { _ in
                Task { @MainActor in NightModeService.shared.evaluate(animated: true) }
            })
        }
    }

    // MARK: - Schedule

    /// Whether `date` falls inside the schedule. Handles ranges that cross midnight;
    /// identical start and end means the schedule never turns on.
    func isInSchedule(_ date: Date = Date()) -> Bool {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let now = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if startMinutes < endMinutes {
            return now >= startMinutes && now < endMinutes
        } else if startMinutes > endMinutes {
            return now >= startMinutes || now < endMinutes
        }
        return false
    }

    /// Formats minutes after midnight in the user's time format (e.g. "22:00" or "10:00 PM").
    static func timeString(_ minutes: Int) -> String {
        date(forMinutes: minutes).formatted(date: .omitted, time: .shortened)
    }

    static func date(forMinutes minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    static func minutes(from date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    // MARK: - Applying

    private func evaluate(animated: Bool) {
        let shouldBeActive: Bool
        switch mode {
        case .off:       shouldBeActive = false
        case .on:        shouldBeActive = true
        case .scheduled: shouldBeActive = isInSchedule()
        }

        let target = shouldBeActive ? 1.0 : 0.0
        if isActive != shouldBeActive { isActive = shouldBeActive }
        guard strength != target || fadeTask != nil else { return }

        fadeTask?.cancel()
        fadeTask = nil
        guard animated else {
            strength = target
            applyTint()
            return
        }

        let from = strength
        fadeTask = Task { @MainActor [weak self] in
            let steps = 30
            for step in 1...steps {
                try? await Task.sleep(nanoseconds: 50_000_000)   // 1.5 s total
                guard let self, !Task.isCancelled else { return }
                let t = Double(step) / Double(steps)
                self.strength = from + (target - from) * t
                self.applyTint()
            }
            self?.fadeTask = nil
        }
    }

    private func applyTint() {
        let kelvin = Self.coolestKelvin - warmth * (Self.coolestKelvin - Self.warmestKelvin)
        let full = GammaService.shared.whitePointFactors(kelvin: kelvin)
        let s = strength
        GammaService.shared.setNightTint(
            r: 1 - s * (1 - full.r),
            g: 1 - s * (1 - full.g),
            b: 1 - s * (1 - full.b))
    }
}
