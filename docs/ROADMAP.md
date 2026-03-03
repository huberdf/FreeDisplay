# Roadmap — FreeDisplay

> 创建: 2026-03-02 | 目标: 完整替代 BetterDisplay 的免费 macOS 显示器管理菜单栏应用
> **详细实现提示见**: `docs/roadmap/phase-N.md`

## Phase 0: 项目初始化 ✅

- [x] 创建项目目录结构
- [x] 创建 project.yml（xcodegen 配置）
- [x] 创建 FreeDisplay.entitlements
- [x] 创建 FreeDisplayApp.swift（@main 入口 MenuBarExtra）
- [x] 创建 AppDelegate.swift
- [x] 创建 Assets.xcassets
- [x] 创建骨架文件（DisplayInfo, DisplayManager, DDCService, MenuBarView）
- [x] xcodegen 生成项目并编译通过

## Phase 1: 显示器检测与菜单 UI ✅
> 详情: `docs/roadmap/phase-1.md`

- [x] 实现 DisplayInfo 模型完整属性（IODisplayCreateInfoDictionary 获取真实名称）
- [x] 实现 DisplayManager 热插拔监听（CGDisplayRegisterReconfigurationCallback）
- [x] 实现菜单栏主视图 MenuBarView（显示器列表 + 开关 Toggle）
- [x] 实现显示器详情展开区 DisplayDetailView（DisclosureGroup 功能 section 列表）
- [x] 实现显示器开关功能（DDC Power Mode / CGDisplayCapture）

## Phase 2: 亮度控制（DDC + 内建） ✅
> 详情: `docs/roadmap/phase-2.md`

- [x] 实现 DDC/CI I2C 底层通信（IOKit I2C 读写 VCP codes）
- [x] 实现内建显示器亮度控制（IODisplaySetFloatParameter）
- [x] 实现亮度滑块 UI（BrightnessSliderView + debounce）
- [x] 集成亮度控制到菜单（组合亮度 + 独立亮度）

## Phase 3: 分辨率管理与 HiDPI ✅
> 详情: `docs/roadmap/phase-3.md`

- [x] 实现分辨率模式枚举（CGDisplayCopyAllDisplayModes + HiDPI 检测）
- [x] 实现分辨率切换（CGConfigureDisplayWithDisplayMode）
- [x] 实现分辨率滑块 UI（ResolutionSliderView）
- [x] 实现显示模式列表 UI（DisplayModeListView 含收藏/过滤）
- [x] 实现 HiDPI 模式注入（display override plist）

## Phase 4: 屏幕旋转与显示器排列 ✅
> 详情: `docs/roadmap/phase-4.md`

- [x] 实现屏幕旋转（IOKit + CGS 私有 API）
- [x] 实现屏幕旋转 UI（RotationView 90°/180°/270°/关闭）
- [x] 实现显示器排列（CGConfigureDisplayOrigin）
- [x] 实现排列显示器 UI（ArrangementView 可视化拖拽）
- [x] 实现设为主显示屏功能

## Phase 5: 色彩管理 ✅
> 详情: `docs/roadmap/phase-5.md`

- [x] 实现 ICC Profile 枚举（ColorSync + 文件系统扫描）
- [x] 实现 ICC Profile 切换（ColorSyncDeviceSetCustomProfiles）
- [x] 实现颜色描述文件 UI（ColorProfileView 分类列表）
- [x] 实现色彩模式 UI（ColorModeView 含帧缓存类型）

## Phase 6: 图像调整 ✅
> 详情: `docs/roadmap/phase-6.md`

- [x] 实现 Gamma Table 调整引擎（CGSetDisplayTransferByFormula）
- [x] 实现对比度软件调整（gamma table min/max）
- [x] 实现反转色彩
- [x] 实现图像调整 UI（ImageAdjustmentView 11 个滑块）
- [x] 实现量化功能（Quantization）

## Phase 7: 显示器高级管理 ✅
> 详情: `docs/roadmap/phase-7.md`

- [x] 实现"设为主显示屏"UI 和逻辑
- [x] 实现"显示刘海"管理
- [x] 实现"集成控制"DDC 扩展（批量读取 VCP codes）
- [x] 实现"管理显示器"设置（配置显示、视觉识别、防睡眠）

## Phase 8: 屏幕镜像 ✅
> 详情: `docs/roadmap/phase-8.md`

- [x] 实现硬件镜像（CGConfigureDisplayMirrorOfDisplay）
- [x] 实现屏幕镜像 UI（MirrorView 目标选择 + 停止）

## Phase 9: 屏幕串流与画中画 ✅
> 详情: `docs/roadmap/phase-9.md`

- [x] 实现屏幕捕获引擎（ScreenCaptureKit SCStream）
- [x] 实现串流窗口（Metal 渲染 CMSampleBuffer）
- [x] 实现串流选项（鼠标/缩放/旋转/裁剪/滤镜/透明度）
- [x] 实现画中画（PiP 浮动窗口 + 层级/锁定/穿透选项）
- [x] 实现串流/PiP 菜单 UI

## Phase 10: 虚拟显示器 ✅
> 详情: `docs/roadmap/phase-10.md`

- [x] 实现虚拟显示器创建（CGVirtualDisplay macOS 14+）
- [x] 实现 HiDPI 增强（虚拟显示器 + 镜像方案）
- [x] 实现虚拟显示器管理 UI
- [x] 实现"高分辨率 (HiDPI)"一键开关 UI

## Phase 11: 配置保护与自动亮度 ✅
> 详情: `docs/roadmap/phase-11.md`

- [x] 实现配置快照（DisplayConfig 序列化到 JSON）
- [x] 实现配置保护监控（CGDisplayRegisterReconfigurationCallback + 自动恢复）
- [x] 实现配置保护 UI（ConfigProtectionView 保护项 Toggle 列表）
- [x] 实现自动亮度（环境光传感器 → DDC 同步）
- [x] 实现自动亮度 UI

## Phase 12: 收尾与发布 ✅
> 详情: `docs/roadmap/phase-12.md`

- [x] 实现全局设置持久化（UserDefaults + JSON）
- [x] 实现开机自启动（SMAppService）
- [x] 实现"视频滤镜窗口"工具
- [x] 实现"系统颜色"工具（取色器）
- [x] 实现"检查更新"功能
- [x] UI 打磨与一致性（深色/浅色适配、间距、动画）
- [x] 性能优化（Metal 渲染、DDC 缓存、内存管理）
- [x] 构建可分发 .app / .dmg
- [x] 触发 refactor-context 更新脚手架

## Phase 13: 关键 Bug 修复 ⏳
> 详情: `docs/roadmap/phase-13.md`

- [ ] 修复图像调整关闭后的残影问题（onDisappear + app 退出 hook）
- [ ] 修复 1920x1080 分辨率无法点击的问题（异步切换 + 错误反馈）
- [ ] 修复 HiDPI 缩放模式不显示/需要重连的问题（自动刷新模式列表）
- [ ] 改进 DisplayMode 的 HiDPI 分类显示

## Phase 14: 性能优化（消除卡顿） ⏳
> 详情: `docs/roadmap/phase-14.md`

- [ ] 将 BrightnessService 的 IOKit 调用移到后台线程
- [ ] 将 DisplayInfo.init 的 IOKit 查询移到后台
- [ ] 将 ColorProfileService.enumerateProfiles 改为异步
- [ ] 拆分 DisplayInfo 的 @Published 属性，减少级联重绘
- [ ] 移除 View body 中的同步 CG 调用
- [ ] 优化 DDCService 批量读取性能

## Phase 15: 交互体验打磨 ⏳
> 详情: `docs/roadmap/phase-15.md`

- [ ] 为所有慢操作添加 Loading 状态和视觉反馈
- [ ] 为 Slider 操作添加实时值显示和触觉反馈
- [ ] 添加 Section 展开/收起动画
- [ ] 改进菜单整体交互感（hover、press 动效）
- [ ] 修复 @StateObject 单例反模式
