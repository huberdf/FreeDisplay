# 踩坑经验索引 — FreeDisplay

> 更新: 2026-03-05

## 主题索引

| 主题 | 文件 | 条数 |
|------|------|------|
| IOKit / DDC / 旋转 / 环境光 / 显示器匹配 / Apple Silicon | [iokit.md](iokit.md) | L-003, L-004, L-005 + 通用条目 |
| CoreGraphics / HiDPI / CGVirtualDisplay | [coregraphics.md](coregraphics.md) | L-006, L-007, L-020 ~ L-027 + 通用条目 |
| SwiftUI / MenuBarExtra / UI 动画 / DDC 缓存 / 性能 | [swiftui.md](swiftui.md) | 通用条目 |
| 跨 Service 协作 / 并发 / 资源管理 | [services.md](services.md) | L-008 ~ L-019 |
| Xcode 构建 / Phase 收尾 | [build.md](build.md) | 通用条目 |

## 永久规则（高频踩坑）

1. **新增 Swift 源文件后必须 `xcodegen generate`** — 否则编译器不知道新文件（"cannot find in scope"）
2. **两个 Service 不能各自写同一 CoreGraphics 资源** — 指定唯一写入方，其他方通过接口影响（见 services.md L-008）
3. **C 回调传 self 一律用 `Unmanaged.passRetained`，注销时配对 release** — passUnretained 是野指针定时炸弹
4. **❌ CGConfigureDisplayMirrorOfDisplay 做 HiDPI** — Apple Silicon 上触发硬件镜像 + 鼠标卡顿，✅ 用 plist override（/Library/Displays/）
