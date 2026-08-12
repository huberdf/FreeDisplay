import OSLog

/// Shared os_log loggers. Read them with:
///
///     log stream --predicate 'subsystem == "com.freedisplay.app"' --style compact
///     log show   --predicate 'subsystem == "com.freedisplay.app"' --last 5m --style compact
///
/// Use `privacy: .public` on interpolated values — os_log redacts dynamic values by
/// default and they show up as `<private>` otherwise.
enum FDLog {
    static let capture = Logger(subsystem: "com.freedisplay.app", category: "capture")
    static let sidecar = Logger(subsystem: "com.freedisplay.app", category: "sidecar")
}
