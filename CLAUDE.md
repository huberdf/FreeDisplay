# FreeDisplay

Free, open-source BetterDisplay alternative: a macOS menu bar app for DDC brightness/contrast, resolution and HiDPI, arrangement, color profiles, image adjustments, auto brightness and virtual displays. UI in Turkish and English.

Swift 6 + SwiftUI (`MenuBarExtra`) + IOKit + CoreGraphics. No third-party dependencies. macOS 14+. App Sandbox is off (DDC/IOKit need it).

- Architecture and services: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Pitfalls you must not repeat: [docs/LESSONS.md](docs/LESSONS.md)

## Build

```bash
xcodegen generate          # after editing project.yml or adding files
xcodebuild -scheme FreeDisplay -configuration Debug build 2>&1 | tail -5
./build.sh                 # Release archive + DMG in build/
```

There is no automated test suite. DDC, HiDPI and brightness changes must be checked on a real external display.

## Language

- Code, comments, commit messages and docs: **English**.
- User-facing strings: inline Turkish/English pairs via `L("Türkçe", "English")` (defined in `SettingsService.swift`). Never hard-code a single-language UI string.

## Rules

**Structure**
- Views never call CoreGraphics/IOKit directly; go through a Service.
- Services are `@MainActor final class … : ObservableObject, @unchecked Sendable` singletons (`static let shared`).
- Row components with local state (`isHovered`, `isLoading`) are separate `struct`s named `XxxRow`, not `@ViewBuilder` functions.
- UserDefaults keys always use the `fd.` prefix (`fd.launchAtLogin`).
- When changing `DisplayInfo` properties, grep every reference and update them.
- Concurrency errors: use `@MainActor` or `@unchecked Sendable` (`SWIFT_STRICT_CONCURRENCY: minimal`).
- Only make genuinely slow work async (file scans, network). Keep microsecond IOKit calls synchronous.

**Display hardware**
- `GammaService` is the only writer of `CGSetDisplayTransferByFormula/Table`. Software brightness goes through it. Never call the global `CGDisplayRestoreColorSyncSettings()`; use `GammaService.resetSingleDisplay(_:)`.
- Services that write display state must reapply it on `NSWorkspace.didWakeNotification` (wired in `FreeDisplayApp` via `AppDelegate.onWake`).
- Long-lived C callbacks: `Unmanaged.passRetained(self)` + `release()` on unregister. Never `passUnretained`.
- HiDPI uses plist overrides in `/Library/Displays/Contents/Resources/Overrides/` (admin via `NSAppleScript`). Never use `CGConfigureDisplayMirrorOfDisplay` for HiDPI. Never set `DisplayProductName`.
- Private frameworks: `dlopen` + `dlsym`, never `@_silgen_name`.
- `CGVirtualDisplay`: non-zero `vendorID`, create on the main thread. Bridging-header names follow Chromium's `virtual_display_mac_util.mm`.
- Don't match IOKit services via `CGDisplayVendorNumber/ModelNumber`. Use `NSScreen.localizedName` for names. DDC may be unavailable, so the UI must degrade gracefully.

**Ask the user first** before adding new private APIs, anything that needs SIP off or special permissions, third-party dependencies, or architecture changes.

## Keeping docs current

- Added/removed a Service or changed a key flow → update `docs/ARCHITECTURE.md`.
- Hit a non-obvious pitfall → add one line to `docs/LESSONS.md`.
- User-visible change → add it to `CHANGELOG.md`.
