# Phase 15: 交互体验打磨

> 目标：让每个操作都有即时视觉反馈，整体交互感灵动流畅

## 任务列表

- [x] 为所有慢操作添加 Loading 状态和视觉反馈
  - 实现提示：
    1. `DisplayModeListView.swift`：分辨率切换时显示小的 `ProgressView()` 在被点击的行上，其他行 disabled
    2. `ColorProfileView.swift`：应用 ICC Profile 时在对应行显示 ProgressView
    3. `MirrorView.swift`：开启/关闭镜像时显示状态
    4. 统一模式：创建 `LoadingButton` 组件 — 点击后自动显示 spinner 直到 async 操作完成
    5. 所有 Service 方法如果是 async 的，调用处统一用 `Task { isLoading = true; defer { isLoading = false }; await ... }` 模式
  - 验证：点击任何切换操作 → 立刻看到 loading 动画 → 完成后消失

- [x] 为 Slider 操作添加实时值显示和触觉反馈
  - 实现提示：
    1. 所有 Slider（亮度、对比度、伽马等）旁边显示当前百分比值，拖动时实时更新
    2. 松手时值文字短暂高亮（用 `withAnimation(.easeOut(duration: 0.3))` 改变颜色）
    3. 滑块添加 `.sensoryFeedback(.selection, trigger: value)` 或用 `NSHapticFeedbackManager`（如果是 MacBook 触控板）
    4. 值显示格式统一：`"75%"` 而非 `"0.75"` 或 `"0%"`（当前图像调整显示 0% 是因为值确实是 0，但格式要统一）
  - 验证：拖动滑块 → 旁边百分比数字实时跟随 → 松手时轻微动画反馈

- [x] 添加 Section 展开/收起动画
  - 实现提示：
    1. `DisplayDetailView.swift` 中所有 Section 的展开/收起添加 `withAnimation(.spring(response: 0.3, dampingFraction: 0.8))` 包裹状态切换
    2. Section 内容用 `.transition(.opacity.combined(with: .move(edge: .top)))` 添加进出动画
    3. Section header 的箭头图标用 `.rotationEffect` 在展开时旋转 90°→0°（或用 chevron.right → chevron.down 的切换动画）
    4. 确保动画不影响性能：collapsed 的 Section 内容应该是条件渲染 `if expanded { ... }` 而非 opacity 隐藏
  - 验证：点击 Section header → 内容平滑展开/收起，箭头旋转动画

- [x] 改进菜单整体交互感
  - 实现提示：
    1. 行点击添加 hover 效果：`.onHover { isHovered = $0 }` + 背景色过渡 `Color.primary.opacity(isHovered ? 0.05 : 0)`
    2. 按钮点击时添加 scale 动画：`.scaleEffect(isPressed ? 0.97 : 1.0)` + `.animation(.easeInOut(duration: 0.1))`
    3. 列表项之间的分隔线用 `Divider().opacity(0.3)` 让视觉层次更清晰
    4. 检查所有 Toggle 开关是否有统一样式，状态切换是否流畅
  - 验证：鼠标悬停在各行上有淡入淡出高亮 → 点击有轻微缩放反馈 → 整体感觉灵动

- [x] 修复 @StateObject 单例反模式
  - 实现提示：
    1. `MenuBarView.swift`：`@StateObject private var updateService = UpdateService.shared` → 改为 `@ObservedObject private var updateService = UpdateService.shared`
    2. 同上 `SettingsService.shared`
    3. 检查所有 View 中使用 `@StateObject` 包装共享单例的地方，统一改为 `@ObservedObject`
    4. 只有 View 自己创建并拥有的对象才用 `@StateObject`（如 `@StateObject private var vm = SomeViewModel()`）
  - 验证：编译通过 + 菜单多次打开关闭无重复订阅导致的闪烁

**Phase 验收**: 编译通过 + 主观体验流畅灵动：点击有即时反馈、滑块拖动流畅、展开收起有动画、无卡顿
