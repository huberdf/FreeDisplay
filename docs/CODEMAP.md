# Code Map — FreeDisplay

> **用途**: 这是 Claude 的代码导航地图。读完这个文件，就知道去哪找什么。
> **维护**: 重大结构变更后更新描述和模块关系图。

---

## 入口文件 / Key Entry Points

- `CLAUDE.md`
- `docs/CODEMAP.md`
- `docs/roadmap/CLAUDE.md`

---

## 目录结构 / File Tree

```
FreeDisplay/
├── docs/                           # 项目文档目录
│   ├── roadmap/                    # Phase 规划文档（planner 产出，不要手改结构）
│   │   ├── CLAUDE.md               # roadmap 总览与当前阶段说明
│   │   ├── phase-0.md              # Phase 0: 基础脚手架
│   │   ├── phase-1.md              # Phase 1: 显示器枚举 + 菜单栏入口
│   │   ├── phase-2.md              # Phase 2: DDC 亮度/对比度控制
│   │   ├── phase-3.md              # Phase 3: 分辨率切换
│   │   ├── phase-4.md              # Phase 4: 旋转 + 排列
│   │   ├── phase-5.md              # Phase 5: 色彩管理（ICC Profile）
│   │   ├── phase-6.md              # Phase 6: 图像调整（Gamma/软件滤镜）
│   │   ├── phase-7.md              # Phase 7: 显示器高级管理
│   │   ├── phase-8.md              # Phase 8: 屏幕镜像
│   │   ├── phase-9.md              # Phase 9: 屏幕串流 + 画中画
│   │   ├── phase-10.md             # Phase 10: 虚拟显示器
│   │   ├── phase-11.md             # Phase 11: 自动亮度 + 配置保护
│   │   ├── phase-12.md             # Phase 12: 系统颜色取色器 + 视频滤镜 + 设置
│   │   ├── phase-13.md             # Phase 13: 关键 Bug 修复（当前阶段）
│   │   ├── phase-14.md             # Phase 14: 性能优化
│   │   └── phase-15.md             # Phase 15: 其他增强
│   ├── BLOCKING.md                 # 阻塞问题追踪（开工前必读）
│   ├── CODEMAP.md                  # 本文件，代码导航地图
│   ├── habits.md                   # 开发偏好与工作习惯记录
│   ├── lessons.md                  # 踩坑经验与教训
│   └── ROADMAP.md                  # 总体进度追踪（autopilot 靠此追踪 [x] 标记）
├── FreeDisplay/                    # Swift 源码目录（xcodegen 自动包含所有 .swift）
│   ├── App/                        # 应用入口，SwiftUI App 生命周期
│   │   ├── AppDelegate.swift       # NSApplicationDelegate，确保仅在菜单栏显示；改动影响 App 生命周期钩子
│   │   └── FreeDisplayApp.swift    # @main 入口，创建 DisplayManager 并挂载 MenuBarView；改动影响整个 App 初始化链
│   ├── Models/                     # 数据模型层（纯数据，无副作用）
│   │   ├── DisplayInfo.swift       # ⚠️ 核心显示器模型，12+ @Published 属性；所有 View/Service 均依赖此类，属性增删需全局 grep 同步
│   │   └── DisplayMode.swift       # 单个显示模式（分辨率+刷新率+HiDPI 标志）的值类型；枚举逻辑改动影响分辨率切换和模式列表展示
│   ├── Services/                   # 业务逻辑层，与系统框架直接交互
│   │   ├── ArrangementService.swift        # 通过 CGDisplayConfiguration 读写显示器位置，支持设为主显示器；改动影响拖拽排列和主显示器切换
│   │   ├── AutoBrightnessService.swift     # 读取 IOKit AppleLMUController 环境光传感器，定时轮询映射 lux→亮度；改动影响自动亮度精度和电池消耗
│   │   ├── BrightnessService.swift         # 统一亮度接口：内建屏用 IODisplayGetFloatParameter，外接屏用 DDC VCP 0x10；改动影响所有亮度读写路径
│   │   ├── ColorProfileService.swift       # ICC Profile 枚举（扫描 3 个系统目录）和切换（ColorSync API）；改动影响色彩描述文件列表和切换
│   │   ├── ConfigProtectionService.swift (11KB) # 显示器配置快照保存/恢复 + CGDisplay 重配置回调监控；改动影响配置保护逻辑和快照 JSON 格式
│   │   ├── DDCService.swift (12KB)         # ⚠️ IOKit I2C DDC/CI 通信核心：IOFramebuffer 查找、VCP 读写、5 秒 TTL 缓存、3 次重试；几乎所有外接显示器功能的底层依赖，改动需极谨慎
│   │   ├── DisplayManager.swift            # ⚠️ 显示器枚举（CGGetOnlineDisplayList）+ CGDisplay 热插拔回调；@Published displays 被全局注入，改动影响整个显示器列表数据流
│   │   ├── GammaService.swift (8KB)        # 软件 Gamma 调整：CGSetDisplayTransferByFormula/Table，支持对比度/增益/色温/量化/反色；改动影响图像调整效果
│   │   ├── HiDPIService.swift              # 写 /Library/Displays/...plist 注入 HiDPI 缩放模式，需管理员权限；改动影响 HiDPI override 生成逻辑
│   │   ├── LaunchService.swift             # SMAppService 管理开机自启动（macOS 13+）；改动仅影响 Launch at Login 功能
│   │   ├── MirrorService.swift             # CGDisplayConfiguration 硬件级屏幕镜像的启用/停止；改动影响镜像功能
│   │   ├── NotchOverlayManager.swift       # 在内建屏刘海区域创建黑色遮罩 NSWindow（screenSaver 级别）；改动影响刘海遮罩的视觉效果和层级
│   │   ├── ResolutionService.swift         # 通过 CGConfigureDisplayWithDisplayMode 切换显示模式；改动影响分辨率切换成功率
│   │   ├── RotationService.swift           # IOKit IOFBTransform 设置屏幕旋转（0/90/180/270°）；Registry 查找逻辑与 DDCService 相同，改动需同步
│   │   ├── ScreenCaptureService.swift      # ScreenCaptureKit SCStream 捕获单显示器帧流，@Published latestFrame；改动影响串流质量和延迟
│   │   ├── SettingsService.swift           # UserDefaults + JSON 文件持久化全局和每显示器设置；改动需注意 key 命名冲突和向后兼容
│   │   ├── UpdateService.swift             # GitHub Releases API 检查新版本，语义化版本比较；改动影响更新检查逻辑
│   │   ├── VirtualDisplayService.swift     # 虚拟显示器配置管理（BLOCKING B-002: CGVirtualDisplay 私有 API 未启用，create 始终返回 false）；实际创建功能尚未可用
│   │   └── VisualIdentificationManager.swift # 在目标显示器全屏展示识别 overlay（3 秒自动消失）；改动影响视觉识别 UI
│   ├── Utilities/                  # 工具扩展
│   │   └── NSScreenExtension.swift         # NSScreen 扩展：按 CGDirectDisplayID 查找 NSScreen，获取 displayID；被 NotchView、NotchOverlayManager、VisualIdentificationManager 依赖
│   ├── ViewModels/                 # ViewModel 层（目前仅串流功能有独立 ViewModel）
│   │   └── StreamViewModel.swift           # 管理单显示器串流状态（StreamConfig）和帧处理（旋转/翻转/裁剪/滤镜）；改动影响所有串流和画中画的图像处理逻辑
│   └── Views/                      # SwiftUI 视图层
│       ├── ArrangementView.swift           # 多显示器拖拽排列画布 + 设为主显示器按钮；依赖 ArrangementService
│       ├── AutoBrightnessView.swift        # 自动亮度开关 + 灵敏度滑块 + 环境光 lux 显示；依赖 AutoBrightnessService
│       ├── BrightnessSliderView.swift      # 单显示器亮度滑块（200ms 去抖）+ 全局组合亮度控制；依赖 BrightnessService + DDCService
│       ├── ColorModeView.swift             # 帧缓存类型选择（标准/反色/灰阶），通过 CoreGraphics Gamma 实现；改动影响色彩模式切换效果
│       ├── ColorProfileView.swift          # ICC Profile 列表（推荐/全部分组）和切换；依赖 ColorProfileService
│       ├── ConfigProtectionView.swift      # 每显示器配置锁定开关（10 项）+ 快照保存/恢复/删除；依赖 ConfigProtectionService
│       ├── DisplayDetailView.swift (15KB)  # ⚠️ 每显示器展开面板，12 个可折叠 Section 的容器；新增/删除 Section 都要改此文件，且需同步 MenuBarView
│       ├── DisplayModeListView.swift       # 分辨率模式列表（HiDPI/原生/其他分组）、收藏星标、点击切换；依赖 ResolutionService
│       ├── ImageAdjustmentView.swift (8KB) # 11 个图像调整滑块（对比度/Gamma/增益/色温/各通道/量化/反色）；依赖 GammaService
│       ├── IntegratedControlView.swift     # DDC VCP 批量读取并展示原始值（仅外接显示器可用）；依赖 DDCService.readBatchVCPCodes
│       ├── MainDisplayView.swift           # "设为主显示屏"行，当前已是主屏时显示状态标签；依赖 ArrangementService
│       ├── ManageDisplayView.swift         # 系统显示设置跳转 + 视觉识别 + IOPMAssertion 防休眠；依赖 VisualIdentificationManager
│       ├── MenuBarView.swift (13KB)        # ⚠️ 菜单栏主视图：显示器列表 + 展开/折叠 + 工具区 + 设置区；是所有功能的入口容器，改动影响全局布局
│       ├── MirrorView.swift                # 屏幕镜像目标选择和停止；依赖 MirrorService
│       ├── NotchView.swift                 # 刘海信息显示 + 遮罩开关（仅有刘海的内建屏显示）；依赖 NotchOverlayManager
│       ├── PiPControlView.swift (11KB)     # 画中画开关 + 完整选项（层级/标题栏/移动/调整/吸附/鼠标穿透/翻转/旋转/滤镜/透明度）；依赖 PiPWindow + StreamViewModel
│       ├── PiPWindow.swift                 # PiPWindowController（NSWindow 管理）+ PiPNSWindow（四分之一吸附）+ PiPWindowLevel 枚举；改动影响画中画窗口行为
│       ├── ResolutionSliderView.swift      # 分辨率横向拖动滑块（松手生效）；依赖 ResolutionService，读取 DisplayInfo.availableModes
│       ├── RotationView.swift              # 旋转选项按钮（0/90/180/270°）；依赖 RotationService，写入 DisplayInfo.rotation
│       ├── StreamControlView.swift (8KB)   # 串流开始/停止 + 选项（指针/翻转/旋转/裁剪/滤镜/透明度）；依赖 StreamViewModel + StreamWindow
│       ├── StreamWindow.swift              # StreamWindowController（NSWindow）+ StreamContentView + CIImageDisplayView（Metal 渲染）；改动影响串流窗口渲染性能
│       ├── SystemColorView.swift (7KB)     # 系统取色器（NSColorSampler）+ HEX/RGB/HSB 显示 + 历史记录；依赖 SettingsService 持久化颜色历史
│       ├── VideoFilterWindow.swift (10KB)  # 独立视频滤镜预览窗口（8 种 CIFilter）+ 强度滑块 + 菜单栏入口；改动影响滤镜预览和滤镜库
│       └── VirtualDisplayView.swift        # 虚拟显示器配置列表 + 创建表单（预设分辨率）；依赖 VirtualDisplayService（实际创建功能受 BLOCKING B-002 限制）
├── FreeDisplay.xcodeproj/          # Xcode 项目文件（由 xcodegen 生成，不要手动编辑）
├── .gitignore                      # Git 忽略规则
├── build.sh                        # 快速构建脚本
├── CLAUDE.md                       # Claude 上下文入口（项目规则、决策约定）
└── project.yml                     # xcodegen 配置，改动后必须重新运行 xcodegen generate
```

---

## 模块说明 / Module Descriptions

| 模块 | 职责 | 关键文件 | 注意事项 |
|------|------|---------|---------|
| **App** | 应用生命周期、MenuBarExtra 场景声明 | `FreeDisplayApp.swift` | DisplayManager 在此创建并注入 environmentObject |
| **Models** | 纯数据结构，ObservableObject | `DisplayInfo.swift`, `DisplayMode.swift` | 改 DisplayInfo 属性必须全局 grep 同步 |
| **Services** | 系统框架交互，无 UI | `DDCService.swift`, `DisplayManager.swift`, `BrightnessService.swift` 等 | 大多数 Service 是 @MainActor 单例 |
| **ViewModels** | 串流状态 + 帧处理逻辑 | `StreamViewModel.swift` | 目前只有串流功能有独立 ViewModel |
| **Views** | SwiftUI 视图，纯展示和交互 | `MenuBarView.swift`, `DisplayDetailView.swift` | 不要在 View 里写业务逻辑，调 Service |
| **Utilities** | 系统类型扩展 | `NSScreenExtension.swift` | 被多处依赖，轻易不改 |

---

## 模块关系图 / Module Relationship Diagram

```
App (FreeDisplayApp)
  └── @StateObject DisplayManager
        └── @Published [DisplayInfo]
              └── MenuBarView (@EnvironmentObject DisplayManager)
                    ├── DisplayRowView
                    │     └── DisplayDetailView  ← 12 Sections
                    │           ├── BrightnessSliderView     → BrightnessService → DDCService
                    │           ├── ResolutionSliderView     → ResolutionService
                    │           ├── DisplayModeListView      → ResolutionService
                    │           ├── RotationView             → RotationService
                    │           ├── ColorProfileView         → ColorProfileService
                    │           ├── ColorModeView            → GammaService (CGSetDisplayTransfer)
                    │           ├── ImageAdjustmentView      → GammaService
                    │           ├── MainDisplayView          → ArrangementService
                    │           ├── NotchView                → NotchOverlayManager
                    │           ├── IntegratedControlView    → DDCService
                    │           ├── ManageDisplayView        → VisualIdentificationManager
                    │           ├── MirrorView               → MirrorService
                    │           ├── StreamControlView        → StreamViewModel → ScreenCaptureService
                    │           │                                             └── StreamWindow (NSWindow)
                    │           ├── PiPControlView           → StreamViewModel → ScreenCaptureService
                    │           │                                             └── PiPWindow (NSWindow)
                    │           ├── HiDPIVirtualRowView      → VirtualDisplayService
                    │           └── ConfigProtectionView     → ConfigProtectionService
                    ├── ArrangementView          → ArrangementService
                    ├── VirtualDisplayView       → VirtualDisplayService
                    ├── AutoBrightnessView       → AutoBrightnessService → BrightnessService
                    ├── VideoFilterMenuEntry     → VideoFilterWindowController (NSWindow)
                    ├── SystemColorMenuEntry     → SystemColorView → SettingsService
                    └── SettingsView             → SettingsService, LaunchService

Services 层内部依赖：
  BrightnessService ──────────→ DDCService (外接屏)
  AutoBrightnessService ──────→ BrightnessService
  ConfigProtectionService ────→ ResolutionService, RotationService
  RotationService ────────────→ IOKit (与 DDCService 相同的 IOFramebuffer 查找逻辑)
  DisplayManager ─────────────→ BrightnessService (刷新时异步初始化亮度)
                 ─────────────→ ArrangementService (setAsMainDisplay)

数据流（单向）：
  CGDisplayAPI / IOKit → Services → DisplayInfo (@Published) → Views (reactive)
  User interaction    → Views   → Services → Hardware
```

---

## 高风险文件 / High-Risk Files ⚠️

| 文件 | 风险原因 | 改动必做 |
|------|---------|---------|
| `Models/DisplayInfo.swift` | 12+ @Published 属性，所有 View 和 Service 均依赖 | grep 所有引用点同步更新 |
| `Services/DisplayManager.swift` | @Published displays 全局注入，热插拔回调 | 修改后验证热插拔、多显示器枚举 |
| `Services/DDCService.swift` | IOKit I2C 底层通信，外接显示器所有功能的基础 | 必须在实际外接显示器上手动测试 |
| `Views/MenuBarView.swift` | 所有功能的入口容器，嵌套所有 Section 入口 | 新增 Section 后检查布局和滚动高度 |
| `Views/DisplayDetailView.swift` | 12 个 Section 的展开容器，状态变量多 | 新增 Section 时注意 @State 命名不冲突 |

---

## 注意事项 / Pitfalls

- **DisplayInfo 属性联动**：改了 `DisplayInfo` 的属性 → grep 所有引用点同步更新，否则编译可能通过但逻辑错误
- **IOFramebuffer 查找重复**：`DDCService` 和 `RotationService` 各自实现了相同的 IOKit Registry 遍历逻辑，未来如需修改需同步两处
- **project.yml**：改了 `project.yml` → 必须 `xcodegen generate` 重新生成 xcodeproj，否则 Xcode 用旧配置
- **新增源文件**：`FreeDisplay/` 目录下所有 `.swift` 文件 xcodegen 自动包含，不需要改 `project.yml`
- **Swift 6 并发**：项目设 `SWIFT_STRICT_CONCURRENCY: minimal`，并发报错用 `@MainActor` 或 `@unchecked Sendable` 处理
- **无 Sandbox**：entitlements 已关闭 App Sandbox，IOKit / /Library/Displays 等直接访问可用，但 App Store 分发不可能
- **VirtualDisplayService 限制**：`create()` 和 `enableHiDPIVirtual()` 始终返回 false，见 `docs/BLOCKING.md` B-002
- **HiDPIService 权限**：写 `/Library/Displays/` 需要管理员权限，无权限时返回错误字符串供 UI 展示

---

## 常见任务 → 修改哪些文件 / Task Reference Table

| 任务 | 需要修改的文件 |
|------|--------------|
| 新增一个显示器属性（如 HDR 状态） | `Models/DisplayInfo.swift` → grep 所有引用 → 相关 View/Service |
| 新增一个 DDC VCP 功能（如音量控制） | `Services/DDCService.swift`（添加 VCP 常量）→ 新建 Service → 新建 View → `Views/DisplayDetailView.swift`（添加 Section）→ `docs/CODEMAP.md` |
| 新增菜单栏工具入口（非显示器相关） | `Views/MenuBarView.swift`（工具区添加入口）→ 新建 View/Service → `docs/CODEMAP.md` |
| 修改分辨率切换逻辑 | `Services/ResolutionService.swift`、`Models/DisplayMode.swift`，测试影响 `Views/ResolutionSliderView.swift` 和 `Views/DisplayModeListView.swift` |
| 修改亮度读写 | `Services/BrightnessService.swift`，外接屏同步检查 `Services/DDCService.swift` |
| 修改图像调整效果 | `Services/GammaService.swift`（公式/Table 计算）、`Views/ImageAdjustmentView.swift`（UI 滑块映射） |
| 修改串流/画中画帧处理 | `ViewModels/StreamViewModel.swift`（processedImage）、影响 `Views/StreamWindow.swift` 和 `Views/PiPWindow.swift` |
| 修改屏幕旋转 | `Services/RotationService.swift`，注意与 `DDCService` 的 IOFramebuffer 查找逻辑保持一致 |
| 添加新的持久化设置项 | `Services/SettingsService.swift`（Keys + @Published 属性 + loadAll/persist）→ 相关 View |
| 修改配置保护逻辑 | `Services/ConfigProtectionService.swift`（handleDisplayChange/applyConfig）、`Views/ConfigProtectionView.swift` |
| 修改通知/热插拔响应 | `Services/DisplayManager.swift`（displayReconfigCallback + refreshDisplays） |
| 修改 HiDPI Override 生成 | `Services/HiDPIService.swift`（generateScaledModes + plist 路径） |
| 修改 PiP 窗口行为 | `Views/PiPWindow.swift`（PiPWindowController + PiPNSWindow）、`Views/PiPControlView.swift` |
| 修改取色器/颜色历史 | `Views/SystemColorView.swift`（SystemColorViewModel）、`Services/SettingsService.swift`（colorPickerHistory） |
