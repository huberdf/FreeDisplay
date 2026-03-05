# 踩坑经验 — CoreGraphics

> 更新: 2026-03-05

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

## HiDPI / 分辨率

- `HiDPIService` 写入 display override plist 后，macOS 不会立刻加载新模式 → 需要触发显示器重新枚举（`CGDisplayForceToMirror` 或 `IOServiceRequestProbe`）
- `isUsableForDesktopGUI()` 会过滤掉部分分辨率模式，导致某些分辨率"看不到" → 可能需要绕过此过滤

### L-006: macOS 14+ plist 注入无法动态启用 HiDPI
- **现象**: 写入 display override plist + IOServiceRequestProbe 后，2K 外接显示器不出现 HiDPI 模式
- **原因**: macOS Ventura/Sonoma 不会为已连接的显示器动态重新枚举 plist 注入的模式。plist 方案只在显示器首次连接时有效
- **解法**: 使用 CGVirtualDisplay 私有 API 创建 3840x2160 虚拟显示器（hiDPI=1），然后镜像物理显示器到虚拟显示器，macOS 自动提供 1920x1080@2x 等 HiDPI 模式
- **教训**: BetterDisplay 的 HiDPI 方案核心是"虚拟显示器 + 镜像"，不是 plist 注入
- **日期**: 2026-03-03

### L-007: NSWindow.isReleasedWhenClosed 默认为 true
- **现象**: 刘海屏 overlay 关闭时 app 崩溃/卡死
- **原因**: NSWindow 默认 `isReleasedWhenClosed = true`，close() 后 window 立即被 ARC 释放，字典中的引用变成悬空指针
- **解法**: 创建 NSWindow 后立即设置 `isReleasedWhenClosed = false`
- **教训**: 项目中其他窗口（PiPWindow、StreamWindow、VideoFilterWindow）都正确设置了此属性，唯独 NotchOverlayManager 漏了
- **日期**: 2026-03-03

## CGVirtualDisplay / 虚拟显示器

- `CGVirtualDisplay`、`CGVirtualDisplayDescriptor`、`CGVirtualDisplaySettings`、`CGVirtualDisplayMode` 是 CoreGraphics 的私有 SPI，虽然符号已导出到 TBD 文件（`grep CGVirtualDisplay CoreGraphics.tbd`），但在 macOS 26 SDK 的公开 C/ObjC 头文件和 Swift interface 文件中均未声明 → Swift 直接引用会报 "cannot find type in scope" 错误
- BetterDisplay/BetterDummy 通过自行声明私有接口头文件（bridging header）来使用这些类 → 属于私有 API 使用，需要项目明确决策是否接受此风险
- 如果被要求解决后才继续，先读 BLOCKING.md B-002

### L-020: CGVirtualDisplay vendorID 必须非零
- **现象**: `CGVirtualDisplay(descriptor:)` 始终返回 nil，无报错
- **原因**: `vendorID = 0` 被 WindowServer 拒绝，参考 node-mac-virtual-display 项目使用 `0xEEEE`
- **解法**: 设 `vendorID = 0xEEEE`，`productID = 0x0001`，`serialNum = 0x0001`
- **教训**: 私有 API 的隐含约束无文档，必须参考已知可运行的开源实现
- **日期**: 2026-03-04

### L-021: CGVirtualDisplay(descriptor:) 必须在主线程
- **现象**: 后台 DispatchQueue 调用返回 nil，主线程调用成功
- **原因**: WindowServer IPC 要求 CGVirtualDisplay 初始化在主线程
- **解法**: descriptor 构建 + init 在 @MainActor，`apply(settings)` 和 `enableMirror` 通过 `runWithTimeout` 在后台
- **教训**: 同一个 API 的不同方法可能有不同的线程要求
- **日期**: 2026-03-04

### L-022: 桥接头属性名必须与运行时 API 精确匹配
- **现象**: `-[CGVirtualDisplayDescriptor setMaxPixelSize:]: unrecognized selector` 导致闪退
- **原因**: 桥接头声明了 `maxPixelSize` (CGSize)，但实际属性名是 `maxPixelsWide`/`maxPixelsHigh` (uint32_t)
- **解法**: 以 Chromium `virtual_display_mac_util.mm` 为权威参考，逐个验证属性名
- **教训**: 私有 API 桥接头不能猜测属性名，必须参考逆向工程或已知可运行的实现
- **日期**: 2026-03-04

### L-023: HiDPI 虚拟显示器配置不能 autoCreate
- **现象**: 每次重启 app，stale 虚拟显示器堆积（displayID=7,8,9,10...），最终创建失败
- **原因**: HiDPI config 存入了 configs 数组并设 `autoCreate: true`，但 autoCreate 只创建虚拟显示器不做镜像，导致无用的虚拟显示器堆积
- **解法**: HiDPI 配置纯运行时（`autoCreate: false`，不存入 configs），启动时清理历史遗留
- **教训**: 依赖运行时状态（如镜像关系）的配置不应自动重建——重建后缺失关键上下文
- **日期**: 2026-03-04

### L-024: CGDisplayMirrorsDisplay() 检测不可靠
- **现象**: HiDPI 模式下切换分辨率失败，`CGDisplayMirrorsDisplay(physicalID)` 返回 `kCGNullDirectDisplay`
- **原因**: macOS 的镜像检测 API 不总是能识别通过 `CGConfigureDisplayMirrorOfDisplay` 设置的镜像关系
- **解法**: 在 `resolvedTargetDisplayID()` 中添加 `VirtualDisplayService.virtualDisplayID(for:)` 作为 fallback
- **教训**: 系统 API 的行为可能与文档不一致，需要备选方案
- **日期**: 2026-03-04

### L-025: HiDPI 方案选择 — 镜像是死路，plist override 才是正道
- **现象**: 用 CGConfigureDisplayMirrorOfDisplay 创建虚拟显示器→镜像到外接屏以获得 HiDPI 模式，结果触发系统"屏幕镜像"UI + 鼠标跨屏卡顿 + 纯镜像模式
- **原因**: Apple Silicon 的 WindowServer 对硬件镜像有严格管理，CGConfigureDisplayMirrorOfDisplay 会触发完整的镜像重配置流程
- **解法**: 改用 plist override（写 /Library/Displays/Contents/Resources/Overrides/），这是 BetterDisplay 的方案。需要管理员权限（NSAppleScript "with administrator privileges"），启用后重连显示器生效
- **教训**: 不要用 CGConfigureDisplayMirrorOfDisplay 做 HiDPI，这在 Apple Silicon 上是死路

### L-026: 私有框架符号加载 — dlsym 而非 @_silgen_name
- **现象**: 用 @_silgen_name("CoreDisplay_Display_GetUserBrightness") 声明私有函数，编译通过但链接失败（undefined symbol）
- **原因**: @_silgen_name 需要符号在链接时可见，CoreDisplay 是私有框架不在默认链接路径
- **解法**: dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY) + dlsym 运行时加载
- **教训**: 私有框架的符号一律用 dlopen+dlsym，不要用 @_silgen_name

### L-027: display.pixelWidth 是当前分辨率，不是原生分辨率
- **现象**: HiDPI plist override 的 scale-resolutions 为空数组
- **原因**: 用 display.pixelWidth/pixelHeight（来自 CGDisplayPixelsWide/High）作为原生分辨率传入，但显示器当前可能在非原生分辨率
- **解法**: 用 display.availableModes.max(by: width*height) 获取最大可用模式作为原生分辨率
- **教训**: CGDisplayPixelsWide/High 返回的是当前模式的像素尺寸，不是面板物理分辨率
