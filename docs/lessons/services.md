# 踩坑经验 — 跨 Service 协作 / 并发 / 资源管理

> 更新: 2026-03-05

## 功能交互 / 跨 Service 协作（Round 3-4 优化）

### L-008: 两个 Service 写同一 CoreGraphics 资源会互相覆盖
- **现象**: 设置 gamma 调整后拖动亮度滑块，gamma 效果消失（或反之）
- **原因**: GammaService 和 BrightnessService 都调用 CGSetDisplayTransfer*，后调用的完全覆盖前者
- **解法**: 指定 GammaService 为唯一写入者；BrightnessService 把亮度因子存入 softwareBrightnessFactors，GammaService 在 applyFormula 里读取并乘入 rHi/gHi/bHi
- **教训**: 两个 Service 共享底层资源时，必须指定唯一所有者，其他方通过接口影响而不是直接写
- **日期**: 2026-03-04

### L-009: macOS 睡眠/唤醒会重置所有 CGSetDisplayTransfer* 效果
- **现象**: gamma 调整和软件亮度在 Mac 睡眠后全部丢失
- **原因**: macOS 睡眠时重置 display transfer function 到系统默认值，CGSetDisplayTransfer* 效果不持久
- **解法**: 注册 NSWorkspace.didWakeNotification，唤醒后延迟 500ms 对所有显示器重新 apply
- **教训**: 写 display 硬件状态的功能都必须考虑睡眠唤醒后重置，测试要覆盖此场景
- **日期**: 2026-03-04

### L-010: CGDisplayRegisterReconfigurationCallback 必须用 passRetained
- **现象**: 理论 crash 风险：C 回调访问悬空指针
- **原因**: passUnretained 不增加引用计数，self 被释放后回调访问悬空指针
- **解法**: passRetained + 配对 release（在 stopMonitoring/deinit 里）
- **教训**: 传给 C 回调的 self 指针一律用 passRetained，项目中已出现两次（DisplayManager + ConfigProtectionService）
- **日期**: 2026-03-04

### L-011: AutoBrightness 与手动调节必须有 cooldown 机制
- **现象**: 手动调亮度 2 秒后被 AutoBrightness 覆盖
- **原因**: applyBrightness 只检查差值，没有"用户最近手动操作"保护
- **解法**: setBrightness 增加 isAutoAdjust 参数，手动调用时记录 lastManualAdjustDate，AutoBrightness 检查 30s cooldown
- **教训**: 自动调节功能必须有手动干预后的暂停机制
- **日期**: 2026-03-04

## 并发 / 资源管理（Round 5 优化）

### L-012: GammaService activeAdjustments 字典必须加锁
- **现象**: 数据竞争风险——BrightnessService 从 background queue 读 hasActiveAdjustment，GammaService 从 MainActor 写 activeAdjustments
- **原因**: 字典无同步保护，多线程并发读写是 Swift 的 undefined behavior（可能崩溃或数据损坏）
- **解法**: 新增 NSLock，所有 activeAdjustments 读写都加锁（hasActiveAdjustment/apply/reapply/reset 等）
- **教训**: 凡是被多个 Actor 访问的可变状态，无论是否当前触发了 race，都必须加锁
- **日期**: 2026-03-04

### L-013: GammaService 量化路径必须同步 brightness factor
- **现象**: 软件亮度在量化模式（quantizationLevels < 256）下静默失效
- **原因**: applyFormula 读取 softwareBrightness factor，applyQuantizedTable 没有读取，两路径不一致
- **解法**: applyQuantizedTable 同样读取 brightnessFactor 并缩放 rHi/gHi/bHi
- **教训**: 同一 Service 有多条执行路径时，所有路径都必须应用相同的修改逻辑
- **日期**: 2026-03-04

### L-014: 睡眠唤醒时 BrightnessService 必须在 GammaService 之前 reapply
- **现象**: 屏幕唤醒时短暂闪白（满亮度）后才恢复
- **原因**: 先调 GammaService.reapply 时 softwareBrightnessFactors 尚未恢复，applyFormula 读到 1.0 写入硬件
- **解法**: 唤醒时先 BrightnessService.reapply，再 GammaService.reapply（确保 factor 已就绪）
- **教训**: 有依赖关系的 reapply 必须按依赖顺序调用；BrightnessService 是 GammaService 的数据提供方
- **日期**: 2026-03-04

### L-015: NSWindow 关闭必须停止关联的 SCStream
- **现象**: 用户点 PiP/Stream 窗口的红色关闭按钮，串流仍在后台运行耗资源
- **原因**: NSWindowController 未实现 NSWindowDelegate.windowWillClose，关闭事件不触发 stopCapture
- **解法**: PiPWindowController/StreamWindowController 实现 windowWillClose → viewModel.stopCapture()，同时设 window.delegate = self
- **教训**: 系统提供的关闭入口（红色按钮）和 app 内关闭按钮都要清理资源，不能只处理其中一个
- **日期**: 2026-03-04

### L-016: 遍历 Dictionary 时禁止同时调用 removeValue
- **现象**: NotchOverlayManager.screenParametersChanged() 遍历 overlayWindows 时调用 removeValue，潜在崩溃
- **原因**: Swift Dictionary 不支持在 for-in 迭代过程中修改自身，行为未定义
- **解法**: 收集待删 key 到临时数组，循环外统一删除
- **教训**: 任何 for-in 遍历集合时，不能对该集合做增删操作（同语言里的 ConcurrentModificationException 等价问题）
- **日期**: 2026-03-04

### L-017: UserDefaults key 必须有应用命名空间前缀
- **现象**: SettingsService/AutoBrightnessService/ConfigProtectionService 用裸 key（如 "launchAtLogin"）
- **原因**: 裸 key 可能与 macOS 系统 defaults 或未来第三方库冲突，导致读到意外值或覆盖系统设置
- **解法**: 统一加 `fd.` 前缀（fd.launchAtLogin, fd.AutoBrightnessEnabled 等）
- **教训**: UserDefaults key 命名规范：`<app_prefix>.<key>`
- **日期**: 2026-03-04

### L-018: Mirror source/target API 查询方向
- **现象**: refreshMirrorState 用 CGDisplayMirrorsDisplay(source) 查询，永远返回 nil（source 不克隆任何人）
- **原因**: CGDisplayMirrorsDisplay(X) 返回"X 克隆的目标"，而 SOURCE 本身不是克隆者
- **解法**: 反向查询——遍历所有显示器，找 CGDisplayMirrorsDisplay(candidate) == source 的那个（即 target）
- **教训**: Mirror API 语义：SOURCE 是被克隆的，TARGET 才是克隆者；查询应该从 TARGET 视角（"谁在克隆我"）
- **日期**: 2026-03-04

### L-019: IOPMAssertion 必须先 release 再创建新 assertion
- **现象**: ManageDisplayView 每次打开防睡眠开关都泄漏一个 IOPMAssertion，旧 ID 被覆盖无法 release
- **原因**: createSleepAssertion() 未检查 sleepAssertionID != 0，直接覆盖
- **解法**: 创建前先 release 旧 assertion；onDisappear 只在 !preventSleep 时 release（保持开关 ON 时持续生效）
- **教训**: 系统资源（IOPMAssertion、IO iterator 等）必须严格配对 create/release，覆盖 ID 前先 release 旧的
- **日期**: 2026-03-04
