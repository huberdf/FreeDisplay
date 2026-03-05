# 踩坑经验 — Xcode / 构建

> 更新: 2026-03-05

## Xcode / 构建

- xcodegen 不自动生成 Info.plist → 必须在 project.yml 设置 `GENERATE_INFOPLIST_FILE: YES`
- ScreenCaptureKit（`SCShareableContent.current`）在 `@MainActor` 上下文调用会报 non-Sendable 错误（即使设了 `SWIFT_STRICT_CONCURRENCY: minimal`）→ 解法：`@preconcurrency import ScreenCaptureKit`
- Swift 6 strict concurrency 下 singleton 报 Sendable 错误 → 类标记 `@unchecked Sendable` + 项目设 `SWIFT_STRICT_CONCURRENCY: minimal`

## Phase 12 / 收尾

- 新增服务/视图文件后必须运行 `xcodegen generate` 重新生成 xcodeproj，否则其他文件引用新类型会报 "cannot find in scope"
- Services 文件中如果使用了 `CGDirectDisplayID`，需要 `import CoreGraphics`（仅 `import Foundation` 不够）
- `NSWorkspace.shared` 需要 `import AppKit`（不能只用 Foundation）
- `NSObject` 子类做 singleton 时 Swift 6 会报 non-Sendable 警告 → 标记 `@unchecked Sendable` 解决
- `SMAppService`（开机自启动）在 macOS 13+ 可用，需要 `import ServiceManagement`
