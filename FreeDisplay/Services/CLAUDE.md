# Services — 业务逻辑层

> 系统框架交互层，无 UI。所有 Service 都是 `@MainActor` 单例（`static let shared`）。

## 职责

直接与 macOS 系统框架（IOKit、CoreGraphics、ScreenCaptureKit、ColorSync）交互，
为 Views/ViewModels 提供高层 API。

## 关键模式

- **单例 + @MainActor**: 所有 Service 标记 `@MainActor final class: ObservableObject, @unchecked Sendable`
- **DDC 通信**: DDCService 是所有外接显示器功能的底层依赖，Apple Silicon 用 IOAVService
- **Gamma table 唯一写入者**: GammaService 拥有 CGSetDisplayTransfer* 的写入权
  - BrightnessService 的软件亮度通过 GammaService 间接写入
  - ❌ 任何 Service/View 不要直接调 CGSetDisplayTransferByFormula/Table
- **CGHelpers.runWithTimeout**: 阻塞性 CG 调用（apply settings、enableMirror）必须用此包装

## 文件清单

| 文件 | 用途 |
|------|------|
| DDCService.swift | IOKit I2C / IOAVService DDC 通信底层 |
| DisplayManager.swift | 显示器枚举、刷新、跨 Service 协调 |
| BrightnessService.swift | 软件亮度（通过 GammaService 写入） |
| GammaService.swift | Gamma table 唯一写入者 |
| AutoBrightnessService.swift | 跟随内建屏亮度同步外接显示器（CoreDisplay API） |
| ResolutionService.swift | 分辨率/HiDPI 模式切换 |
| ArrangementService.swift | 显示器排列 |
| MirrorService.swift | 镜像模式 |
| HiDPIService.swift | HiDPI 检测与管理 |
| VirtualDisplayService.swift | CGVirtualDisplay 创建/销毁 |
| ColorProfileService.swift | ColorSync ICC Profile |
| NotchOverlayManager.swift | 刘海遮罩覆盖层 |
| SettingsService.swift | UserDefaults 持久化 |
| UpdateService.swift | 应用更新检测 |
| LaunchService.swift | 开机自启动 |
| CGHelpers.swift | CG 阻塞调用超时包装 |

## 跨 Service 规则

- **睡眠唤醒 reapply 顺序**: BrightnessService → GammaService（Brightness 是 Gamma 的数据提供方）
  - AppDelegate 监听 `NSWorkspace.didWakeNotification` → 调 reapply
- **C 回调**: 用 `Unmanaged.passRetained(self)` + 配对 `release()`，❌ 不要 passUnretained
- **VirtualDisplayService**: HiDPI 配置纯运行时（❌ 不存 UserDefaults autoCreate），
  `CGVirtualDisplay(descriptor:)` init 必须在主线程

## 测试注意

- DDC/IOKit 功能必须在实际外接显示器上手动测试
- VirtualDisplayService 创建后需验证 `CGVirtualDisplay` 非 nil（vendorID 必须非零）
