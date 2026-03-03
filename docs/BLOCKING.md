# Blocking Issues — FreeDisplay

> 更新: 2026-03-02 | **开工前必读，有未解决的 P0/P1 问题时必须先处理**

## 调度规则

1. 读完此文件 → 如果有 P0/P1 问题 → **按优先级从高到低逐个解决，全部清完再做 ROADMAP**
2. 如果只有 P2 问题 → 可以先做 ROADMAP 任务，穿插解决 P2
3. 解决后 → 移到下方"已解决"区，写上解法
4. 工作中遇到新的卡住问题 → 立刻加到这里

---

## 🔴 P0 — 硬阻塞

（暂无）

---

## 🟡 P1 — 高优先级

### B-002: CGVirtualDisplay 是私有 API，无公开头文件
- **影响范围**: Phase 10 虚拟显示器功能（VirtualDisplayService.swift）
- **现状**: `CGVirtualDisplay`、`CGVirtualDisplayDescriptor`、`CGVirtualDisplaySettings`、`CGVirtualDisplayMode` 这四个类在 CoreGraphics 的 TBD 文件中有导出符号，但 macOS 26 SDK 的公开 C/ObjC 头文件和 Swift interface 文件中均未声明。BetterDisplay/BetterDummy 等应用通过自行声明私有 ObjC 接口头文件（bridging header）来使用这些 API。
- **当前处理**: `VirtualDisplayService.swift` 已完成架构（配置持久化、UI 接口），但所有实际创建/销毁方法均返回 `false` 占位，等待决策。
- **需要决策**：是否允许在项目中声明并使用 CGVirtualDisplay 私有 API？
  - **选项 A（允许）**: 添加 `FreeDisplay-Bridging-Header.h`，声明 CGVirtualDisplay 私有接口，在 project.yml 设置 `SWIFT_OBJC_BRIDGING_HEADER`，实现完整虚拟显示器功能。
  - **选项 B（拒绝）**: 保持现有占位实现，Phase 10 的虚拟显示器创建功能标记为"不支持"，只保留 UI 架构和 HiDPI plist 方案（Phase 3 已实现）。
- **添加日期**: 2026-03-03

---

## 🔵 P2 — 一般优先级

（暂无）

---

## ✅ 已解决

### ~~B-001: DisplayInfo.name 只显示 "Display N" 而非真实显示器名称~~
- **解法**: 用 `IOServiceMatching("IODisplayConnect")` + `IODisplayCreateInfoDictionary` 枚举所有 IODisplayConnect 服务，通过 DisplayVendorID + DisplayProductID 匹配，从 DisplayProductName 字典取首个 locale 的产品名称；内建显示屏直接返回"内建显示屏"
- **解决日期**: 2026-03-02
- **经验**: IOKit CF 字典中的整数值可能是 Int 类型而非 UInt32，需要双类型尝试

### ~~B-000: GENERATE_INFOPLIST_FILE 缺失导致编译失败~~
- **解法**: 在 project.yml settings 中添加 `GENERATE_INFOPLIST_FILE: YES`
- **解决日期**: 2026-03-02
- **经验**: xcodegen 不自动生成 Info.plist，需要显式启用

### ~~B-000b: DDCService static singleton Swift 6 并发报错~~
- **解法**: 类标记 `@unchecked Sendable`，并在 project.yml 设置 `SWIFT_STRICT_CONCURRENCY: minimal`
- **解决日期**: 2026-03-02
- **经验**: Swift 6 严格并发检查下，singleton 需要显式标记 Sendable
