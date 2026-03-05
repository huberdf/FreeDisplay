# Models — 数据模型层

> 纯数据结构，ObservableObject。

## 文件

| 文件 | 用途 |
|------|------|
| DisplayInfo.swift | 单个显示器的状态模型（高风险） |
| DisplayMode.swift | 显示模式值类型（分辨率 + 刷新率 + HiDPI） |

---

## DisplayInfo.swift — 高风险

核心显示器模型，多个 `@Published` 属性。**所有 View 和 Service 均依赖此类。**

### 改动协议

1. 增删 `@Published` 属性 → `grep -r "DisplayInfo" FreeDisplay/ --include="*.swift"` 找所有引用
2. 同步更新所有引用点（编译通过 ≠ 逻辑正确）
3. `loadDetails()` 是异步方法，在 `DisplayManager.refreshDisplays()` 中对新显示器调用

### 关键属性说明

- `displayID: CGDirectDisplayID` — 硬件标识，热插拔后可能变（不可用作持久 key）
- `isBuiltin` — 用 `CGDisplayIsBuiltin()` 判断
- `bounds` — 来自 `CGDisplayBounds()`，热插拔/排列变更后需刷新
- `name` — 来自 `NSScreen.localizedName`（比 IOKit vendorID 更可靠）
- `rotation` 属性已在 Phase 21 移除（随 RotationService/RotationView 一起删除）

---

## DisplayMode.swift

单个显示模式的值类型（分辨率 + 刷新率 + HiDPI 标志）。

- `currentMode(for:)` 静态方法获取当前模式
- `availableModes(for:)` 获取可用模式列表（包含 HiDPI 变体）
- 改动影响 ResolutionService 和 DisplayModeListView

### HiDPI 注意

- HiDPI 模式通过 `kIOScalingModeKey` 标志区分，不是简单的 2× 分辨率
- 虚拟显示器的 HiDPI 模式由 VirtualDisplayService 动态注入，不来自 DisplayMode
