# FreeDisplay — Claude 上下文入口

> 版本: 2026-03-02 | 状态: 开发中（Phase 1 完成）

## 这个项目是什么

BetterDisplay 的免费开源替代品。macOS 菜单栏应用，完整管理显示器：DDC 亮度/对比度控制、分辨率/HiDPI 管理、屏幕旋转/排列、色彩管理、屏幕串流/画中画、虚拟显示器。
技术栈：Swift 6 + SwiftUI (MenuBarExtra) + IOKit + CoreGraphics + ScreenCaptureKit，零第三方依赖。

## 快速导航（按需加载）

| 需要做什么 | 读哪个文件 |
|-----------|-----------|
| **开工前检查阻塞问题** | `docs/BLOCKING.md` |
| 了解代码结构、找文件 | `docs/CODEMAP.md` |
| 查看项目规划、当前进度 | `docs/roadmap/CLAUDE.md`（总览）→ `docs/roadmap/phase-N.md`（详情） |
| 查看工作习惯/偏好 | `docs/habits.md` |
| 查看踩坑经验/教训 | `docs/lessons.md` |

## 当前焦点

- **当前阶段**: Phase 13 — 关键 Bug 修复（Phase 0-12 已完成，用户反馈修复中）
- **禁止动的地方**: `docs/roadmap/` 不要改结构（planner 产出），只更新 `[x]` 进度标记
- **最近变更**: Phase 0-12 全部完成。用户反馈：图像调整残影、1080P 点不动、缺 HiDPI 缩放模式、UI 卡顿不灵动。新增 Phase 13-15 修复计划。

## 自主决策规则

> **阻塞优先（开工第一件事）：**
- 每次开始 → 先读 `docs/BLOCKING.md` → 有 P0/P1 先解决 → 全清才做 ROADMAP
- 遇到搞不定的问题 → 加到 `docs/BLOCKING.md`

> **联动规则：**
- 改了 `DisplayInfo` 的属性 → grep 所有引用点同步更新
- 改了 `project.yml` → 必须 `xcodegen generate` 重新生成 xcodeproj
- 新增 Service/View 文件 → 更新 `docs/CODEMAP.md`

> **修复/开发类：**
- 编译失败 → 先修到通过，不跳过
- Swift 6 并发报错 → 用 `@MainActor` 或 `@unchecked Sendable`（项目已设 `SWIFT_STRICT_CONCURRENCY: minimal`）
- 新增文件不需要改 project.yml（xcodegen 自动包含 FreeDisplay/ 下所有源文件）

> **停下来问用户：**
- 需要使用私有 API（CoreDisplay 等）
- 需要 SIP 关闭或特殊系统权限
- 架构方向变更（MVVM→其他）

> **自维护规则：**
- 增删改文件 → 更新 `docs/CODEMAP.md`
- Phase 任务完成 → 在 `docs/roadmap/phase-N.md` 标 `[x]` **且同步在 `docs/ROADMAP.md` 标 `[x]`**（autopilot 靠后者追踪进度）
- 踩了坑 → 写到 `docs/lessons.md`
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
| CoreGraphics | 显示器枚举、分辨率、旋转、排列 | 1-4 |
| IOKit | DDC/CI I2C 通信、亮度/对比度 | 2 |
| ScreenCaptureKit | 屏幕捕获、串流 | 9 |
| ColorSync | ICC Profile 管理 | 5 |
| CoreGraphics (CGVirtualDisplay) | 虚拟显示器 | 10 |
