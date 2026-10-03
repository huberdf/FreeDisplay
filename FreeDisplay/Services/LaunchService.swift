import Foundation
import ServiceManagement

/// Manages "Launch at Login" via a per-user launchd agent (~/Library/LaunchAgents).
///
/// Besides starting FreeDisplay at login, the agent restarts it after a crash:
/// `KeepAlive.SuccessfulExit = false` relaunches on a non-zero exit or a signal, while a
/// normal Quit (exit 0) is left alone. launchd throttles restarts (ThrottleInterval).
@MainActor
final class LaunchService: @unchecked Sendable {
    static let shared = LaunchService()
    private init() {}

    static let agentLabel = "com.freedisplay.app.agent"
    /// Passed by the agent so a launchd-started instance can be told apart from a manual launch.
    static let managedLaunchArgument = "--launchd"

    /// True when launchd started this process (login or crash restart).
    static var isManagedLaunch: Bool {
        CommandLine.arguments.contains(managedLaunchArgument)
    }

    private var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Self.agentLabel).plist")
    }

    private var domain: String { "gui/\(getuid())" }
    private var job: String { "\(domain)/\(Self.agentLabel)" }

    // MARK: - State

    var isEnabled: Bool {
        FileManager.default.fileExists(atPath: agentURL.path)
    }

    // MARK: - Enable / Disable

    @discardableResult
    func enable() -> Bool {
        guard writeAgentPlist() else { return false }
        if Self.isManagedLaunch {
            // Already supervised by launchd; just make sure the job isn't disabled.
            launchctl("enable", job)
        } else {
            handOverToAgent(reload: true)
        }
        return true
    }

    @discardableResult
    func disable() -> Bool {
        launchctl("disable", job)
        // Booting out the job would also kill this process if launchd started it;
        // in that case the loaded job just ends at logout.
        if !Self.isManagedLaunch {
            launchctl("bootout", job)
        }
        try? FileManager.default.removeItem(at: agentURL)
        return !isEnabled
    }

    /// Toggle and return the new state.
    @discardableResult
    func toggle() -> Bool {
        if isEnabled {
            disable()
            return false
        } else {
            enable()
            return true
        }
    }

    // MARK: - Launch-time Sync

    /// Called once at launch: migrates the old SMAppService login item to the agent, keeps the
    /// agent pointing at the current app location, and hands a manually opened copy over to
    /// launchd so crash restarts cover it.
    func prepareAtLaunch() {
        if #available(macOS 13.0, *), SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
            enable()
            return
        }
        guard isEnabled else { return }
        let moved = agentProgramPath() != Bundle.main.executablePath
        if moved {
            writeAgentPlist()
        }
        if !Self.isManagedLaunch {
            handOverToAgent(reload: moved)
        }
    }

    // MARK: - Helpers

    /// Starts the agent so launchd runs a supervised instance; that instance then takes over
    /// from this manually opened one (see AppDelegate). Never called from a launchd-started process.
    private func handOverToAgent(reload: Bool) {
        launchctl("enable", job)
        if reload {
            launchctl("bootout", job)
        }
        // kickstart if the job is already loaded; otherwise bootstrap it (RunAtLoad starts it).
        if !launchctl("kickstart", job) {
            launchctl("bootstrap", domain, agentURL.path)
        }
    }

    @discardableResult
    private func writeAgentPlist() -> Bool {
        guard let executable = Bundle.main.executablePath else { return false }
        let plist: [String: Any] = [
            "Label": Self.agentLabel,
            "ProgramArguments": [executable, Self.managedLaunchArgument],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive",
            "ThrottleInterval": 10,
        ]
        do {
            try FileManager.default.createDirectory(
                at: agentURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: agentURL, options: .atomic)
            return true
        } catch {
            #if DEBUG
            print("[LaunchService] writing agent plist failed: \(error)")
            #endif
            return false
        }
    }

    private func agentProgramPath() -> String? {
        guard let data = try? Data(contentsOf: agentURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String]
        else { return nil }
        return arguments.first
    }

    /// Runs `/bin/launchctl` synchronously (it returns immediately) and reports success.
    @discardableResult
    private func launchctl(_ arguments: String...) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
