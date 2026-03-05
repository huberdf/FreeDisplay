# 工作习惯 — FreeDisplay

> 更新: 2026-03-02

## 构建与测试

- 构建命令：`cd ~/Desktop/FreeDisplay && xcodebuild -scheme FreeDisplay -configuration Debug build 2>&1 | tail -5`
- 改了 project.yml 后必须先 `xcodegen generate` 再 build
- 编译输出很长，只看最后几行即可（`| tail -5`）

## 代码风格

- SwiftUI 视图保持声明式，复杂逻辑提取到 ViewModel/Service
- @MainActor 标注所有 ObservableObject 类（解决 Swift 6 并发检查）
- Service 层用 singleton 模式（`static let shared`），标记 `@unchecked Sendable`

## 项目管理

- xcodegen 管理项目，不手动编辑 .xcodeproj
- 新文件放到 FreeDisplay/ 对应子目录，xcodegen 自动包含
- 每个 Phase 完成后更新 roadmap 中的 `[x]` 标记

## 代理执行质量控制

- 给代理的指令要包含**精确的代码修改**（具体改哪行改成什么），而非高层描述
- 编译通过 ≠ 功能正常，需要验证运行时行为
- 涉及硬件交互的功能（DDC、IOKit），代理难以验证，需要人工测试确认

## 多代理优化工作流（Round 3-4 验证有效）

- **扫描和修复分开**：先 4 个扫描代理并行（只读不改），收集完所有问题再派修复代理——修复代理有完整上下文，不遗漏关联修复
- **扫描要覆盖"功能交互链路"**：不只扫单文件 bug，每个功能的「用户操作→UI→Service→系统 API→回调」完整链路都要覆盖，跨 Service 交互问题只有这样才能发现
- **P0 先修，每批编译一次**：不要攒太多改动再编译，发现失败时难以定位
- **0 warnings 是质量底线**：每轮结束前清理所有 warnings

## SwiftUI 组件开发

- 需要 hover/loading 等本地状态的行组件 → 提取为独立 struct（不要用 @ViewBuilder 函数，@ViewBuilder 不支持 @State）
- 命名约定：可复用行组件用 `XxxRow` 或 `XxxRowView`，私有 struct 加 `private` 修饰
- hover 效果标准模板：`@State private var isHovered = false` + `.background(Color.primary.opacity(isHovered ? 0.06 : 0))` + `.onHover { isHovered = $0 }` + `.animation(.easeInOut(duration: 0.15), value: isHovered)`

## 多代理 UX 打磨工作流（3轮验证有效）

- **按功能域分组**：MenuBar/DetailView/Sliders/FeatureViews 分别派给不同代理，不要让两个代理编辑同一文件
- **先读后改**：告诉代理"先完整读文件，再按清单改"，避免代理凭假设修改
- **每轮结束编译验证**：所有代理汇报后，用 `xcodebuild` 做最终编译确认
- **改进清单要具体**：给代理的指令必须包含目标 struct 名、@State 变量名、具体的 modifier 代码，而不是"加 hover 效果"这样的高层描述

## 调试模式

- **文件日志调试法**：当 stdout/stderr 不可见时（如菜单栏 app），写 `~/Desktop/xxx_debug.log` 文件追踪执行流程，比 print/NSLog 更可靠
- **参考实现验证法**：私有 API 不靠猜，找已知可运行的开源项目（Chromium、BetterDisplay、node-mac-virtual-display）作为权威参考，对照属性名和调用方式

## UX 模式

- **一键预设模式**：把多步操作（创建虚拟显示器 + 设分辨率 + 排列）封装成单个 toggle，用户体验最佳；适用于所有"一组动作组合才有意义"的功能

## HiDPI 开发经验

- **plist override 是唯一可行的 HiDPI 方案**：写 `/Library/Displays/Contents/Resources/Overrides/`，需要管理员权限（NSAppleScript），启用后重连显示器生效
- **不要在 override plist 里设 DisplayProductName**：会覆盖系统显示器名称
- **获取原生分辨率**：用 `availableModes.max()` 而非 `CGDisplayPixelsWide/High`（后者返回当前分辨率）
- **私有框架加载**：一律用 dlopen+dlsym，不用 @_silgen_name（会 linker error）
