# 踩坑经验 — IOKit

> 更新: 2026-05-23

## IOKit / DDC

- `IODisplayCreateInfoDictionary` 返回的 CF 字典中，`DisplayVendorID` 和 `DisplayProductID` 是 `Int` 类型（非 `UInt32`），需要先试 UInt32 转型，再试 Int 转型
- `IODisplayCreateInfoDictionary` 返回 `Unmanaged<CFDictionary>?`，需要 `.takeRetainedValue()` 取值（ARC 管理）
- `IOServiceGetMatchingServices` 的 matching 参数会消耗 CFDictionary 的引用，不需要手动 release
- IOKit 的 I2C 子模块是 `explicit module`，`import IOKit` 不包含 → 需要 `import IOKit.i2c`（I2C 函数）和 `import IOKit.graphics`（IODisplay*FloatParameter 函数）
- `IOI2CRequest` 在 `#pragma pack(push, 4)` 结构体内，`sendTransactionType`/`replyTransactionType` 字段类型是 `IOOptionBits`（UInt32，非 UInt8）
- `kIODisplayBrightnessKey` 是 `#define "brightness"`，Swift 不会自动 bridge 字符串宏 → 直接用 `"brightness" as CFString`
- Swift 的 `Array.withUnsafeMutableBytes` 持有 exclusive mutable borrow，closure 内不能再下标访问原数组 → 改用 raw buffer pointer (`replyRaw.bindMemory(to: UInt8.self)`) 读取数据，或在 closure 外提前捕获 `.count`
- `IOFBCopyI2CInterfaceForBus(framebuffer, busIndex, &interface)` 是比手动查 IOFramebufferI2CInterface 子节点更干净的 API，推荐使用
- `BrightnessService` 方法若要访问 `@MainActor` 隔离的 `DisplayInfo` 属性，需标记为 `@MainActor`；实际 DDC I/O 由 DDCService 内部的 ddcQueue 异步执行，不阻塞 MainActor

## IOKit / 屏幕旋转（Phase 4）

- `CGDisplayIOServicePort` 在最新 macOS SDK 中已彻底 **unavailable**（非 deprecated），直接报错，必须用 IOKit registry 遍历代替
- 替代方式：遍历 `IODisplayConnect` → 用 vendor/model 匹配 → `IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent)` 得到 IOFramebuffer（与 DDCService.framebufferService 完全相同的模式）
- 屏幕旋转：`IORegistryEntrySetCFProperty(fb, "IOFBTransform", NSNumber(value: index))` + `IOServiceRequestProbe(fb, 0x00000400)` 触发；旋转 index = 0/1/2/3 对应 0°/90°/180°/270°
- `import IOKit.graphics` 对于 `IOServiceRequestProbe` 所需的图形常量是必要的

## IOKit / 环境光传感器（Phase 11）

- `AppleLMUController` 是 IOKit 服务，通过 `IOServiceGetMatchingService` 获取；`IOServiceOpen` 打开连接后用 `IOConnectCallMethod(port, 0, nil, 0, nil, 0, &output, &outputCount, nil, &outputStructSize)` 读取两通道（左/右）传感器 UInt64 值
- `IOConnectCallMethod` 的 struct 大小参数是 `Int`（Swift 中 size_t = Int），不能传 `nil` → 必须传 `0` 或指向变量的指针（`&outputStructSize`）
- 新建 Swift 文件后，如果其他文件引用了新文件中的类型，必须先运行 `xcodegen generate` 重新生成 xcodeproj，否则"cannot find in scope"
- `@MainActor` class 的 `init` 内访问其他 `@MainActor` 类的属性时，`init` 需要也标记 `@MainActor`，否则 Swift 6 strict concurrency 报错

## IOKit 显示器匹配（Phase 13-15）

### L-003: vendor+model IOKit 匹配不可靠
- **现象**: DisplayInfo 名称显示 "Display 2"，DDC 亮度滑块无效
- **原因**: CGDisplayVendorNumber/ModelNumber 返回的值和 IOKit DisplayVendorID/DisplayProductID 不一定一致（至少在 HKC H2435Q 上不匹配），导致 IODisplayConnect 服务匹配失败
- **解法**: 名称用 NSScreen.localizedName（系统 API，最可靠）；IOKit 服务查找用 CGDisplayIOServicePort（deprecated 但仍可用）
- **教训**: 不要假设不同框架（CoreGraphics vs IOKit）对同一硬件的标识符一致。优先使用系统级 API（NSScreen）而非底层 IOKit 查找
- **日期**: 2026-03-03

### L-004: 不要对微秒级操作做 async 化
- **现象**: Phase 14 将 DisplayInfo.init 的名称查找改为 async，导致用户看到 "Display N" 闪烁然后才更新为真实名称（有时甚至不更新）
- **原因**: IOKit 名称查找只需微秒，async 化引入了竞态条件（refreshDisplays 可能被多次调用，后一次覆盖前一次的 async 结果）
- **解法**: 回滚为同步调用
- **教训**: async 化只对真正慢的操作（>100ms）有价值。对微秒级操作做 async 反而引入复杂性和 bug
- **日期**: 2026-03-03

## Apple Silicon DDC（Phase 17）

### L-005: IOFramebuffer I2C API 在 Apple Silicon 上完全不工作
- **现象**: DDC 亮度/对比度控制对所有外接显示器无效
- **原因**: `IOFBCopyI2CInterfaceForBus` / `IOI2CSendRequest` 是 Intel 时代的 IOFramebuffer API，在 Apple Silicon (M1/M2/M3/M4) 上这些函数调用静默返回但不发送任何 I2C 数据
- **解法**: 使用 IOAVService 私有 API（`IOAVServiceCreateWithService` + `IOAVServiceWriteI2C` / `IOAVServiceReadI2C`），通过 DCPAVServiceProxy IOKit 服务查找外接显示器
- **教训**: 不同 CPU 架构的 macOS 使用完全不同的显示器通信 API。MonitorControl、BetterDisplay 都用 IOAVService。参考 alinpanaitiu.com/blog/journey-to-ddc-on-m1-macs/
- **日期**: 2026-03-03

### L-028: DCPAVServiceProxy 顺序不能当作显示器顺序
- **现象**: 多台外接显示器时，点击 27G1G4 的 DDC 电源睡眠，实际进入睡眠的是 S27H85x
- **原因**: Apple Silicon 上 `DCPAVServiceProxy` 的枚举顺序会随睡眠、唤醒、重连变化；用“剩余服务按顺序分配给剩余显示器”的兜底策略会把 DDC 写命令发到错误硬件
- **解法**: 只接受可验证的映射：先尝试 DCPAVServiceProxy 父链 vendor/product；失败时用 registry path 中的 `dispextN` 对齐 `IOMobileFramebufferShim`，再用 `DisplayAttributes.ProductAttributes` 的 vendor/product/serial 与 CoreGraphics displayID 校验
- **教训**: DDC 写命令有真实硬件副作用，宁可把通道标记为不可用，也不要用顺序、索引或数组位置猜测目标显示器
- **日期**: 2026-05-23

### L-029: DDC `0xD6=0x04` 不是安全的“睡眠”
- **现象**: S27H85x 点击“睡眠”后从面板消失，并且疑似需要实体电源键才能回来
- **原因**: 当前“睡眠”按钮发送的是 VCP `0xD6=0x04`（Off / DPMS 关闭），部分显示器会断开信号链路甚至进入深度关闭；macOS 会把它从在线显示器列表移除，DDC 唤醒也随之失去通道
- **解法**: “睡眠”只发送更保守的 `0xD6=0x02`（Standby）；会断连的 Off / Hard Off 必须作为破坏性操作单独呈现并明确提示
- **教训**: UI 文案不能把 DDC Off 包装成普通睡眠。显示器电源命令应按最保守语义暴露，避免用户误触后失去软件控制路径
- **日期**: 2026-05-23

### L-030: 待机后读不到 VCP 状态不代表不能唤醒
- **现象**: S27H85x 点击“睡眠”后仍在面板里，但电源状态显示“不可读取”，唤醒按钮也被禁用
- **原因**: 待机后的显示器可能停止响应 VCP `0xD6` 读取，但仍接受 `0xD6=0x01` 写入；如果 UI 把“状态不可读”当成“所有命令不可用”，就会把用户卡在不能唤醒的状态
- **解法**: 本次会话内刚发送过睡眠/关机命令时，可以保留唤醒；但刷新、系统唤醒、显示器重连后必须重建 AVService 映射，避免使用旧通道；若唤醒失败，按显示器 UUID 记录 `fd.power.wakeFailedAfterStandby.*` 并禁用后续睡眠
- **教训**: DDC 读通道和写通道不能等价处理。对唤醒这类恢复命令，应尽量保留安全且已验证的写入路径
- **日期**: 2026-05-23

### L-031: BetterDisplay 重连后旧 AVService 缓存会变危险
- **现象**: S27H85x 经 BetterDisplay disconnect/reconnect 后重新显示，但 FreeDisplay 刷新电源状态仍不可读；此时点击“唤醒”反而可能让屏幕再次进入待机
- **原因**: BetterDisplay 的 reconnect 会重建显示链路，`CGDirectDisplayID` 可能保持不变，但底层 `DCPAVServiceProxy` / `IOAVService` 引用和 endpoint 映射已经失效。继续使用旧缓存做 DDC 写入，有概率把命令送到错误或陈旧的通道
- **解法**: 刷新电源状态、发送 DDC 电源命令、系统显示器 add/remove、系统 wake 后都必须清掉 AVService 缓存并重新做 IORegistry 身份匹配；状态不可读且不是本次 FreeDisplay 刚发送睡眠后的场景时，不再提供盲目 DDC 唤醒，改提供“重连”动作
- **教训**: `CGDirectDisplayID` 稳定不代表 IOKit 通信通道稳定。显示链路被第三方工具或系统重初始化后，所有 DDC 写入前都要重新校验目标硬件身份
- **日期**: 2026-05-23

### L-032: 电源状态读取必须先用安全 VCP 确认可用性
- **现象**: S27H85x 通过 BetterDisplay reconnect 恢复后，FreeDisplay 显示软件亮度；点击“显示器电源”的刷新按钮，显示器又进入待机/黑屏
- **原因**: 电源刷新先调用 `BrightnessService.invalidateDDCState` 清掉“DDC 不可用”缓存，再立即读取 VCP `0xD6`。这会绕过软件亮度/无 DDC 的保护，对本来已经判定为 DDC 不可靠的显示器发送 power 读取请求。后续若把读取门槛写成 `isDDCAvailable == true`，又会让刚启动时状态为 nil 的正常 DDC 显示器也无法读取电源状态
- **解法**: `DisplayPowerService.currentStatus` 调用 `BrightnessService.ensureDDCAvailability`，先用亮度 VCP `0x10` 确认 DDC 可用；只有确认成功才读取 power VCP `0xD6`。电源刷新只清 DDC transport/VCP 缓存，不清 DDC 可用性缓存；已知 DDC 不可用的显示器只允许重连/显示链路恢复动作
- **教训**: DDC 电源控制必须建立在“该显示器 DDC 已被其他安全 VCP 验证可用”的前提上。不要用 power VCP 本身来探测 DDC 是否可用
- **日期**: 2026-05-23

### L-033: DDC 电源高风险必须按显示器隔离
- **现象**: 某一台显示器的 DDC 电源命令会误控或影响其他屏，容易想到“只要有一台高风险，就禁用所有显示器的睡眠/关机”
- **原因**: 全局禁用虽然安全，但破坏了正常显示器的能力边界，也掩盖了真正的问题：DDC 通道映射没有做到足够可靠的一对一校验
- **解法**: 高风险标记必须按 `displayUUID` 持久化，只禁用该显示器自己的 DDC 睡眠/唤醒/关机；同时加强 AVService 匹配，优先使用 `dispextN` endpoint 对齐 `IOMobileFramebufferShim`，再考虑父链 vendor/product
- **教训**: 电源命令的安全边界是“目标显示器 + 已验证通信通道”，不是“当前机器所有外接显示器”。单台设备异常不能变成全局功能退化
- **日期**: 2026-05-23

### L-034: S27H85x 必须在首次 DDC 探测前进入高风险名单
- **现象**: 清空设置或首次启动后，S27H85x 仍可能在电源状态加载时触发 VCP `0x10` 亮度探测，随后才进入保护分支
- **原因**: “失败后打标”的保护只对已经发生过异常的设备有效；对已知高风险型号，第一次探测本身就是风险
- **解法**: 枚举显示器后按显示器名称识别 `S27H85x` 系列，立即写入 `fd.ddc.disabled.*` 禁用硬件 DDC，使亮度、电源刷新和强制探测都直接走软件亮度/拓扑控制路径
- **教训**: 已知高风险硬件不能依赖运行时探测得出结论；应在任何 VCP 读写前进入 denylist
- **日期**: 2026-05-23

### L-035: Mi Monitor 的 DDC 电源写入有效但读值不可信
- **现象**: Mi Monitor 发送 `0xD6=0x02` 后屏幕确实进入待机，且没有影响其他显示器；但随后读取 `0xD6` 又返回 `0x01`（开机），并且 `max=0xFF`，不像标准枚举范围 `0x01...0x05`。继续发送 `0xD6=0x01` 时 I2C 写入也返回成功，但面板没有实际恢复画面
- **原因**: 该显示器固件接受 DDC Power Mode 写入，但 `0xD6` 读回值和 wake 写入确认都不能可靠表达面板/背光实际状态。报告里 EDID 层声明 `Supports Standby: 1`，但不支持 Suspend/Active Off，因此只能把 Standby 当作可写动作，不能把后续 `0x01` 或 wake 写入 ACK 当成高可信状态
- **解法**: 引入电源状态来源和可信度：正常 DDC、DDC 读值不可靠、DDC 高风险拓扑三档。对 Mi Monitor 这类 wake ACK 不可信设备，电源控制改用拓扑断开/重连；普通 DDC 亮度不禁用。拓扑重连若发现显示器仍在线启用，先执行一次断开再重连，强制重建显示链路
- **教训**: DDC 写成功、DDC 读成功、显示器真实视觉状态是三类信号。Power VCP 必须带来源和可信度建模，不能用单个 `status.mode == .on` 决定 UI 和恢复路径
- **日期**: 2026-05-23
