# Views — SwiftUI 视图层

> 纯展示和交互，❌ 不在 View 里写业务逻辑，不直接调 Service。

## 结构

- **MenuBarView.swift** — 菜单栏主视图，所有功能的入口容器
- **DisplayDetailView.swift** — 每显示器展开面板，可折叠 Section 的容器
- 每个 Section 对应一个独立 View 文件（BrightnessSliderView、ColorProfileView 等）

## 文件清单

| 文件 | 用途 |
|------|------|
| MenuBarView.swift | 菜单栏主视图 + 所有 Section 入口 |
| DisplayDetailView.swift | 显示器展开面板（12 个 Section） |
| BrightnessSliderView.swift | 亮度/对比度滑条 |
| ResolutionSliderView.swift | 分辨率滑条 |
| DisplayModeListView.swift | 分辨率模式列表（收藏置顶） |
| ArrangementView.swift | 显示器排列（含内外屏缩略图区分） |
| ColorProfileView.swift | ICC Profile 选择 |
| SystemColorView.swift | 系统颜色配置 |
| ImageAdjustmentView.swift | 图像调整（gamma/对比度） |
| VirtualDisplayView.swift | HiDPI 虚拟显示器 |
| NotchView.swift | 刘海遮罩 |
| MainDisplayView.swift | 主显示器设置 |
| AutoBrightnessView.swift | 环境光自动亮度 |

## 关键模式

- `@EnvironmentObject var displayManager: DisplayManager` — 全局注入
- `@ObservedObject` 用于共享单例（❌ 不要用 @StateObject 包装 .shared）
- 需要 hover/loading 状态的行组件 → 提取为独立 `struct`（❌ 不要用 @ViewBuilder 函数）
- 组件命名: 可复用行 `XxxRow` 或 `XxxRowView`
- 统一 hover 效果：`.background(isHovered ? Color.primary.opacity(0.07) : .clear)`

## 改动检查

- 新增 Section → 改 DisplayDetailView.swift + 检查 MenuBarView 布局
- 新增工具入口 → 改 MenuBarView.swift 工具区
- 新增行组件 → 必须用独立 struct，不能是 @ViewBuilder 函数
