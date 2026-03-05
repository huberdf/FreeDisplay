# 踩坑经验 — IOKit

> 更新: 2026-03-05

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
