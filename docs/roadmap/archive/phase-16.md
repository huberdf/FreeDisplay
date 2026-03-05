# Phase 16: 全面 Bug 修复

> 目标：修复审计发现的 37 个问题，按优先级分三批执行

## 批次 A: P0 — 崩溃/数据丢失（5 个）

- [x] A1: 修复 AutoBrightnessService 遍历 displays 竞态条件
  - **文件**: `AutoBrightnessService.swift` applyBrightness 方法
  - **问题**: 访问 `DisplayManagerAccessor.shared.displays` 并修改 `display.brightness` 时无同步保护，热插拔时可能崩溃
  - **修法**: 迭代前用 `let snapshot = displays` 做数组快照，或加 `@MainActor` 确保主线程访问
  - **验证**: 自动亮度开启状态下热插拔显示器不崩溃

- [x] A2: 修复 BrightnessService refreshBrightness 内存泄漏
  - **文件**: `BrightnessService.swift` refreshBrightness 方法
  - **问题**: DDCService.shared.readAsync() 的 completion handler 隐式捕获 self，display 释放后回调悬空
  - **修法**: completion 中用 `[weak self]` 捕获，回调内 `guard let self else { return }`
  - **验证**: 反复刷新亮度后 Instruments 无内存泄漏

- [x] A3: 修复 BrightnessSliderView onChange 边界条件
  - **文件**: `BrightnessSliderView.swift` onChange(of: display.brightness)
  - **问题**: `abs(newValue - localBrightness) > 1` 用 `>` 导致恰好 1% 变化时不同步
  - **修法**: 改为 `abs(newValue - localBrightness) >= 1`
  - **验证**: 外部修改亮度 1% → UI 同步更新

- [x] A4: 修复 DDCService readBatchVCPCodes 缓存稀疏问题
  - **文件**: `DDCService.swift` readBatchVCPCodes 方法
  - **问题**: 从缓存构建字典时 compactMap 跳过缺失 code，返回结果比请求少且无提示
  - **修法**: 缓存未命中的 code 走实际读取，最终结果显式标注哪些读取失败（返回 `[UInt8: UInt16?]`）
  - **验证**: 批量读取 11 个 VCP codes → 全部返回（成功或明确失败）

- [x] A5: 修复 DisplayModeListView 分辨率切换无错误处理
  - **文件**: `DisplayModeListView.swift` switchTo 方法
  - **问题**: `ResolutionService.shared.setDisplayMode()` 失败后无重试、无用户提示
  - **修法**: 失败时显示错误 Toast（用 `@State var errorMessage`），添加一次自动重试
  - **验证**: 模拟切换失败 → 用户看到错误提示

## 批次 B: P1 — 功能异常（11 个）

- [x] B1: 修复 DisplayInfo 亮度初始值硬编码
  - **文件**: `DisplayInfo.swift` init
  - **问题**: 内建显示器亮度初始化为 50.0，不读取实际值
  - **修法**: init 完成后立即调用 `BrightnessService.shared.refreshBrightness(for: self)` 读取真实值
  - **验证**: 打开 app → 亮度滑块显示真实系统亮度

- [x] B2: 修复 GammaService 单显示器状态 key
  - **文件**: `GammaService.swift` saveState/loadSavedState
  - **问题**: UserDefaults key 固定为 `"GammaService.savedAdjustment"`，多显示器只保存最后一个
  - **修法**: key 改为 `"GammaService.savedAdjustment.\(displayID)"`
  - **验证**: 两个显示器分别调伽马 → 重启 app → 各自恢复正确值

- [x] B3: 修复 MirrorView async defer 提前执行
  - **文件**: `MirrorView.swift` toggleMirror 方法
  - **问题**: `defer { isSwitching = false }` 在 async 函数中会在 await 前执行，loading 状态瞬间消失
  - **修法**: 去掉 defer，在 await 完成后和 catch 块中分别设置 `isSwitching = false`
  - **验证**: 点击镜像按钮 → loading 动画持续到操作完成

- [x] B4: 修复 ColorProfileView loadProfiles 竞态条件
  - **文件**: `ColorProfileView.swift` loadProfiles
  - **问题**: View 消失后 async task 仍更新 @State，触发 SwiftUI 警告
  - **修法**: 用 `.task { }` 替代手动 Task（SwiftUI 自动取消），或加 `@State var loadTask: Task<Void, Never>?` 在 onDisappear 取消
  - **验证**: 快速展开/收起色彩面板 → 无控制台警告

- [x] B5: 修复 IntegratedControlView 非 MainActor 状态更新
  - **文件**: `IntegratedControlView.swift` readFromDevice
  - **问题**: 非 @MainActor 方法直接更新 @State 变量
  - **修法**: 方法标记 `@MainActor`，或用 `await MainActor.run { isReading = false }`
  - **验证**: 编译无并发警告

- [x] B6: 修复 ColorProfileView applyProfile 并发问题
  - **文件**: `ColorProfileView.swift` applyProfile
  - **问题**: 函数未标记 @MainActor 但内部更新 UI 状态
  - **修法**: 标记 `@MainActor`
  - **验证**: 应用 ICC Profile → 无并发警告

- [x] B7: 验证 HiDPIService plist 路径构造（已确认正确，无需修改）
  - **文件**: `HiDPIService.swift` overridePlistURL
  - **问题**: 审计指出 vendor/product 路径可能不正确
  - **修法**: 检查实际生成的 plist 路径与 macOS 期望路径是否匹配（`/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-XXXX/DisplayProductID-YYYY`），修正不一致处
  - **验证**: 写入 plist → `ls` 确认路径正确 → 重新枚举模式列表出现 HiDPI

- [x] B8: 修复 DisplayDetailView task 无取消
  - **文件**: `DisplayDetailView.swift` .task(id:)
  - **问题**: 显示器断开重连后旧 task 可能更新脏数据
  - **修法**: 用 `Task.checkCancellation()` 在 await 之后检查取消状态
  - **验证**: 热插拔显示器 → 详情面板数据正确

- [x] B9: 修复 RotationService 返回值不准确
  - **文件**: `RotationService.swift` setRotation
  - **问题**: 返回 `IOServiceRequestProbe` 的结果，但这只代表 probe 请求成功，不代表旋转生效
  - **修法**: probe 之后 sleep 100ms，再用 `CGDisplayRotation(displayID)` 验证实际角度
  - **验证**: 旋转显示器 → 返回值准确反映是否生效

- [x] B10: 清理 DisplayInfo.lookupDisplayName 死代码
  - **文件**: `DisplayInfo.swift` lookupDisplayName
  - **问题**: 该方法从未被调用（已被 NSScreen.localizedName 替代）
  - **修法**: 删除整个方法
  - **验证**: 编译通过

- [x] B11: 修复 ResolutionService .permanently vs .forSession 不一致
  - **文件**: `ResolutionService.swift` vs `ArrangementService.swift`
  - **问题**: 分辨率用 .permanently，排列用 .forSession，行为不一致
  - **修法**: 统一改为 `.forSession`（重启后由 macOS 恢复系统设置更安全），或两者都用 `.permanently` 并在文档中说明
  - **验证**: 切换分辨率/排列 → 重启后行为符合预期

## 批次 C: P2 — 小问题/代码质量（21 个）

- [x] C1: AutoBrightnessService readAmbientLux 可能阻塞主线程
  - **修法**: 确保从后台线程调用，或方法内 dispatch 到 background queue

- [x] C2: AutoBrightnessService lux 缩放常量无文档
  - **修法**: 添加注释说明 `rawAvg / 1_000_000.0 * 1_000.0` 的推导依据

- [x] C3: BrightnessSliderView DispatchAfter 无取消
  - **修法**: 用 `DispatchWorkItem` 替代，或用 SwiftUI `.task` + `Task.sleep`

- [x] C4: ColorProfileService ICC header 假设 ASCII
  - **修法**: 添加 encoding 校验，非 ASCII 时 fallback

- [x] C5: DDCService buffer count 捕获脆弱
  - **修法**: 内联 count 或提取 helper 方法

- [x] C6: DisplayModeListView 冗余过滤逻辑
  - **修法**: `.filter { $0.isNative || (!$0.isHiDPI && $0.isNative) || ($0.isNative) }` 简化为 `.filter { $0.isNative }`

- [x] C7: ImageAdjustmentView quantization 边界条件
  - **修法**: `quantLevels >= 256` 改为 `quantLevels >= 255` 或 `== 256`

- [x] C8: ImageAdjustmentView resetAll 缺 MainActor 保证
  - **修法**: 确认 GammaService.restoreColorSync() 在 MainActor 上调用

- [x] C9: MenuBarView update check 可能阻塞 UI
  - **修法**: 添加 timeout、移到后台执行

- [x] C10: HiDPIService refreshModes 未 await
  - **修法**: 存储 Task 引用并在适当时候取消

- [x] C11: DDCService lock 释放与 callback 顺序不一致
  - **修法**: 统一为"先 unlock 再 callback"模式

- [x] C12: VirtualDisplayService addAndCreate 创建失败不回滚
  - **修法**: `create()` 失败时从 configs 中移除

- [x] C13: ArrangementService .forSession 可能不是用户预期
  - **修法**: 与 B11 一起处理

- [x] C14: UpdateService JSON 解析静默失败
  - **修法**: 添加 `print("[UpdateService] JSON parse error:")` 日志

- [x] C15: BrightnessService withCheckedContinuation 过度使用
  - **修法**: 直接 dispatch async 返回，或简化为同步调用

- [x] C16: DisplayDetailView @EnvironmentObject MainActor 未显式标注
  - **修法**: 添加注释说明

- [x] C17: BrightnessSliderView @ObservedObject 并发安全
  - **修法**: 确保 DisplayInfo 更新都在主线程

- [x] C18: DDCService 内存指针理论安全问题
  - **修法**: 确认 withUnsafeMutableBytes 用法正确（已正确，标记为已审查）

- [x] C19: BrightnessService IOObjectRelease 迭代器清理
  - **修法**: 确认 iterator 完全耗尽后释放（已正确，标记为已审查）

- [x] C20: DisplayDetailView ResolutionSliderView 引用
  - **修法**: 确认组件存在，否则删除引用

- [x] C21: 全局代码清理 — 删除未使用的 import、注释掉的代码
  - **修法**: 全局扫描清理

## 验收标准

```bash
# 1. 编译无警告
xcodebuild -scheme FreeDisplay -configuration Debug build 2>&1 | grep -E "warning:|error:" | head -20

# 2. 手动测试清单
# - 打开 app → 亮度显示真实值（非 50%）
# - 热插拔显示器 → 无崩溃
# - 调伽马 → 关闭面板 → 屏幕恢复
# - 镜像操作 → loading 动画全程显示
# - 色彩 Profile 切换 → 无控制台警告
# - HiDPI 开关 → plist 写入正确路径
```
