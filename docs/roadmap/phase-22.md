# Phase 22: 自动亮度重写 — 跟随内建屏幕

> 状态: 完成 | 预计: 高复杂度

## 目标

重写自动亮度功能：放弃 Intel-only 的 AppleLMUController 方案，改为**监听内建屏幕亮度变化，按比例同步到外接显示器**。这是 BetterDisplay 采用的方案，在 Apple Silicon 上稳定可靠。

## 技术方案

macOS 系统已在为内建屏自动调节亮度（根据环境光）。FreeDisplay 只需要：
1. 每 2 秒轮询内建屏当前亮度（`IODisplayGetFloatParameter` 或 CoreDisplay 私有 API）
2. 如果亮度变化超过阈值（2%），按用户设定的映射曲线同步到外接显示器
3. 外接显示器通过 DDC VCP 0x10 或 gamma table 软件降级设置亮度

**关键 API**:
- 内建屏亮度读取：`CoreDisplay_Display_GetUserBrightness(displayID)` — Apple Silicon 上可靠
- 备选：`IODisplayGetFloatParameter(service, kNilOptions, kIODisplayBrightnessKey, &brightness)`
- 外接屏亮度设置：已有 `BrightnessService.setBrightness()` 复用

## 任务

### Task 1: 重写 AutoBrightnessService — 跟随模式
- [x] 移除 `AppleLMUController` 传感器轮询逻辑（`findSensorPort`、`readAmbientLux` 等全部删除）
- [x] 新增 `readBuiltinBrightness() -> Double?`：读取内建屏当前亮度（0.0-1.0）
  - 首选：`@_silgen_name("CoreDisplay_Display_GetUserBrightness") func CoreDisplay_Display_GetUserBrightness(_ display: CGDirectDisplayID) -> Double`
  - 备选：`IODisplayGetFloatParameter` 遍历 IODisplayConnect
- [x] 新增 `@Published var builtinBrightness: Double = 0` 替换 `lastLux`
- [x] 轮询逻辑改为：读内建屏亮度 → 如果变化 > 2% → 按映射曲线计算外接屏目标亮度 → 调用 BrightnessService
- [x] 映射曲线：`externalTarget = builtinBrightness * sensitivityMultiplier`（sensitivity 范围 0.5-1.5，默认 1.0）
- [x] 保留 30 秒手动调节冷却期
- [x] 保留 UserDefaults `fd.AutoBrightnessEnabled`、`fd.AutoBrightnessSensitivity`

**实现提示**: `CoreDisplay_Display_GetUserBrightness` 是私有 API 但在 macOS 14+ 上稳定存在，MonitorControl/Lunar 等开源项目都在用。用 `@_silgen_name` 声明即可。如果 `CoreDisplay_Display_GetUserBrightness` 返回 0（某些系统版本），用 IODisplayGetFloatParameter 做 fallback。

### Task 2: 重写 AutoBrightnessView — 适配新方案
- [x] 移除 `lastLux` 显示（不再有 lux 值）
- [x] 改为显示"内建屏亮度: XX%"（`builtinBrightness` 实时显示）
- [x] 传感器不可用的提示改为"未检测到内建显示屏"（只在没有内建屏时显示）
- [x] Sensitivity 滑块保留，文案改为"同步比例"
- [x] 添加说明文字："自动跟随内建屏幕亮度调整外接显示器"

**实现提示**: `sensorUnavailable` 逻辑改为检查 `builtinBrightness > 0 || hasBuiltinDisplay`，不再检查 lux。

### Task 3: 内建屏亮度读取验证
- [x] 写一个临时测试：在 AppDelegate 启动时打印 `CoreDisplay_Display_GetUserBrightness(builtinDisplayID)` 到 `~/Desktop/brightness_test.log`
- [x] 手动调节亮度滑块，确认读数实时变化（0.0-1.0 范围）
- [x] 如果 CoreDisplay 返回 0 或异常 → 切换到 IODisplayGetFloatParameter 路径
- [x] 测试通过后删除临时测试代码

**实现提示**: 内建显示器 ID 用 `CGDisplayIsBuiltin(displayID)` 过滤。调试用文件日志比 print 更可靠（菜单栏 app 没有 stdout）。

### Task 4: 编译验证 + 集成测试
- [x] 编译通过
- [x] 实际测试：开启自动亮度 → 调节 MacBook 亮度 → 观察外接显示器是否跟随
- [x] 边界测试：拔掉外接显示器 → 不 crash；没有内建屏时 → 显示提示
- [x] 更新 `docs/CODEMAP.md` 中 AutoBrightnessService 的描述

## 验收标准

```bash
# 编译通过
xcodebuild -scheme FreeDisplay -configuration Debug build 2>&1 | tail -3

# 手动测试
# 1. 开启自动亮度 → 调节 MacBook 亮度 → 外接显示器亮度跟随变化
# 2. 调节"同步比例"滑块 → 外接显示器响应变化
# 3. 手动调节外接显示器亮度 → 30 秒内自动亮度不覆盖
# 4. 合盖/拔显示器 → 不 crash
```
