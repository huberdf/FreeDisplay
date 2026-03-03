# Phase 2: 亮度控制（DDC + 内建） ✅

> 核心价值：最常用的功能——亮度滑块控制外接和内建显示器

## 任务列表

- [x] 实现 DDC/CI I2C 底层通信 (`FreeDisplay/Services/DDCService.swift`)
  - 实现提示：
    1. 通过 `IOServiceGetMatchingServices` + `IOFramebufferI2CInterface` 找到 I2C 端口
    2. 通过 `CGDirectDisplayID` → `IOServicePortFromCGDisplayID` 映射到 I2C 服务
       （需要遍历 IOKit registry 匹配 display vendorID/productID）
    3. 打开 I2C 连接：`IOI2CInterfaceOpen`
    4. 构造 DDC/CI 读写请求：
       - 写：地址 0x37，前缀 0x51 0x80+len，VCP opcode 0x03（set）+ VCP code + value
       - 读：先写请求（opcode 0x01 get + VCP code），再读响应解析 current/max value
    5. 关闭连接：`IOI2CInterfaceClose`
    6. 关键函数签名：
       `func read(displayID: CGDirectDisplayID, command: UInt8) -> (current: UInt16, max: UInt16)?`
       `func write(displayID: CGDirectDisplayID, command: UInt8, value: UInt16) -> Bool`
    7. 添加错误处理和重试机制（DDC 通信不稳定，重试 3 次间隔 50ms）
    注意：DDC 通信需要在后台线程执行，避免阻塞 UI。
    参考 MonitorControl 开源项目的 DDC 实现思路。
  - 验证：`DDCService.shared.read(displayID: externalID, command: 0x10)` 返回当前亮度值

- [x] 实现内建显示器亮度控制 (`FreeDisplay/Services/BrightnessService.swift`)
  - 实现提示：
    内建显示器不走 DDC。使用 `IODisplaySetFloatParameter` + `kIODisplayBrightnessKey`。
    获取：`IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey, &brightness)`
    设置：`IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey, brightness)`
    service 通过 `IOServiceGetMatchingService` + `IODisplayConnect` 获取。
    值范围 0.0-1.0，需转换为百分比显示。
  - 验证：代码修改亮度值后内建屏幕亮度实际变化

- [x] 实现亮度滑块 UI (`FreeDisplay/Views/BrightnessSliderView.swift`)
  - 实现提示：
    水平 Slider，左侧太阳图标(☀)，右侧显示百分比数值。
    仿照 BetterDisplay 截图"亮度 (组合)"区域的布局。
    `@Binding var brightness: Double`（0-100）。
    Slider 的 `onEditingChanged` 回调中调用 DDCService/BrightnessService。
    添加 debounce（200ms）避免频繁 DDC 通信。
    支持"组合亮度"模式：一个滑块同时控制所有显示器的亮度（按比例映射）。
  - 验证：拖动滑块外接显示器亮度实际变化

- [x] 集成亮度控制到菜单 (`FreeDisplay/Views/MenuBarView.swift`)
  - 实现提示：
    在显示器列表下方添加"亮度 (组合)"区域，包含一个组合亮度滑块。
    每个显示器展开后也有独立的亮度滑块。
    `DisplayInfo` 增加 `brightness: Double` 属性，启动时通过 DDC read 初始化。
  - 验证：菜单中显示亮度滑块，拖动后显示器亮度变化

## Phase 验收

- 外接显示器 DDC 亮度读取和设置工作正常
- 内建显示器亮度读取和设置工作正常
- UI 滑块拖动流畅，无明显延迟
- 组合亮度模式可同时控制多屏

**完成后**: 建议运行 project-optimize 反思
