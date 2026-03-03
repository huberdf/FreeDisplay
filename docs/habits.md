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
