# FreeDisplay — Claude 上下文入口

> 版本: 2026-03-05 | 状态: Phase 22 完成

## 这个项目是什么

BetterDisplay 的免费开源替代品。macOS 菜单栏应用，管理显示器：DDC 亮度/对比度控制、分辨率/HiDPI 管理、显示器排列、色彩管理、虚拟显示器。
技术栈：Swift 6 + SwiftUI (MenuBarExtra) + IOKit + CoreGraphics，零第三方依赖。

## 快速导航（按需加载）

| 需要做什么 | 读哪个文件 |
|-----------|-----------|
| **开工前检查阻塞问题** | `docs/BLOCKING.md` |
| 了解代码结构、找文件 | `docs/codemap/CLAUDE.md`（索引）→ `docs/codemap/file-tree.md`（文件树）→ `docs/codemap/relationships.md`（关系图） |
| 查看项目规划、当前进度 | `docs/roadmap/CLAUDE.md`（总览）→ `docs/roadmap/phase-N.md`（详情） |
| 查看工作习惯/偏好 | `docs/habits.md` |
| 查看踩坑经验/教训 | `docs/lessons/CLAUDE.md`（索引）→ `docs/lessons/{topic}.md`（详情） |

## 当前焦点

- **当前阶段**: Phase 22 已完成。功能精简（删除旋转/串流/PiP/镜像/配置保护等）+ 自动亮度重写 + HiDPI plist override 实现。
- **禁止动的地方**: `docs/roadmap/` 不要改结构（planner 产出），只更新 `[x]` 进度标记
- **最近变更**: Phase 21 功能精简（删除 15+ 文件）、Phase 22 自动亮度重写（CoreDisplay dlsym）、HiDPI 从镜像方案改为 plist override、排列居中对齐修复、HiDPI 预设

## 自主决策规则

> **阻塞优先（开工第一件事）：**
- 每次开始 → 先读 `docs/BLOCKING.md` → 有 P0/P1 先解决 → 全清才做 ROADMAP
- 遇到搞不定的问题 → 加到 `docs/BLOCKING.md`

> **联动规则：**
- 改了 `DisplayInfo` 的属性 → grep 所有引用点同步更新
- 改了 `project.yml` → 必须 `xcodegen generate` 重新生成 xcodeproj
- 新增 Service/View 文件 → 更新 `docs/codemap/file-tree.md`

> **修复/开发类：**
- 编译失败 → 先修到通过，不跳过
- Swift 6 并发报错 → 用 `@MainActor` 或 `@unchecked Sendable`（项目已设 `SWIFT_STRICT_CONCURRENCY: minimal`）
- 新增文件不需要改 project.yml（xcodegen 自动包含 FreeDisplay/ 下所有源文件）

> **SwiftUI 组件规则：**
- 需要本地状态（isHovered、isLoading）的行组件 → 必须是独立 `struct`，❌ 不能是 `@ViewBuilder` 函数（@ViewBuilder 函数不支持 @State）
- 可复用的行组件统一命名：`XxxRow`（如 DetailRow、ExpandableRow、ProtectionRowView）

> **UserDefaults key 命名规范：**
- 所有 UserDefaults key 必须加 `fd.` 前缀（如 `fd.launchAtLogin`、`fd.AutoBrightnessEnabled`）
- ❌ 裸 key（如 `"launchAtLogin"`）可能与系统或第三方 key 冲突

> **跨 Service 写共享资源的协调原则：**
- 两个 Service 不能各自独立写同一个 CoreGraphics 资源（如 gamma table）→ 指定一个 Service 作为所有者负责最终写入
- BrightnessService（软件亮度）通过 GammaService 写 transfer function，不直接写 CGSetDisplayTransferByTable
- ❌ View 层直接调 `CGSetDisplayTransferByFormula/Table`（绕过 GammaService）→ ✅ 通过 `GammaService.apply()` 或 `GammaService.resetSingleDisplay()` 间接操作
- ❌ `CGDisplayRestoreColorSyncSettings()`（全局）→ ✅ `GammaService.resetSingleDisplay(displayID)` 只重置单个显示器

> **睡眠/唤醒处理（必须）：**
- 写 display 硬件状态的 Service（gamma、软件亮度）必须响应 `NSWorkspace.didWakeNotification` 重新应用
- 已注册：AppDelegate 监听唤醒 → GammaService.reapplyIfNeeded + BrightnessService.reapplySoftwareBrightnessIfNeeded

> **C 回调 Unmanaged 规则：**
- 长期 C 回调（CGDisplayRegisterReconfigurationCallback 等）→ 必须用 `Unmanaged.passRetained(self)`，注销时 `release()`
- ❌ `passUnretained`（野指针风险）

> **IOKit 显示器匹配：**
- 不要用 CGDisplayVendorNumber/ModelNumber 匹配 IOKit 服务（对部分显示器不可靠）
- 显示器名称用 `NSScreen.localizedName`
- IOKit 服务查找用 IOServiceGetMatchingServices 枚举 IODisplayConnect（❌ CGDisplayIOServicePort 已弃用）
- DDC 外接亮度控制不一定可用 → UI 需要优雅降级（检测失败时提示用户）

> **异步化原则：**
- 只对真正慢的操作做 async（文件系统扫描、网络请求）
- 微秒级 IOKit 调用（名称查找、属性读取）保持同步，不值得 async 化

> **CGVirtualDisplay 私有 API（必须遵守）：**
- `vendorID` 必须非零（如 `0xEEEE`），为 0 时 `CGVirtualDisplay(descriptor:)` 返回 nil
- `CGVirtualDisplay(descriptor:)` 必须在主线程调用（后台线程返回 nil），`apply(settings)` 可在后台
- 桥接头属性名以 Chromium `virtual_display_mac_util.mm` 为准（`maxPixelsWide`/`maxPixelsHigh` 非 `maxPixelSize`）

> **HiDPI 实现方式（必须遵守）：**
- ❌ `CGConfigureDisplayMirrorOfDisplay` 做 HiDPI — Apple Silicon 上会触发硬件镜像模式 + 鼠标卡顿
- ✅ Plist override 写入 `/Library/Displays/Contents/Resources/Overrides/` — BetterDisplay 同款方案
- 写 plist 需管理员权限 → 用 `NSAppleScript("do shell script ... with administrator privileges")`
- ❌ plist 中设 `DisplayProductName` — 会覆盖系统显示器名称
- 启用后需重新连接显示器才生效（IOServiceRequestProbe 不一定可靠）

> **私有框架动态加载：**
- ❌ `@_silgen_name` 引用私有框架符号（链接时 undefined symbol）
- ✅ `dlopen` + `dlsym` 运行时加载（如 CoreDisplay_Display_GetUserBrightness）

> **停下来问用户：**
- 需要使用私有 API（CoreDisplay 等）
- 需要 SIP 关闭或特殊系统权限
- 架构方向变更（MVVM→其他）

> **自维护规则：**
- 增删改文件 → 更新 `docs/codemap/file-tree.md`
- Phase 任务完成 → 在 `docs/roadmap/phase-N.md` 标 `[x]` **且同步在 `docs/ROADMAP.md` 标 `[x]`**（autopilot 靠后者追踪进度）
- 踩了坑 → 写到 `docs/lessons/{topic}.md`（同步更新 `docs/lessons/CLAUDE.md` 索引）
- 发现偏好/模式 → 写到 `docs/habits.md`
- 遇到卡住 → 加到 `docs/BLOCKING.md`
- 解决了 BLOCKING → 移到已解决区

## 验证链（每次改完必跑）

```bash
# 1. 编译检查
cd ~/Desktop/FreeDisplay && xcodebuild -scheme FreeDisplay -configuration Debug build 2>&1 | tail -5

# 2. 联动检查（改了接口/模型时）
grep -r "DisplayInfo\|DisplayManager\|DDCService" FreeDisplay/ --include="*.swift" | grep -v "^Binary"
```

## 常见操作 Playbook

### 新增功能 Section（Phase 2-12 最常用操作）
1. 在 `Services/` 创建新 Service（如 `BrightnessService.swift`）
2. 在 `Views/` 创建对应 View（如 `BrightnessSliderView.swift`）
3. 如有状态管理需求，在 `ViewModels/` 创建 ViewModel
4. 在 `MenuBarView.swift` 中嵌入新 View
5. 更新 `DisplayInfo.swift` 添加需要的属性
6. 跑验证链

### 实现 DDC 功能
1. 在 `DDCService.swift` 实现 IOKit I2C 通信
2. 新功能的 VCP code 查 DDC/CI 标准（如 0x10=亮度）
3. Service 中调用 `DDCService.shared.read/write`
4. 跑验证链 + 在实际外接显示器上手动测试

### 修 Bug
1. 确认是编译错误还是运行时错误
2. 编译错误 → 看 xcodebuild 输出定位
3. 运行时错误 → Console.app 查日志或 Xcode debugger
4. 修复 → 跑验证链

## 设计资源

- **App 图标设计**: 使用 [Nano Banana](https://nano-banana.ai/)（Google Gemini 驱动的 AI 图像生成器）生成高质量图标
  - 支持文字描述生成图标、Logo、UI 元素
  - 生成后用 Python PIL 裁剪/缩放为 macOS 所需的多尺寸 PNG（16/32/64/128/256/512/1024）
  - 图标文件位于 `FreeDisplay/Assets.xcassets/AppIcon.appiconset/`

## 关键约定

- **语言**: Swift 6.0（并发检查 minimal）
- **最低系统**: macOS 14.0
- **架构**: MVVM（View → ViewModel → Service）
- **构建**: `xcodegen generate && xcodebuild -scheme FreeDisplay -configuration Debug build`
- **无 Sandbox**: entitlements 已关闭 App Sandbox（DDC/IOKit 需要）
- **无第三方依赖**: 全部用系统框架

## 核心框架

| 框架 | 用途 | Phase |
|------|------|-------|
| CoreGraphics | 显示器枚举、分辨率、排列 | 1-4 |
| IOKit | DDC/CI I2C 通信、亮度/对比度 | 2 |
| ColorSync | ICC Profile 管理 | 5 |
| CoreGraphics (CGVirtualDisplay) | 虚拟显示器 | 10 |
| CoreDisplay (dlsym) | 内建屏亮度读取 | 22 |
