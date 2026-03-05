# Code Map — FreeDisplay (Quick Reference)

> **用途**: Claude 代码导航快速参考。详细文件树见 `file-tree.md`，模块关系图见 `relationships.md`。
> **维护**: 重大结构变更后更新描述和模块关系图。

---

## 入口文件 / Key Entry Points

- `CLAUDE.md`
- `docs/codemap/CLAUDE.md` (本文件)
- `docs/roadmap/CLAUDE.md`

详细信息: [file-tree.md](file-tree.md) | [relationships.md](relationships.md)

---

## 模块总览 / Module Summary

| 模块 | 职责 | 关键文件 | 注意事项 |
|------|------|---------|---------|
| **App** | 应用生命周期、MenuBarExtra 场景声明 | `FreeDisplayApp.swift` | DisplayManager 在此创建并注入 environmentObject |
| **Models** | 纯数据结构，ObservableObject | `DisplayInfo.swift`, `DisplayMode.swift` | 改 DisplayInfo 属性必须全局 grep 同步 |
| **Services** | 系统框架交互，无 UI | `DDCService.swift`, `DisplayManager.swift`, `BrightnessService.swift` 等 | 大多数 Service 是 @MainActor 单例 |
| **Views** | SwiftUI 视图，纯展示和交互 | `MenuBarView.swift`, `DisplayDetailView.swift` | 不要在 View 里写业务逻辑，调 Service |
| **Utilities** | 系统类型扩展 | `NSScreenExtension.swift` | 被多处依赖，轻易不改 |

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

## 常见任务 → 修改哪些文件 / Task Reference Table

| 任务 | 需要修改的文件 |
|------|--------------|
| 新增一个显示器属性（如 HDR 状态） | `Models/DisplayInfo.swift` → grep 所有引用 → 相关 View/Service |
| 新增一个 DDC VCP 功能（如音量控制） | `Services/DDCService.swift`（添加 VCP 常量）→ 新建 Service → 新建 View → `Views/DisplayDetailView.swift`（添加 Section）→ `docs/codemap/CLAUDE.md` |
| 新增菜单栏工具入口（非显示器相关） | `Views/MenuBarView.swift`（工具区添加入口）→ 新建 View/Service → `docs/codemap/CLAUDE.md` |
| 修改分辨率切换逻辑 | `Services/ResolutionService.swift`、`Models/DisplayMode.swift`，测试影响 `Views/ResolutionSliderView.swift` 和 `Views/DisplayModeListView.swift` |
| 修改亮度读写 | `Services/BrightnessService.swift`，外接屏同步检查 `Services/DDCService.swift` |
| 修改图像调整效果 | `Services/GammaService.swift`（公式/Table 计算）、`Views/ImageAdjustmentView.swift`（UI 滑块映射） |
| 添加新的持久化设置项 | `Services/SettingsService.swift`（Keys + @Published 属性 + loadAll/persist）→ 相关 View |
| 修改通知/热插拔响应 | `Services/DisplayManager.swift`（displayReconfigCallback + refreshDisplays） |
| 修改 HiDPI Override 生成 | `Services/HiDPIService.swift`（generateScaledModes + plist 路径） |
| 修改取色器/颜色历史 | `Views/SystemColorView.swift`（SystemColorViewModel）、`Services/SettingsService.swift`（colorPickerHistory） |
| 修改虚拟显示器逻辑 | `Services/VirtualDisplayService.swift`、`FreeDisplay-Bridging-Header.h`（私有 API 声明） |

---

## 注意事项 / Pitfalls

- **DisplayInfo 属性联动**：改了 `DisplayInfo` → grep 所有引用点同步更新，否则编译可能通过但逻辑错误
- **project.yml**：改了后必须 `xcodegen generate` 重新生成 xcodeproj
- **新增源文件**：`FreeDisplay/` 目录下所有 `.swift` 文件 xcodegen 自动包含，不需要改 `project.yml`
- **Swift 6 并发**：项目设 `SWIFT_STRICT_CONCURRENCY: minimal`，并发报错用 `@MainActor` 或 `@unchecked Sendable` 处理
- **无 Sandbox**：entitlements 已关闭 App Sandbox，IOKit / /Library/Displays 等直接访问可用
- **Bridging Header 私有 API**：`FreeDisplay-Bridging-Header.h` 中的 CGVirtualDisplay / IOAVService 声明基于 Chromium 源码验证，修改前需重新核对属性名
- **HiDPIService 权限**：写 `/Library/Displays/` 需要管理员权限，无权限时返回错误字符串供 UI 展示
- **CGHelpers.runWithTimeout**：WindowServer IPC 可能阻塞主线程，所有 CG 配置事务须通过此工具在后台线程以超时保护执行
