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

（暂无）

---

## 🔵 P2 — 一般优先级

（暂无）

---

## ✅ 已解决

### ~~B-004: HiDPI 虚拟显示器触发系统镜像 UI + 鼠标移动卡顿~~
- **解法**: `CGConfigureDisplayMirrorOfDisplay` 在 Apple Silicon 上会触发硬件镜像模式，这是死路。改为 BetterDisplay 同款的 plist override 方案：写 `scale-resolutions` 到 `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-XXXX/DisplayProductID-XXXX`，需要管理员权限（NSAppleScript），启用后重新连接显示器生效。已移除所有镜像相关代码（enableHiDPIVirtual/disableHiDPIVirtual/hiDPIMirrorMap 等）。
- **解决日期**: 2026-03-05
- **经验**: macOS HiDPI 方案只有两条路：(1) plist override（BetterDisplay 方案，需 admin + 重连）(2) CGVirtualDisplay 纯虚拟显示器（不与物理屏镜像）。❌ 绝对不要用 CGConfigureDisplayMirrorOfDisplay。

### ~~B-002: CGVirtualDisplay 是私有 API，无公开头文件~~
- **解法**: 用户批准使用私有 API。已创建 FreeDisplay-Bridging-Header.h 声明 CGVirtualDisplay + IOAVService 接口，VirtualDisplayService 已实现完整的虚拟显示器创建/销毁功能。
- **解决日期**: 2026-03-03

### ~~B-003: DDC 亮度控制对部分外接显示器无效~~
- **解法**: 根因确认：DDCService 使用的 IOFramebuffer I2C API 在 Apple Silicon 上完全不工作。已添加 IOAVService ARM64 DDC 路径（通过 DCPAVServiceProxy 查找外接显示器），并添加 CGSetDisplayTransferByTable gamma table 软件亮度降级方案。
- **解决日期**: 2026-03-03

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
