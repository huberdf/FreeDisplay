# FreeDisplay

> **Free & open-source alternative to [BetterDisplay](https://github.com/waydabber/BetterDisplay)** — all the core display management features, zero cost.

BetterDisplay is a great app, but its best features are locked behind a paid Pro license. FreeDisplay implements the most essential BetterDisplay features as a completely free, open-source macOS menu bar app.

[Download Latest Release](https://github.com/hakanotal/FreeDisplayTurkish/releases/latest) | [Report an Issue](https://github.com/hakanotal/FreeDisplayTurkish/issues)

> 🇹🇷 **Turkish edition** — maintained by [@hakanotal](https://github.com/hakanotal).

---

## What's Changed in This Fork

- **Turkish + English UI** — full Turkish translation; switch languages live in Settings → Dil / Language
- **Night mode** — blue light filter that warms all displays, always on or on a daily schedule
- **macOS 27 fixes** — menu no longer collapses to just the footer, and it shrinks back when sections collapse
- **Crash fixes** — brightness/presets, color profiles, resolution fallback and display arrangement no longer crash the app
- **Color profile** — shows the active profile (e.g. your monitor's own) instead of "Unknown", and updates live; only display-compatible profiles are listed (picking a CMYK/gray profile used to crash)
- **Auto-restart** — with "Launch at login" on, FreeDisplay relaunches itself after a crash (Quit still quits)
- **HiDPI** — asks for your password once per monitor instead of on every enable/disable
- **Cleaner menu** — removed the built-in "Native Mode" / "HiDPI Mode" preset buttons; settings switches right-aligned

---

## What BetterDisplay Features Does This Replace?

| BetterDisplay Feature | FreeDisplay | Notes |
|----------------------|:-----------:|-------|
| DDC Brightness & Contrast | ✅ | Hardware control via IOKit I2C (Intel) / IOAVService (Apple Silicon) |
| Software Brightness (Gamma) | ✅ | Per-display gamma table control with smooth transitions |
| Keyboard Brightness Keys for External Displays | ✅ | Intercepts brightness keys when cursor is on external display, shows native macOS OSD |
| Auto Brightness Sync | ✅ | Syncs external display brightness with built-in display changes |
| HiDPI Virtual Displays | ✅ | Creates HiDPI dummy displays via CGVirtualDisplay private API |
| Display Arrangement | ✅ | Position displays (external above built-in, etc.) |
| Resolution & HiDPI Switching | ✅ | Browse and switch all available display modes including HiDPI |
| ICC Color Profile Management | ✅ | Switch color profiles per display via ColorSync |
| Image Adjustment (Gamma/Temperature) | ✅ | Software contrast, color temperature, RGB channels, invert |
| Display Presets | ✅ | Save & restore full display configurations with one click |
| Virtual Display (Dummy) | ✅ | Create headless virtual displays |
| Notch Management | ✅ | Hide the MacBook notch with a black overlay |
| Launch at Login | ✅ | Via SMAppService |

### Not Included (intentionally)

- Screen streaming / PiP — rarely used, adds complexity
- EDID override — requires SIP disabled
- XDR/HDR extra brightness — requires specific hardware

---

## Screenshots

<p align="center">
  <img src="docs/Screenshot-1.png" alt="Main menu: display, presets, combined brightness and tools" width="260" align="top">
  <img src="docs/Screenshot-2.png" alt="Display panel: brightness, HiDPI mode, display modes, color profile and image adjustments" width="260" align="top">
  <img src="docs/Screenshot-3.png" alt="Tools expanded: auto brightness, night mode schedule and settings with the language switch" width="260" align="top">
</p>

---

## Installation

### Option 1: Download DMG

1. Download the latest `FreeDisplay-<version>.dmg` from [Releases](https://github.com/hakanotal/FreeDisplayTurkish/releases/latest) (universal: Apple Silicon + Intel, macOS 14+)
2. Open the DMG and drag **FreeDisplay.app** to **Applications**
3. First launch: the app isn't notarized, so macOS blocks it once. Open it, then go to **System Settings → Privacy & Security** and click **Open Anyway** — or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/FreeDisplay.app
   ```

### Option 2: Build from Source

```bash
git clone https://github.com/hakanotal/FreeDisplayTurkish.git
cd FreeDisplayTurkish
./scripts/build-dmg.sh   # → build/FreeDisplay.app and build/FreeDisplay-<version>.dmg
```

Xcode is optional: without it the script builds with the Command Line Tools (`xcode-select --install`). With Xcode you can also open `FreeDisplay.xcodeproj` (regenerate it with `xcodegen generate` after editing `project.yml`).

---

## Permissions

| Permission | Why |
|------------|-----|
| **Accessibility** | Required for brightness key interception on external displays |

No internet connection required (except optional update checks via GitHub Releases API).

---

## Tech Stack

- **Swift 6** + **SwiftUI** (MenuBarExtra)
- **IOKit** — DDC/CI I2C for hardware brightness/contrast
- **CoreGraphics** — Display enumeration, resolution, arrangement
- **ColorSync** — ICC color profile management
- **CGVirtualDisplay** — Virtual display creation (private API, macOS 14+)
- **CoreDisplay** — Built-in display brightness reading (private API, via dlopen)
- Zero third-party dependencies

---

## Project Structure

```
FreeDisplay/
├── App/              # AppDelegate, app entry point
├── Models/           # DisplayInfo, DisplayMode, DisplayPreset
├── Services/         # System-level services (DDC, brightness, resolution, gamma, etc.)
└── Views/            # SwiftUI views for each feature section
```

---

## How It Works

FreeDisplay sits in your menu bar and talks directly to your displays:

- **External monitors**: Uses DDC/CI protocol over I2C (Intel) or IOAVService (Apple Silicon) to control hardware brightness, contrast, and other settings
- **Built-in display**: Uses CoreGraphics gamma tables for software brightness adjustment
- **Brightness keys**: Installs a CGEventTap to intercept keyboard brightness keys and route them to the display under your mouse cursor
- **Auto brightness**: Polls the built-in display brightness via CoreDisplay private API and proportionally adjusts external displays
- **HiDPI**: Creates virtual displays via CGVirtualDisplay private API, or writes display override plists for persistent HiDPI

---

## Contributing

Issues and PRs welcome. This project uses:
- `xcodegen` for project generation (edit `project.yml`, not `.xcodeproj`)
- Swift 6 with `SWIFT_STRICT_CONCURRENCY: minimal`
- MVVM architecture (View → ViewModel → Service)

---

## Contributors

- [@huberdf](https://github.com/huberdf) — original author
- [@hakanotal](https://github.com/hakanotal) — Turkish translation (Türkçe çeviri)

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

## Acknowledgments

- Inspired by [BetterDisplay](https://github.com/waydabber/BetterDisplay), [MonitorControl](https://github.com/MonitorControl/MonitorControl), and [Lunar](https://lunar.fyi/)
- CGVirtualDisplay bridging header based on [Chromium's virtual_display_mac_util.mm](https://chromium.googlesource.com/chromium/src/+/main/ui/display/mac/test/virtual_display_mac_util.mm)
