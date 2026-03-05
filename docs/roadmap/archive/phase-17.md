# Phase 17: 核心功能专项修复 — DDC/HiDPI/刘海

> 目标：修复三个影响核心体验的技术性问题：Apple Silicon DDC 亮度控制不可用、外接 2K 显示器 HiDPI 虚拟显示创建失败、以及刘海遮罩 NSWindow 崩溃

## 前置说明

本 Phase 涉及私有 API bridging header 和两个底层服务的重写，任务间有依赖顺序：
**Task 1（bridging header）必须先于 Task 2、3**；Task 4（刘海崩溃）独立，可与 Task 1 并行启动；Task 5（集成测试）最后进行。

---

## 任务列表

- [x] **Task 1**: 创建 Objective-C Bridging Header（DDC + 虚拟显示器私有 API 共同前置）
  - 实现提示：
    1. 在项目根目录创建 `FreeDisplay/FreeDisplay-Bridging-Header.h`，声明以下内容：

       ```objc
       // ── CGVirtualDisplay 私有类（macOS 14+ 虚拟显示器）──────────────────────
       #import <Foundation/Foundation.h>
       #import <CoreGraphics/CoreGraphics.h>

       @interface CGVirtualDisplayDescriptor : NSObject
       @property (nonatomic) uint32_t sizeInMillimeters;   // 对角线尺寸（毫米）
       @property (nonatomic) CGSize   maxPixelSize;        // 最大像素分辨率
       @property (nonatomic) CGColorSpaceRef colorSpace;
       @property (nonatomic) NSPoint  whitePoint;
       @property (nonatomic) NSPoint  redPrimary;
       @property (nonatomic) NSPoint  greenPrimary;
       @property (nonatomic) NSPoint  bluePrimary;
       @end

       @interface CGVirtualDisplaySettings : NSObject
       @property (nonatomic) BOOL hiDPI;
       - (void)addMode:(CGSize)size refreshRate:(double)hz;
       @end

       @interface CGVirtualDisplayMode : NSObject
       @property (nonatomic, readonly) CGSize  size;
       @property (nonatomic, readonly) double  refreshRate;
       @property (nonatomic, readonly) BOOL    hiDPI;
       @end

       @interface CGVirtualDisplay : NSObject
       - (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
       - (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
       @property (nonatomic, readonly) CGDirectDisplayID displayID;
       @end

       // ── CGSDisplayMode（高级分辨率切换）──────────────────────────────────────
       typedef struct {
           uint32_t modeID;
           uint32_t width;
           uint32_t height;
           uint32_t depth;
           double   refreshRate;
           uint32_t flags;        // bit 0x20000 = HiDPI
       } CGSDisplayMode;

       extern CGError CGSConfigureDisplayMode(CGSConnectionID connection, CGDirectDisplayID display, uint32_t modeID);
       extern CGSConnectionID CGSMainConnectionID(void);

       // ── CoreDisplay（可选，供未来参考）────────────────────────────────────────
       // extern CFDictionaryRef CoreDisplay_DisplayCreateInfoDictionary(CGDirectDisplayID display);

       // ── IOAVService（Apple Silicon DDC）──────────────────────────────────────
       typedef void * IOAVServiceRef;
       extern IOAVServiceRef IOAVServiceCreate(CFAllocatorRef allocator);
       extern IOAVServiceRef IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service);
       extern IOReturn IOAVServiceReadI2C(IOAVServiceRef service,
                                          uint32_t chipAddress,
                                          uint32_t offset,
                                          void *outputBuffer,
                                          uint32_t outputBufferSize);
       extern IOReturn IOAVServiceWriteI2C(IOAVServiceRef service,
                                           uint32_t chipAddress,
                                           uint32_t dataAddress,
                                           void *inputBuffer,
                                           uint32_t inputBufferSize);
       ```

    2. 打开 `project.yml`，在 `targets.FreeDisplay.settings.base` 下添加：
       ```yaml
       SWIFT_OBJC_BRIDGING_HEADER: FreeDisplay/FreeDisplay-Bridging-Header.h
       ```
    3. 运行 `cd ~/Desktop/FreeDisplay && xcodegen generate`
    4. 运行验证链确认编译通过（bridging header 空用也不应报错）
  - 验证：`xcodebuild -scheme FreeDisplay -configuration Debug build 2>&1 | tail -5` 显示 `BUILD SUCCEEDED`

---

- [x] **Task 2**: 重写 DDCService 支持 Apple Silicon（IOAVService 路径）
  - 背景：现有 `IOFBCopyI2CInterfaceForBus` + `IOI2CSendRequest` 是 Intel 时代 API，在 Apple Silicon 上完全无法工作。需要新增 ARM64 路径，保留 Intel 路径作为兜底（Hackintosh/VM 用户）。
  - 实现提示：
    1. **新增 ARM64 DDC 写方法**（`DDCService.swift`）：
       ```swift
       // 在 DDCService 顶部，ARM64 专用路径
       #if arch(arm64)
       private func findAVService(for displayID: CGDirectDisplayID) -> IOAVServiceRef? {
           // 1. 通过 CGDisplayIOServicePort 获取显示器对应的 IOService
           let port = CGDisplayIOServicePort(displayID)
           guard port != IO_OBJECT_NULL else { return nil }

           // 2. 向上遍历 IORegistry 父节点，找到 DCPAVServiceProxy
           var iterator: io_iterator_t = 0
           let matchDict = IOServiceMatching("DCPAVServiceProxy")
           IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iterator)
           defer { IOObjectRelease(iterator) }

           var service = IOIteratorNext(iterator)
           while service != IO_OBJECT_NULL {
               defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
               let avService = IOAVServiceCreateWithService(kCFAllocatorDefault, service)
               // 用一个无害的读测试确认是否是正确的 AVService
               var testBuf = [UInt8](repeating: 0, count: 12)
               let ret = IOAVServiceReadI2C(avService, 0x37, 0x51, &testBuf, 12)
               if ret == kIOReturnSuccess { return avService }
           }
           return nil
       }

       /// ARM64 DDC write: 向外接显示器写 VCP 值（如亮度 VCP=0x10）
       private func arm64Write(displayID: CGDirectDisplayID, command: UInt8, value: UInt16) -> Bool {
           guard let avService = findAVService(for: displayID) else { return false }
           // DDC/CI 写包格式（注意：dataAddress=0x51 作为参数传入，不放进 buffer）
           // buffer: [0x84, 0x03, vcpCode, valueHigh, valueLow, checksum]
           let valueHigh = UInt8((value >> 8) & 0xFF)
           let valueLow  = UInt8(value & 0xFF)
           var checksum  = UInt8(0x50 ^ 0x03 ^ command ^ valueHigh ^ valueLow)
           // 0x50 = 0x51 XOR'd with 0x01 (reply flag) — 参考 DDC/CI spec
           var buf: [UInt8] = [0x84, 0x03, command, valueHigh, valueLow, checksum]
           let ret = IOAVServiceWriteI2C(avService, 0x37, 0x51, &buf, UInt32(buf.count))
           return ret == kIOReturnSuccess
       }

       /// ARM64 DDC read: 读取 VCP 当前值
       private func arm64Read(displayID: CGDirectDisplayID, command: UInt8) -> (current: UInt16, max: UInt16)? {
           guard let avService = findAVService(for: displayID) else { return nil }
           // 先发送 VCP 请求包（与 write 类似，opcode=0x01）
           var requestChecksum = UInt8(0x51 ^ 0x82 ^ 0x01 ^ command)
           var requestBuf: [UInt8] = [0x82, 0x01, command, requestChecksum]
           IOAVServiceWriteI2C(avService, 0x37, 0x51, &requestBuf, UInt32(requestBuf.count))
           // 等待 DDC 处理
           Thread.sleep(forTimeInterval: 0.04)
           // 读取响应
           var replyBuf = [UInt8](repeating: 0, count: 12)
           let ret = IOAVServiceReadI2C(avService, 0x37, 0x51, &replyBuf, 12)
           guard ret == kIOReturnSuccess else { return nil }
           // replyBuf 格式：[len, 0x02, vcpCode, 0x00, maxHigh, maxLow, curHigh, curLow, ...]
           let maxVal  = UInt16(replyBuf[4]) << 8 | UInt16(replyBuf[5])
           let curVal  = UInt16(replyBuf[6]) << 8 | UInt16(replyBuf[7])
           return (curVal, maxVal)
       }
       #endif
       ```

    2. **修改 `write(displayID:command:value:)` 分发逻辑**：
       ```swift
       func write(displayID: CGDirectDisplayID, command: UInt8, value: UInt16) -> Bool {
           #if arch(arm64)
           if arm64Write(displayID: displayID, command: command, value: value) {
               return true
           }
           // arm64 失败时可选降级到软件路径
           return false
           #else
           return intelWrite(displayID: displayID, command: command, value: value)
           #endif
       }
       ```
       将现有 Intel 路径的方法重命名为 `intelWrite` / `intelRead`（函数签名不变，只改名）。

    3. **在 `BrightnessService.swift` 添加软件亮度降级**：
       - 新增 `var isDDCAvailable: [CGDirectDisplayID: Bool] = [:]` 缓存
       - `setBrightness(for:value:)` 中：先尝试 DDC 写；若失败且是外接显示器，调用 `applyGammaFallback(displayID:brightness:)` 使用 `CGSetDisplayTransferByTable` 模拟亮度
       - `applyGammaFallback` 实现：构建从 0 到 `brightness`（0.0-1.0）的线性 ramp 写入 gamma table，视觉上等效于调低亮度（黑色电平不动，白色电平降低）
       - 记录 `isDDCAvailable[displayID] = false` 后续直接走软件路径，不再尝试 DDC

    4. **在 `BrightnessSliderView.swift` 添加模式指示**（可选但推荐）：
       - 在滑块标题旁添加小标签：DDC 可用时显示 "DDC" (蓝色)，软件模式显示 "Software" (灰色)
       - 实现：从 `BrightnessService.shared.isDDCAvailable[display.id]` 读取状态

  - 文件：`FreeDisplay/Services/DDCService.swift`（新增 `#if arch(arm64)` 块，现有 Intel 代码重命名）
  - 文件：`FreeDisplay/Services/BrightnessService.swift`（新增软件降级逻辑）
  - 文件：`FreeDisplay/Views/BrightnessSliderView.swift`（可选：模式指示标签）
  - 参考：MonitorControl `Arm64DDC.swift`、`m1ddc` 项目、alinpanaitiu.com/blog/journey-to-ddc-on-m1-macs/
  - 验证：外接显示器亮度滑块拖动 → 显示器亮度实际变化（DDC 成功）；DDC 不支持的显示器 → 自动降级到软件调光，滑块仍可用，标签显示 "Software"

---

- [x] **Task 3**: 实现真实虚拟显示器创建（CGVirtualDisplay API）
  - 背景：`VirtualDisplayService.swift` 的 `create(config:)` 和 `destroy(id:)` 当前只有占位返回 `false`，导致 HiDPI 虚拟显示功能完全不可用。需用 bridging header 暴露的 `CGVirtualDisplay` 私有类完成实现。
  - 实现提示：
    1. **在 `VirtualDisplayService.swift` 实现 `create(config:)`**：
       ```swift
       // 保存强引用，释放 = 虚拟显示器消失
       private var activeDisplayObjects: [CGDirectDisplayID: CGVirtualDisplay] = [:]

       func create(config: VirtualDisplayConfig) -> CGDirectDisplayID? {
           let descriptor = CGVirtualDisplayDescriptor()
           descriptor.sizeInMillimeters = 527  // 24英寸对角线约 527mm（可按 config 调整）
           descriptor.maxPixelSize = CGSize(width: CGFloat(config.width), height: CGFloat(config.height))
           descriptor.colorSpace   = CGColorSpace(name: CGColorSpace.sRGB)!
           // sRGB 色域基准值
           descriptor.whitePoint   = NSPoint(x: 0.3127, y: 0.3290)
           descriptor.redPrimary   = NSPoint(x: 0.6400, y: 0.3300)
           descriptor.greenPrimary = NSPoint(x: 0.3000, y: 0.6000)
           descriptor.bluePrimary  = NSPoint(x: 0.1500, y: 0.0600)

           let settings = CGVirtualDisplaySettings()
           settings.hiDPI = config.hiDPI
           // 添加主模式（实际像素尺寸）
           settings.addMode(CGSize(width: CGFloat(config.width), height: CGFloat(config.height)),
                            refreshRate: Double(config.refreshRate))
           // 若 hiDPI，同时添加逻辑分辨率模式（物理的一半）
           if config.hiDPI {
               settings.addMode(CGSize(width: CGFloat(config.width / 2),
                                       height: CGFloat(config.height / 2)),
                                refreshRate: Double(config.refreshRate))
           }

           let virtualDisplay = CGVirtualDisplay(descriptor: descriptor)
           guard virtualDisplay.applySettings(settings) else { return nil }
           let displayID = virtualDisplay.displayID
           guard displayID != kCGNullDirectDisplay else { return nil }
           activeDisplayObjects[displayID] = virtualDisplay  // 保持强引用
           return displayID
       }

       func destroy(id: CGDirectDisplayID) {
           activeDisplayObjects.removeValue(forKey: id)  // 释放 → 虚拟显示消失
       }
       ```

    2. **实现 `enableHiDPIVirtual(for:physicalWidth:physicalHeight:)`**：
       ```swift
       /// 为物理外接显示器创建 2x 虚拟显示器并镜像，实现 HiDPI 缩放
       func enableHiDPIVirtual(for displayID: CGDirectDisplayID,
                                physicalWidth: Int,
                                physicalHeight: Int) -> CGDirectDisplayID? {
           let config = VirtualDisplayConfig(
               name: "HiDPI Virtual",
               width: physicalWidth * 2,   // 2x 物理分辨率，如 2K→4K
               height: physicalHeight * 2,
               refreshRate: 60,
               hiDPI: true
           )
           guard let virtualID = create(config: config) else { return nil }
           // 将物理显示器镜像到虚拟显示器（物理作为 mirror source，虚拟作为 mirror target）
           MirrorService.shared.startMirror(source: displayID, target: virtualID)
           return virtualID
       }
       ```

    3. **实现 `disableHiDPIVirtual(for:)`**：
       ```swift
       func disableHiDPIVirtual(for physicalDisplayID: CGDirectDisplayID) {
           // 找到与此物理显示器关联的虚拟显示器
           guard let virtualID = hiDPIVirtualMap[physicalDisplayID] else { return }
           MirrorService.shared.stopMirror(for: virtualID)
           destroy(id: virtualID)
           hiDPIVirtualMap.removeValue(forKey: physicalDisplayID)
       }
       // 需要在 VirtualDisplayService 新增: private var hiDPIVirtualMap: [CGDirectDisplayID: CGDirectDisplayID] = [:]
       // enableHiDPIVirtual 返回 virtualID 后记录: hiDPIVirtualMap[displayID] = virtualID
       ```

    4. **更新 `HiDPIService.swift`**：
       - `enableHiDPI(for:)` 改为先尝试虚拟显示器路径（`VirtualDisplayService.shared.enableHiDPIVirtual`）
       - 若失败（如权限不足），再退回到 plist override 路径
       - 在 UI 中区分两种路径：虚拟显示器路径立即生效，plist 路径需要重连显示器

  - 文件：`FreeDisplay/Services/VirtualDisplayService.swift`（主要实现，替换占位 false）
  - 文件：`FreeDisplay/Services/HiDPIService.swift`（切换 primary/fallback 路径）
  - 注意：`CGVirtualDisplay` 对象必须保持强引用（存到 `activeDisplayObjects` 字典），一旦 ARC 释放，虚拟显示器立即消失
  - 注意：`CGVirtualDisplayDescriptor.colorSpace` 是 `CGColorSpaceRef`（Core Foundation），在 Swift 里用 `CGColorSpace(name:)` 创建后直接赋值，不需要手动 retain
  - 参考：BetterDummy 项目 bridging header、KhaosT/CGVirtualDisplay 示例
  - 验证：HiDPI 开关打开 → 系统显示器列表出现新的"HiDPI Virtual"显示器 → 分辨率列表出现 `1920×1080 (HiDPI)` 等缩放模式 → 关闭开关 → 虚拟显示器消失

---

- [x] **Task 4**: 修复刘海遮罩窗口崩溃（NSWindow 生命周期）
  - 背景：`NotchOverlayManager` 创建的 `NSWindow` 缺少 `isReleasedWhenClosed = false`，导致关闭时 Swift 持有悬空指针；`@State isHidingNotch` 与 manager 状态不同步；新窗口在旧窗口未关闭前创建引发顺序问题；`onChange` 使用了已废弃的单参数形式。
  - 实现提示：
    1. **`NotchOverlayManager.swift`** — 窗口创建修复：
       ```swift
       // 在 showOverlay(for:) 方法中，window 初始化后立即添加：
       window.isReleasedWhenClosed = false  // ← 关键：防止 close() 后指针悬空
       ```

    2. **`NotchOverlayManager.swift`** — 关闭顺序修复：
       ```swift
       func showOverlay(for screen: NSScreen) {
           // 先关闭旧窗口，再创建新窗口
           if let existing = overlayWindows[screen.displayID] {
               existing.close()
               overlayWindows.removeValue(forKey: screen.displayID)
           }
           // ... 然后再创建新 window
       }
       ```

    3. **`NotchOverlayManager.swift`** — 新增查询方法：
       ```swift
       public func isShowingOverlay(for screen: NSScreen) -> Bool {
           return overlayWindows[screen.displayID] != nil
       }
       ```

    4. **`NotchView.swift`** — 状态同步修复：
       ```swift
       // 在 body 或 .onAppear 中从 manager 同步初始状态：
       .onAppear {
           isHidingNotch = NotchOverlayManager.shared.isShowingOverlay(for: screen)
       }
       ```

    5. **`NotchView.swift`** — onChange 废弃 API 修复：
       ```swift
       // 旧（废弃单参数形式）：
       // .onChange(of: isHidingNotch) { newValue in ... }
       // 改为双参数形式：
       .onChange(of: isHidingNotch) { _, newValue in
           // 处理逻辑不变
       }
       ```

  - 文件：`FreeDisplay/Services/NotchOverlayManager.swift`
  - 文件：`FreeDisplay/Views/NotchView.swift`（若存在；否则在包含刘海 Toggle 的 View 文件中修改）
  - 验证：刘海开关反复 ON/OFF 十次 → 不崩溃；关闭菜单再重新打开 → 刘海开关状态与实际遮罩状态一致；Console.app 中无 EXC_BAD_ACCESS 或 objc over-release 日志

---

- [x] **Task 5**: 集成测试与 UI 更新
  - 实现提示：
    1. **DDC 验证**：外接 HKC H2435Q 接入 → 打开 FreeDisplay → 拖动亮度滑块 → 观察显示器物理亮度是否变化（可用眼睛判断或查看 IntegratedControlView 的 DDC 读值是否有回显）
    2. **HiDPI 验证**：外接 2K 显示器 → 打开 HiDPI 开关 → 系统偏好设置"显示器"中查看是否出现新的虚拟显示器 → 分辨率列表中是否出现 `1920×1080 (Retina)` → 选择该分辨率 → 文字是否明显更清晰
    3. **刘海验证**：内建 MacBook 屏幕 → 刘海开关 ON → 遮罩出现 → OFF → 遮罩消失 → 重复 10 次 → 不崩溃；关闭菜单再打开 → 状态一致
    4. **更新 `DisplayDetailView.swift` / `MenuBarView.swift`**（按需）：
       - 若 DDC 软件降级，在亮度控件区显示软件模式提示
       - 若 HiDPI 虚拟显示器激活，显示"HiDPI 已启用（虚拟显示器）"状态
    5. **更新 `docs/BLOCKING.md`**：
       - 将 B-002（DDC Apple Silicon 不可用）标记为已解决，移至"已解决区"
       - 将 B-003（HiDPI 虚拟显示器创建失败）标记为已解决，移至"已解决区"
  - 文件：`FreeDisplay/Views/DisplayDetailView.swift`（按需小改）
  - 文件：`FreeDisplay/Views/MenuBarView.swift`（按需小改）
  - 文件：`docs/BLOCKING.md`（移动已解决项）
  - 验证：见上三条手动测试；编译无警告无错误

---

## Phase 验收

```bash
# 1. 编译检查
cd ~/Desktop/FreeDisplay && xcodebuild -scheme FreeDisplay -configuration Debug build 2>&1 | tail -5

# 2. 手动测试清单：
# [ ] DDC: 外接显示器亮度滑块 → 屏幕亮度实际变化（或软件模式标签正确显示）
# [ ] HiDPI: HiDPI 开关 ON → 虚拟显示器出现 → 1920x1080@2x 可选 → OFF → 虚拟显示器消失
# [ ] 刘海: 刘海开关 ON/OFF × 10 次 → 不崩溃 → 状态与遮罩一致
# [ ] 菜单重开: 所有上述开关状态在关闭重开菜单后保持正确
```

**Phase 验收标准**：编译通过 + 以上四条手动测试全部满足
