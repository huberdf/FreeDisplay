# Phase 18: 稳定性加固

> 状态: 已完成 | 预计: 中等复杂度

## 目标

将 CG 阻塞调用的超时保护模式推广到全项目，确保睡眠/唤醒后 HiDPI 状态自动恢复，显示器配置变更后排列自动重新应用。

## 任务

### Task 1: 统一 CG 阻塞调用超时保护
- [x] 将 VirtualDisplayService 的 `runWithTimeout` 提取为公共工具函数（放到 `Utilities/` 或 `Services/CGHelpers.swift`）
- [x] MirrorService: `enableMirror`/`disableMirror` 中的 `CGCompleteDisplayConfiguration` 调用使用 `runWithTimeout` 包裹
- [x] ArrangementService: `setPosition` 中的 `CGCompleteDisplayConfiguration` 调用使用 `runWithTimeout` 包裹
- [x] ResolutionService: `applyModeSync` 加 10 秒超时保护（当前无限等待 `CGCompleteDisplayConfiguration`）

**实现提示**: `runWithTimeout` 已在 VirtualDisplayService 中验证有效，直接复用相同模式。注意 `@Sendable` 约束。

### Task 2: 显示器配置变更自动重排列
- [x] 在 AppDelegate 或 DisplayManager 中注册 `CGDisplayRegisterReconfigurationCallback`
- [x] 回调中检测配置变更完成（`flags` 包含 `beginConfigurationFlag` 后等待不包含的回调）
- [x] 配置变更完成后延迟 500ms 调用 `displayManager.arrangeExternalAboveBuiltin()`
- [x] 避免重复触发：用防抖（debounce）机制，500ms 内多次回调只执行最后一次

**实现提示**: `CGDisplayRegisterReconfigurationCallback` 的 context 参数用 `Unmanaged.passRetained(self)` 防止野指针（CLAUDE.md 已有规则）。回调在系统线程，需 `DispatchQueue.main.async` 切回主线程。

### Task 3: 睡眠/唤醒后自动恢复 HiDPI
- [x] 在 AppDelegate 的 `didWakeNotification` 处理中，检查 `VirtualDisplayService.hiDPIActiveDisplayIDs` 是否有活跃会话
- [x] 如果有，检查虚拟显示器是否还在线（`CGDisplayIsOnline`），如果丢失则重新创建 + 镜像 + 应用分辨率
- [x] 恢复序列：create → apply settings → sleep 500ms → mirror → sleep 500ms → setDisplayMode → arrangeExternalAboveBuiltin
- [x] 持久化 HiDPI 状态到 UserDefaults（`fd.hiDPI.activePhysicalIDs`），以便 app 重启后也能恢复

**实现提示**: 唤醒后 WindowServer 需要时间稳定，整个恢复序列加 2 秒初始延迟。参考 VirtualDisplayService 已有的 `enableHiDPIVirtual` 流程。

### Task 4: 错误恢复与用户反馈
- [x] CG 调用超时时显示菜单栏状态提示（非弹窗，用 `statusMessage` 模式）
- [x] HiDPI 恢复失败时提示用户手动重新开启
- [x] 连续失败 3 次后自动禁用 HiDPI 并提示

**实现提示**: 复用 HiDPIVirtualRowView 已有的 `statusMessage` 模式。

## 验收标准

```bash
# 编译通过
xcodebuild -scheme FreeDisplay -configuration Debug build 2>&1 | tail -3

# 手动测试
# 1. 开启 HiDPI → 合盖睡眠 → 唤醒 → HiDPI 自动恢复 + 排列正确
# 2. 开启 HiDPI → 拔外接显示器 → 重插 → 无 crash
# 3. 切换分辨率 → 排列保持正上方
```
