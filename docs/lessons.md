# 踩坑经验 — FreeDisplay

> 更新: 2026-03-03 (Phase 13-15 规划，新增性能与 HiDPI 教训)

## Xcode / 构建

- xcodegen 不自动生成 Info.plist → 必须在 project.yml 设置 `GENERATE_INFOPLIST_FILE: YES`
- ScreenCaptureKit（`SCShareableContent.current`）在 `@MainActor` 上下文调用会报 non-Sendable 错误（即使设了 `SWIFT_STRICT_CONCURRENCY: minimal`）→ 解法：`@preconcurrency import ScreenCaptureKit`
- Swift 6 strict concurrency 下 singleton 报 Sendable 错误 → 类标记 `@unchecked Sendable` + 项目设 `SWIFT_STRICT_CONCURRENCY: minimal`

## SwiftUI / MenuBarExtra

- MenuBarExtra 需要 `.menuBarExtraStyle(.window)` 才能显示自定义 SwiftUI 视图（默认是 menu style 只支持 Button/Toggle）
- 隐藏 Dock 图标：在 project.yml 设 `INFOPLIST_KEY_LSUIElement: true`，不需要在 AppDelegate 里手动设

## IOKit / 屏幕旋转（Phase 4）

- `CGDisplayIOServicePort` 在最新 macOS SDK 中已彻底 **unavailable**（非 deprecated），直接报错，必须用 IOKit registry 遍历代替
- 替代方式：遍历 `IODisplayConnect` → 用 vendor/model 匹配 → `IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent)` 得到 IOFramebuffer（与 DDCService.framebufferService 完全相同的模式）
- 屏幕旋转：`IORegistryEntrySetCFProperty(fb, "IOFBTransform", NSNumber(value: index))` + `IOServiceRequestProbe(fb, 0x00000400)` 触发；旋转 index = 0/1/2/3 对应 0°/90°/180°/270°
- `import IOKit.graphics` 对于 `IOServiceRequestProbe` 所需的图形常量是必要的

## IOKit / DDC

- `IODisplayCreateInfoDictionary` 返回的 CF 字典中，`DisplayVendorID` 和 `DisplayProductID` 是 `Int` 类型（非 `UInt32`），需要先试 UInt32 转型，再试 Int 转型
- `IODisplayCreateInfoDictionary` 返回 `Unmanaged<CFDictionary>?`，需要 `.takeRetainedValue()` 取值（ARC 管理）
- `IOServiceGetMatchingServices` 的 matching 参数会消耗 CFDictionary 的引用，不需要手动 release
- IOKit 的 I2C 子模块是 `explicit module`，`import IOKit` 不包含 → 需要 `import IOKit.i2c`（I2C 函数）和 `import IOKit.graphics`（IODisplay*FloatParameter 函数）
- `IOI2CRequest` 在 `#pragma pack(push, 4)` 结构体内，`sendTransactionType`/`replyTransactionType` 字段类型是 `IOOptionBits`（UInt32，非 UInt8）
- `kIODisplayBrightnessKey` 是 `#define "brightness"`，Swift 不会自动 bridge 字符串宏 → 直接用 `"brightness" as CFString`
- Swift 的 `Array.withUnsafeMutableBytes` 持有 exclusive mutable borrow，closure 内不能再下标访问原数组 → 改用 raw buffer pointer (`replyRaw.bindMemory(to: UInt8.self)`) 读取数据，或在 closure 外提前捕获 `.count`
- `IOFBCopyI2CInterfaceForBus(framebuffer, busIndex, &interface)` 是比手动查 IOFramebufferI2CInterface 子节点更干净的 API，推荐使用
- `BrightnessService` 方法若要访问 `@MainActor` 隔离的 `DisplayInfo` 属性，需标记为 `@MainActor`；实际 DDC I/O 由 DDCService 内部的 ddcQueue 异步执行，不阻塞 MainActor

## CoreGraphics / 显示器

- Swift 6 class init 中，如果有 `@Published` 属性尚未初始化，不能在初始化完成前用 `self.anyProperty`（即使该属性已赋值）→ 解法：用局部变量保存值再引用
- `CGDisplayRegisterReconfigurationCallback` 要求回调是 C 函数指针（全局 func），不能是 closure → 用 `userInfo` 传 `Unmanaged.passUnretained(self).toOpaque()`
- `deinit` 在 Swift 6 下是 nonisolated，不能访问 `@MainActor` 隔离的属性 → 解法：把需要在 deinit 访问的属性标记 `nonisolated(unsafe)`
- 新增 Swift 源文件后如果编译报"找不到符号"，需要重新运行 `xcodegen generate` 重生成 xcodeproj（即使 project.yml 用了 glob，老的 xcodeproj 可能没包含新文件）
- macOS 26.2 SDK 将 `CGDisplayModeGetWidth/Height/PixelWidth/PixelHeight/RefreshRate/IODisplayModeID` 等 C 函数全部替换为 Swift 属性（`mode.width`, `mode.pixelWidth`, `mode.ioDisplayModeID` 等）和方法（`mode.isUsableForDesktopGUI()`）→ 使用新 SDK 时直接用属性语法，避免 deprecated 函数
- `kCGDisplayShowDuplicateLowResolutionModes: true` 是正确键名，传入 `CGDisplayCopyAllDisplayModes` 的 options 字典可显示 HiDPI 缩放模式
- `CGDisplayCopyColorSpace` 在 macOS 26 SDK 返回非 Optional `CGColorSpace`（旧 SDK 返回 Optional）→ guard let 要改成直接调用，用 `colorSpace.name` 取名称（`CGColorSpaceCopyName` 已替换为属性）
- `CGDisplayMode.pixelEncoding` 是 `CFString?`（不是 `String`），需手动 bridge：`if let cfEnc = mode.pixelEncoding { encoding = cfEnc as String }`
- ColorSync 全局常量（`kColorSyncDisplayDeviceClass`、`kColorSyncDeviceDefaultProfileID`）在 Swift 6 中是 `Unmanaged<CFString>?` 类型，且全局 var 访问有并发安全警告 → 用 `@preconcurrency import ColorSync` 压制并发错误；访问时用 `.takeUnretainedValue()` 借用引用（不要 `takeRetainedValue` 以免双重释放）
- `kColorSyncProfileUseSystemSequence` 不存在于公开 ColorSync 头文件 → 重置为系统默认 profile 的 API 无法通过公开接口实现，略过 resetProfile
- 新增 Swift 源文件后必须重新运行 `xcodegen generate` 重生成 xcodeproj，否则新文件不会被编译器知道（"cannot find in scope" 错误）

## IOKit / 环境光传感器（Phase 11）

- `AppleLMUController` 是 IOKit 服务，通过 `IOServiceGetMatchingService` 获取；`IOServiceOpen` 打开连接后用 `IOConnectCallMethod(port, 0, nil, 0, nil, 0, &output, &outputCount, nil, &outputStructSize)` 读取两通道（左/右）传感器 UInt64 值
- `IOConnectCallMethod` 的 struct 大小参数是 `Int`（Swift 中 size_t = Int），不能传 `nil` → 必须传 `0` 或指向变量的指针（`&outputStructSize`）
- 新建 Swift 文件后，如果其他文件引用了新文件中的类型，必须先运行 `xcodegen generate` 重新生成 xcodeproj，否则"cannot find in scope"
- `@MainActor` class 的 `init` 内访问其他 `@MainActor` 类的属性时，`init` 需要也标记 `@MainActor`，否则 Swift 6 strict concurrency 报错

## Phase 12 / 收尾

- 新增服务/视图文件后必须运行 `xcodegen generate` 重新生成 xcodeproj，否则其他文件引用新类型会报 "cannot find in scope"
- Services 文件中如果使用了 `CGDirectDisplayID`，需要 `import CoreGraphics`（仅 `import Foundation` 不够）
- `NSWorkspace.shared` 需要 `import AppKit`（不能只用 Foundation）
- `NSObject` 子类做 singleton 时 Swift 6 会报 non-Sendable 警告 → 标记 `@unchecked Sendable` 解决
- `SMAppService`（开机自启动）在 macOS 13+ 可用，需要 `import ServiceManagement`

## UI 动画 / SwiftUI（Phase 12）

- `withAnimation(.easeInOut(duration: 0.2)) { state.toggle() }` 是触发展开/折叠动画的最简单方式，不需要 `.animation(_, value:)` 作用在整个容器上
- `.transition(.opacity.combined(with: .move(edge: .top)))` 用于展开内容的进出效果，视觉上像从按钮下方滑出
- 共享 icon 助手 `MenuItemIcon`（定义在 MenuBarView.swift）可在同一 Module 内所有 View 直接使用，不需要额外声明
- SwiftUI 中颜色语义化（绿色=保护/安全，红=流媒体，橙=亮度，灰=设置，紫=颜色管理）能有效传递功能语义，无需额外文字说明

## DDC 性能缓存（Phase 12）

- DDC I2C 读取延迟 50ms+，UI 重复触发读取会显著影响体验 → 用 `NSLock` + 字典缓存 + 5 秒 TTL 解决；写操作后立即失效对应缓存条目
- 缓存 key 为 `[CGDirectDisplayID: [UInt8: VCPCacheEntry]]` 双层字典，可按显示器和 VCP code 精确失效
- `NSLock.lock()` / `unlock()` 必须配对，建议用 `defer { lock.unlock() }` 但要注意提前 return 时 defer 会正确执行

## SwiftUI 性能

- `@Published` 属性变更会触发所有观察该 ObservableObject 的 View 重绘 → 拆分状态到多个小 ObservableObject 或用 `@State` 局部化
- View `body` 中不要放同步 IOKit/CG 调用（如 `CGDisplayCopyColorSpace`）→ 用 `@State` + `onAppear`/`task {}` 异步获取
- `isSwitching = true; syncCall(); isSwitching = false` 模式无效：SwiftUI 不会在同步代码中间渲染 → 必须用 async/await 让 SwiftUI 有机会重绘
- `@StateObject` 包装共享单例（`XXX.shared`）是反模式：每次 View 重建都可能创建新订阅 → 共享单例用 `@ObservedObject`
- `CGSetDisplayTransferByFormula` 设置的 gamma table 是内核级持久的，不会随 View 销毁自动恢复 → 必须在 `onDisappear` 和 app 退出时手动调 `CGDisplayRestoreColorSyncSettings()`

## HiDPI / 分辨率

- `HiDPIService` 写入 display override plist 后，macOS 不会立刻加载新模式 → 需要触发显示器重新枚举（`CGDisplayForceToMirror` 或 `IOServiceRequestProbe`）
- `isUsableForDesktopGUI()` 会过滤掉部分分辨率模式，导致某些分辨率"看不到" → 可能需要绕过此过滤

## CGVirtualDisplay / 虚拟显示器

- `CGVirtualDisplay`、`CGVirtualDisplayDescriptor`、`CGVirtualDisplaySettings`、`CGVirtualDisplayMode` 是 CoreGraphics 的私有 SPI，虽然符号已导出到 TBD 文件（`grep CGVirtualDisplay CoreGraphics.tbd`），但在 macOS 26 SDK 的公开 C/ObjC 头文件和 Swift interface 文件中均未声明 → Swift 直接引用会报 "cannot find type in scope" 错误
- BetterDisplay/BetterDummy 通过自行声明私有接口头文件（bridging header）来使用这些类 → 属于私有 API 使用，需要项目明确决策是否接受此风险
- 如果被要求解决后才继续，先读 BLOCKING.md B-002
