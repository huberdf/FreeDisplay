# Module Relationships — FreeDisplay

> 模块关系图、Services 内部依赖、数据流。快速参考见 [CLAUDE.md](CLAUDE.md)，文件树见 [file-tree.md](file-tree.md)。

---

## 模块关系图 / Module Relationship Diagram

```
App (FreeDisplayApp)
  └── @StateObject DisplayManager
        └── @Published [DisplayInfo]
              └── MenuBarView (@EnvironmentObject DisplayManager)
                    ├── DisplayRowView
                    │     └── DisplayDetailView  ← 12 Sections（三组分组）
                    │           ├── BrightnessSliderView     → BrightnessService → DDCService
                    │           ├── ResolutionSliderView     → ResolutionService
                    │           ├── DisplayModeListView      → ResolutionService
                    │           ├── ColorProfileView         → ColorProfileService
                    │           ├── ImageAdjustmentView      → GammaService
                    │           ├── MainDisplayView          → ArrangementService
                    │           ├── NotchView                → NotchOverlayManager
                    │           └── HiDPIVirtualRowView      → VirtualDisplayService
                    ├── ArrangementView          → ArrangementService
                    ├── VirtualDisplayView       → VirtualDisplayService
                    ├── AutoBrightnessView       → AutoBrightnessService → BrightnessService
                    ├── SystemColorMenuEntry     → SystemColorView → SettingsService
                    └── SettingsView             → SettingsService, LaunchService
```

---

## Services 层内部依赖 / Services Internal Dependencies

```
BrightnessService ──────────→ DDCService (外接屏 DDC 亮度读写)
AutoBrightnessService ──────→ BrightnessService (映射 lux→亮度后调用)
DisplayManager ─────────────→ BrightnessService (刷新时异步初始化亮度)
               ─────────────→ ArrangementService (setAsMainDisplay)
               ─────────────→ arrangeExternalAboveBuiltin() (热插拔后自动定位外接屏)

CGHelpers (共享工具) ────────→ 被以下 Service 使用（WindowServer IPC 超时保护）:
  ArrangementService (setPosition/setAsMainDisplay CG 事务)
  MirrorService (enableMirror/disableMirror CG 事务)
  ResolutionService (applyModeSync CG 事务)
  VirtualDisplayService (CGVirtualDisplay apply 事务)

GammaService (gamma 所有者) ─→ 唯一写入 CGSetDisplayTransferByFormula/Table 的 Service
  BrightnessService ─────────→ GammaService (软件亮度通过 GammaService 写入，不直接写 CG)
  ❌ View 层不得直接调 CGSetDisplayTransferByFormula/Table
  ❌ 不得使用 CGDisplayRestoreColorSyncSettings()（全局），改用 GammaService.resetSingleDisplay(displayID)

ResolutionService ──────────→ VirtualDisplayService.virtualDisplayID(for:) (镜像检测 fallback)
```

---

## 数据流 / Data Flow

```
单向数据流（响应式）：
  CGDisplayAPI / IOKit → Services → DisplayInfo (@Published) → Views (reactive SwiftUI)
  User interaction    → Views   → Services → Hardware

睡眠/唤醒数据流：
  NSWorkspace.didWakeNotification → AppDelegate
    → GammaService.reapplyIfNeeded()
    → BrightnessService.reapplySoftwareBrightnessIfNeeded()

热插拔数据流：
  CGDisplayRegisterReconfigurationCallback → DisplayManager.displayReconfigCallback
    → refreshDisplays()
    → arrangeExternalAboveBuiltin()
    → @Published displays 更新 → 全局 View 重渲染

虚拟显示器数据流（运行时，不持久化）：
  VirtualDisplayView → VirtualDisplayService.enableHiDPIVirtual()
    → CGVirtualDisplay(descriptor:) [主线程，vendorID=0xEEEE]
    → MirrorService.enableMirror() [后台，CGHelpers.runWithTimeout]
    → HiDPI 模式可用（重启后消失）
```
