# File Tree — FreeDisplay (Annotated)

> 完整带注释的目录结构。快速参考见 [CLAUDE.md](CLAUDE.md)，模块关系见 [relationships.md](relationships.md)。

---

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
│   │   ├── phase-13.md             # Phase 13: 关键 Bug 修复
│   │   ├── phase-14.md             # Phase 14: 性能优化
│   │   ├── phase-15.md             # Phase 15: 其他增强
│   │   ├── phase-16.md             # Phase 16: HiDPI 虚拟显示器 + 预设
│   │   └── phase-17.md             # Phase 17: UI/UX 打磨
│   ├── codemap/                    # 代码导航地图（本目录）
│   │   ├── CLAUDE.md               # 快速参考索引（模块总览、高风险文件、任务表）
│   │   ├── file-tree.md            # 完整带注释目录结构（本文件）
│   │   └── relationships.md        # 模块关系图 + 服务内部依赖 + 数据流
│   ├── BLOCKING.md                 # 阻塞问题追踪（开工前必读）
│   ├── habits.md                   # 开发偏好与工作习惯记录
│   ├── lessons.md                  # 踩坑经验与教训
│   └── ROADMAP.md                  # 总体进度追踪（autopilot 靠此追踪 [x] 标记）
├── FreeDisplay/                    # Swift 源码目录（xcodegen 自动包含所有 .swift）
│   ├── App/                        # 应用入口，SwiftUI App 生命周期
│   │   ├── AppDelegate.swift       # NSApplicationDelegate，确保仅在菜单栏显示；改动影响 App 生命周期钩子
│   │   └── FreeDisplayApp.swift    # @main 入口，创建 DisplayManager 并挂载 MenuBarView；改动影响整个 App 初始化链
│   ├── Models/                     # 数据模型层（纯数据，无副作用）
│   │   ├── DisplayInfo.swift       # ⚠️ 核心显示器模型，12+ @Published 属性；所有 View/Service 均依赖此类，属性增删需全局 grep 同步
│   │   ├── DisplayMode.swift       # 单个显示模式（分辨率+刷新率+HiDPI 标志）的值类型；枚举逻辑改动影响分辨率切换和模式列表展示
│   │   └── DisplayPreset.swift     # 显示器配置预设模型：DisplayPreset（预设）+ DisplayPresetEntry（单显示器快照）；Codable，由 PresetService 持久化
│   ├── Services/                   # 业务逻辑层，与系统框架直接交互
│   │   ├── ArrangementService.swift        # 通过 CGDisplayConfiguration 读写显示器位置，支持设为主显示器；setPosition/setAsMainDisplay 已异步化，CG 事务在 CGHelpers.runWithTimeout 内执行；改动影响拖拽排列和主显示器切换
│   │   ├── AutoBrightnessService.swift     # 读取 IOKit AppleLMUController 环境光传感器，定时轮询映射 lux→亮度；改动影响自动亮度精度和电池消耗
│   │   ├── BrightnessService.swift         # 统一亮度接口：内建屏用 IODisplayGetFloatParameter，外接屏用 DDC VCP 0x10；改动影响所有亮度读写路径
│   │   ├── CGHelpers.swift                 # 共享 CG 阻塞调用工具：CGHelpers.runWithTimeout(seconds:fallback:operation:) 在后台线程以超时保护运行 WindowServer IPC 阻塞操作；被 ArrangementService、MirrorService、ResolutionService、VirtualDisplayService 使用
│   │   ├── ColorProfileService.swift       # ICC Profile 枚举（扫描 3 个系统目录）和切换（ColorSync API）；改动影响色彩描述文件列表和切换
│   │   ├── DDCService.swift                # ⚠️ IOKit I2C DDC/CI 通信核心：IOFramebuffer 查找、VCP 读写、5 秒 TTL 缓存、3 次重试；几乎所有外接显示器功能的底层依赖，改动需极谨慎
│   │   ├── DisplayManager.swift            # ⚠️ 显示器枚举（CGGetOnlineDisplayList）+ CGDisplay 热插拔回调 + arrangeExternalAboveBuiltin() 自动外接屏定位；@Published displays 被全局注入，改动影响整个显示器列表数据流
│   │   ├── GammaService.swift              # 软件 Gamma 调整：CGSetDisplayTransferByFormula/Table，支持对比度/增益/色温/量化/反色；所有 gamma/软件亮度写入的唯一入口；改动影响图像调整效果
│   │   ├── HiDPIService.swift              # 写 /Library/Displays/...plist 注入 HiDPI 缩放模式，需管理员权限；改动影响 HiDPI override 生成逻辑
│   │   ├── LaunchService.swift             # SMAppService 管理开机自启动（macOS 13+）；改动仅影响 Launch at Login 功能
│   │   ├── MirrorService.swift             # CGDisplayConfiguration 硬件级屏幕镜像的启用/停止；enableMirror/disableMirror 已异步化，CG 事务在 CGHelpers.runWithTimeout 内执行；改动影响镜像功能
│   │   ├── NotchOverlayManager.swift       # 在内建屏刘海区域创建黑色遮罩 NSWindow（screenSaver 级别）；改动影响刘海遮罩的视觉效果和层级
│   │   ├── ResolutionService.swift         # 通过 CGConfigureDisplayWithDisplayMode 切换显示模式；applyModeSync 已异步化，整个 CG 事务在 CGHelpers.runWithTimeout 内执行；resolvedTargetDisplayID() 在镜像检测时回退到 VirtualDisplayService；改动影响分辨率切换成功率
│   │   ├── SettingsService.swift           # UserDefaults + JSON 文件持久化全局和每显示器设置；改动需注意 key 命名（必须 fd. 前缀）和向后兼容
│   │   ├── UpdateService.swift             # GitHub Releases API 检查新版本，语义化版本比较；改动影响更新检查逻辑
│   │   ├── VirtualDisplayService.swift     # 虚拟显示器创建/销毁：CGVirtualDisplay 私有 API（vendorID 必须非零如 0xEEEE，主线程创建），HiDPI via 镜像模式，CGHelpers.runWithTimeout 超时保护，hiDPILog 文件调试日志，ObjC 类型 Sendable 扩展；HiDPI 配置仅运行时生效不持久化；改动影响虚拟显示器和 HiDPI 一键预设功能
│   │   └── PresetService.swift             # 预设管理：保存/加载/应用显示器配置预设；使用 DisplayManagerAccessor 读取当前显示器状态；presets.json 存储在 ~/Library/Application Support/FreeDisplay/
│   ├── Utilities/                  # 工具扩展
│   │   └── NSScreenExtension.swift         # NSScreen 扩展：按 CGDirectDisplayID 查找 NSScreen，获取 displayID；被 NotchView、NotchOverlayManager 依赖
│   ├── FreeDisplay-Bridging-Header.h       # 私有 API 声明：CGVirtualDisplay（macOS 14+）和 IOAVService（Apple Silicon DDC）；属性名已对照 Chromium 源码验证（maxPixelsWide/maxPixelsHigh 非 maxPixelSize）
│   └── Views/                      # SwiftUI 视图层
│       ├── ArrangementView.swift           # 多显示器拖拽排列画布（内外屏缩略图区分）+ 设为主显示器按钮；依赖 ArrangementService
│       ├── AutoBrightnessView.swift        # 自动亮度开关 + 灵敏度滑块 + 环境光 lux 显示；依赖 AutoBrightnessService
│       ├── BrightnessSliderView.swift      # 单显示器亮度滑块（200ms 去抖）+ 全局组合亮度控制；依赖 BrightnessService + DDCService
│       ├── ColorProfileView.swift          # ICC Profile 列表（推荐/全部分组）和切换；依赖 ColorProfileService
│       ├── DisplayDetailView.swift         # ⚠️ 每显示器展开面板，可折叠 Section 的容器（三组分组）；新增/删除 Section 都要改此文件，且需同步 MenuBarView
│       ├── DisplayModeListView.swift       # 分辨率模式列表（HiDPI/原生/其他分组）、收藏置顶星标、点击切换；依赖 ResolutionService
│       ├── ImageAdjustmentView.swift       # 11 个图像调整滑块（对比度/Gamma/增益/色温/各通道/量化/反色）；依赖 GammaService
│       ├── MainDisplayView.swift           # "设为主显示屏"行，当前已是主屏时显示状态标签；依赖 ArrangementService
│       ├── MenuBarView.swift               # ⚠️ 菜单栏主视图：显示器列表 + 展开/折叠 + 工具区 + 设置区 + PresetListView；是所有功能的入口容器，改动影响全局布局
│       ├── NotchView.swift                 # 刘海信息显示 + 遮罩开关（仅有刘海的内建屏显示）；依赖 NotchOverlayManager
│       ├── ResolutionSliderView.swift      # 分辨率横向拖动滑块（松手生效）；依赖 ResolutionService，读取 DisplayInfo.availableModes
│       ├── SystemColorView.swift           # 系统取色器（NSColorSampler）+ HEX/RGB/HSB 显示 + 历史记录；依赖 SettingsService 持久化颜色历史
│       ├── HiDPIView.swift                 # HiDPI Override 状态行（plist 方案）+ 写入/还原按钮；依赖 HiDPIService
│       ├── VirtualDisplayView.swift        # 虚拟显示器配置列表 + 创建表单（预设分辨率）+ HiDPI 一键预设；依赖 VirtualDisplayService
│       └── SavePresetView.swift            # 保存当前显示器状态为预设；内联表单（名称 + 图标选择器）；调用 PresetService.captureCurrentState + addPreset
├── FreeDisplay.xcodeproj/          # Xcode 项目文件（由 xcodegen 生成，不要手动编辑）
├── .gitignore                      # Git 忽略规则
├── build.sh                        # 快速构建脚本
├── CLAUDE.md                       # Claude 上下文入口（项目规则、决策约定）
└── project.yml                     # xcodegen 配置，改动后必须重新运行 xcodegen generate
```
