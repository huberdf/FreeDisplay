# FreeDisplay

> A free, open-source alternative to BetterDisplay — macOS display management in your menu bar.
> BetterDisplay 的免费开源替代品 — macOS 显示器管理菜单栏应用

[Download Latest Release](https://github.com/OWNER/FreeDisplay/releases/latest) | [Report an Issue](https://github.com/OWNER/FreeDisplay/issues)

---

## Features / 功能特性

| Feature | Description |
|---------|-------------|
| **Brightness & Contrast** | DDC/CI hardware control for external monitors; software gamma for built-in |
| **Resolution & HiDPI** | Switch resolutions, enable HiDPI scaling, create HiDPI virtual displays |
| **Rotation** | Rotate any display 0°/90°/180°/270° |
| **Arrangement** | Visual display arrangement matching System Settings |
| **Color Management** | Switch ICC color profiles per display |
| **Image Adjustment** | Software contrast, gamma, color temperature, RGB channels, invert colors |
| **Screen Mirroring** | Mirror any display to any other display |
| **Screen Streaming & PiP** | Stream any display into a floating Picture-in-Picture window |
| **Virtual Display** | Create dummy/virtual displays (useful for headless setups or extra workspaces) |
| **Config Protection** | Prevent macOS from resetting resolution/refresh rate/color settings |
| **Auto Brightness** | Automatically adjust brightness based on time of day |
| **Notch Management** | Show/hide the notch overlay on MacBooks with a notch |
| **Display Presets** | Save and instantly restore full display configurations |
| **Launch at Login** | Start FreeDisplay automatically on login |

---

## System Requirements / 系统要求

- macOS 14.0 (Sonoma) or later
- External monitor recommended for DDC brightness/contrast control
- Screen Recording permission required for streaming/PiP features

---

## Installation / 安装

### Option 1: Download DMG (Recommended)

1. Download the latest `FreeDisplay.dmg` from [Releases](https://github.com/OWNER/FreeDisplay/releases/latest)
2. Open the DMG and drag **FreeDisplay.app** into your **Applications** folder
3. First launch: right-click FreeDisplay.app → **Open** (see Gatekeeper note below)

### Option 2: Build from Source

```bash
# Prerequisites: Xcode, xcodegen
brew install xcodegen

git clone https://github.com/OWNER/FreeDisplay.git
cd FreeDisplay
xcodegen generate
xcodebuild -scheme FreeDisplay -configuration Release build
```

---

## Gatekeeper Notice / 安全提示

Since FreeDisplay is not signed with an Apple Developer ID, macOS will show a warning on first launch.

**To open the app:**

1. Right-click (or Control-click) `FreeDisplay.app` → **Open**
2. Click **Open** in the dialog

Or via System Settings:
- After a blocked launch attempt, go to **System Settings → Privacy & Security**
- Scroll down and click **Open Anyway** next to the FreeDisplay entry

> This is a one-time step. After the first approval, the app opens normally.

---

## Permissions Required / 权限说明

| Permission | Why |
|------------|-----|
| **Accessibility** | Required for DDC communication with external monitors |
| **Screen Recording** | Required for screen streaming and PiP features |

FreeDisplay does **not** require an internet connection except for optional update checks.

---

## Tech Stack / 技术栈

- **Swift 6** + **SwiftUI** (MenuBarExtra)
- **IOKit** — DDC/CI I2C communication for hardware brightness/contrast
- **CoreGraphics** — Display enumeration, resolution, rotation, arrangement
- **ScreenCaptureKit** — Screen capture and streaming
- **ColorSync** — ICC color profile management
- **CGVirtualDisplay** — Virtual display creation (macOS 14+)
- Zero third-party dependencies

---

## Project Structure / 项目结构

```
FreeDisplay/
├── App/              # AppDelegate, app entry point
├── Models/           # DisplayInfo, DisplayMode data models
├── Services/         # All system-level services (DDC, brightness, resolution, etc.)
├── ViewModels/       # Observable state bridges between Views and Services
└── Views/            # SwiftUI views for each feature
```

See [`docs/CODEMAP.md`](docs/CODEMAP.md) for a detailed file map.

---

## License / 许可证

MIT License — see [LICENSE](LICENSE) for details.
