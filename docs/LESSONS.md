# Lessons Learned

Hard-won constraints. Each one cost real debugging time; don't relearn them.

## HiDPI

- **Use plist overrides, never mirroring.** `CGConfigureDisplayMirrorOfDisplay` with a virtual display triggers hardware mirror mode and mouse stutter on Apple Silicon. Write `scale-resolutions` to `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-XXXX/DisplayProductID-XXXX` instead (the BetterDisplay approach).
- Writing there needs admin rights → `NSAppleScript("do shell script … with administrator privileges")`.
- Don't set `DisplayProductName` in the override plist; it replaces the system display name.
- macOS only loads new override modes when the display is (re)connected. `IOServiceRequestProbe` is not reliable.
- Native resolution = largest entry in `availableModes`. `CGDisplayPixelsWide/High` returns the *current* mode.

## Private APIs

- Load private framework symbols with `dlopen` + `dlsym`. `@_silgen_name` compiles but fails to link.
- `CGVirtualDisplay`: `vendorID` must be non-zero (e.g. `0xEEEE`) or init returns nil. `CGVirtualDisplay(descriptor:)` must run on the main thread; `apply(settings)` can run in the background.
- Bridging-header property names must match the runtime exactly (`maxPixelsWide`/`maxPixelsHigh`, not `maxPixelSize`). Use Chromium's `virtual_display_mac_util.mm` as the reference, never guess.
- Virtual display configs are runtime-only. Auto-recreating them on launch piles up stale displays.
- `CGSConfigureDisplayMode(CGDisplayConfigRef config, CGDirectDisplayID, int modeNum)` takes the transaction from `CGBeginDisplayConfiguration` as its first argument (see CGSInternal). Passing a connection ID makes CoreGraphics dereference a bogus pointer.
- Applying a non-display ICC profile (CMYK, gray, Lab/XYZ, abstract, named color) with `ColorSyncDeviceSetCustomProfiles` aborts the app inside SkyLight. Only offer `mntr` class + `RGB ` profiles. Read ICC signatures from `ColorSyncProfileCopyData`; `ColorSyncProfileCopyHeader` returns byte-swapped fields (`BGR `).

## DDC / IOKit

- IOFramebuffer I2C (`IOFBCopyI2CInterfaceForBus`) silently does nothing on Apple Silicon. Use IOAVService via `DCPAVServiceProxy`.
- Don't match IOKit services with `CGDisplayVendorNumber/ModelNumber`; they don't always match IOKit's IDs. Use `NSScreen.localizedName` for names.
- `CGDisplayIOServicePort` is unavailable. Enumerate `IODisplayConnect` with `IOServiceGetMatchingServices`.
- Integer values in IOKit CF dictionaries may bridge as `Int`, not `UInt32`. Try both.
- DDC reads take 50 ms or more. Cache them (5 s TTL), invalidate after writes, and degrade gracefully when DDC is unsupported.
- Keep microsecond IOKit calls synchronous. Making name lookup async caused races and "Display N" flicker.

## Shared resources & lifecycle

- One writer per CoreGraphics resource. `GammaService` owns the transfer table; `BrightnessService` supplies a factor it multiplies in. Every code path (formula *and* quantized table) must apply the factor.
- Never call `CGDisplayRestoreColorSyncSettings()` (global). Use `GammaService.resetSingleDisplay(_:)`.
- Sleep resets all transfer tables. Reapply on `didWakeNotification`: brightness before gamma, or the screen flashes at full brightness.
- Pass `self` to long-lived C callbacks with `Unmanaged.passRetained`, and `release()` on unregister.
- Lock mutable state that is read from multiple threads (e.g. `GammaService.activeAdjustments` uses an `NSLock`).
- Auto brightness must back off after a manual change (30 s cooldown).
- Set `NSWindow.isReleasedWhenClosed = false` for windows you keep in a dictionary.
- Don't mutate a dictionary while iterating it; collect the keys first.
- Wrap blocking WindowServer calls in `CGHelpers.runWithTimeout`.
- `CGCompleteDisplayConfiguration` invalidates the config on return, even when it fails. Never call `CGCancelDisplayConfiguration` after it (use-after-free); cancel only before completing.
- Event tap callbacks don't own the passed-in event: return `Unmanaged.passUnretained(event)` to pass it through. `passRetained` leaks one event per call.
- Swift 6 inserts a runtime main-thread check into closures created in a `@MainActor` context and passed as non-`@Sendable` parameters. If such a closure runs on another queue (DDC completions, XPC handlers), the app traps. Mark completion handlers that run off-main `@Sendable`.

## SwiftUI / MenuBarExtra

- Custom content needs `.menuBarExtraStyle(.window)`. Hide the Dock icon with `INFOPLIST_KEY_LSUIElement: true`.
- On macOS 27 the panel is sized to the content's *minimum* size, so a bare `ScrollView` collapses to 0 height. Test layout on macOS 27, not only on the macOS 14 target.
- Row components with local state (`isHovered`, `isLoading`) must be separate `struct`s. `@ViewBuilder` functions can't hold `@State`.
- Observe shared singletons with `@ObservedObject`, not `@StateObject`.
- Don't make IOKit/CG calls in `body`; load them in `.task`/`onAppear`.
- `flag = true; syncWork(); flag = false` never renders the intermediate state. Use async.

## Build

- After changing `project.yml` or adding files, run `xcodegen generate`.
- `GENERATE_INFOPLIST_FILE: YES` is required (XcodeGen doesn't create an Info.plist).
- Swift 6 singletons: `@MainActor` + `@unchecked Sendable`, with `SWIFT_STRICT_CONCURRENCY: minimal`.
- `deinit` is nonisolated. Properties it touches need `nonisolated(unsafe)`.
- `import IOKit` doesn't include I2C/graphics. Add `import IOKit.i2c` / `import IOKit.graphics`.
- ColorSync globals: `@preconcurrency import ColorSync` and `.takeUnretainedValue()`.
