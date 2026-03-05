# Phase 19: 显示器预设系统

> 状态: 已完成 | 预计: 中等复杂度

## 目标

将一键 HiDPI 扩展为通用的显示器预设系统，用户可保存当前显示状态为预设，一键切换不同配置。

## 任务

### Task 1: 预设数据模型
- [x] 创建 `Models/DisplayPreset.swift`，定义预设结构体：
  - `id: UUID`、`name: String`、`icon: String`（SF Symbol 名）
  - `displays: [DisplayPresetEntry]`，每个条目包含：
    - `displayUUID: String`（匹配物理显示器）
    - `width: Int`、`height: Int`、`isHiDPI: Bool`（目标分辨率）
    - `brightness: Double?`（可选亮度）
    - `arrangement: CGPoint?`（可选排列位置）
    - `enableHiDPIVirtual: Bool`（是否启用 HiDPI 虚拟显示器）
- [x] 创建 `Services/PresetService.swift`：加载/保存/应用预设
- [x] 预设存储在 `~/Library/Application Support/FreeDisplay/presets.json`

**实现提示**: 用 `display.displayUUID` 匹配显示器（已有稳定 UUID 生成逻辑）。预设应用时如果某个显示器不在线，跳过该条目。

### Task 2: 内置默认预设
- [x] "HiDPI 模式"：复用当前 HiDPIPresetRow 逻辑（enableHiDPIVirtual + 1920×1080 + 排列）
- [x] "原生模式"：禁用 HiDPI 虚拟 + 恢复显示器原生分辨率 + 排列
- [x] 内置预设不可删除，标记 `isBuiltin: true`

**实现提示**: 将 HiDPIPresetRow 的 turnOn/turnOff 逻辑迁移到 PresetService.applyPreset()，HiDPIPresetRow 改为调用 PresetService。

### Task 3: 保存当前状态为预设
- [x] 菜单栏添加"保存为预设"按钮（在预设列表下方）
- [x] 点击后弹出内联表单：输入名称、选择图标
- [x] 自动捕获当前所有显示器的分辨率、HiDPI 状态、亮度、排列位置
- [x] 保存到 presets.json

**实现提示**: 参考 CreateVirtualDisplayForm 的内联表单模式。图标选择用 Picker + 几个预定义 SF Symbol。

### Task 4: 预设列表与一键切换
- [x] 在 MenuBarView 中显示预设列表（在 HiDPIPresetRow 的位置替换为预设 section）
- [x] 每个预设显示：图标 + 名称 + 当前是否匹配（绿色 "当前" 徽章）
- [x] 点击预设 → 应用（显示 loading spinner）
- [x] 长按/右键 → 删除（非内置预设）

**实现提示**: 预设匹配检测：遍历每个 DisplayPresetEntry，检查当前分辨率和 HiDPI 状态是否一致。全部一致则标记为"当前"。

## 验收标准

```bash
# 编译通过
xcodebuild -scheme FreeDisplay -configuration Debug build 2>&1 | tail -3

# 手动测试
# 1. 开启 HiDPI → 保存为预设"工作模式" → 关闭 HiDPI → 点击"工作模式" → HiDPI 恢复
# 2. 切换到 1280×720 → 保存为预设"低分辨率" → 在两个预设间切换
# 3. 内置"HiDPI 模式"和"原生模式"不可删除
```
