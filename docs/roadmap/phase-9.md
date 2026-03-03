# Phase 9: 屏幕串流与画中画 ✅

> 核心价值：BetterDisplay 最高级的功能——屏幕串流到窗口 + 画中画浮动窗口

## 任务列表

- [x] 实现屏幕捕获引擎 (`FreeDisplay/Services/ScreenCaptureService.swift`)
  - 实现提示：
    使用 ScreenCaptureKit（macOS 12.3+）：
    ```swift
    import ScreenCaptureKit

    // 1. 获取可共享内容
    let content = try await SCShareableContent.current
    let display = content.displays.first { $0.displayID == targetDisplayID }

    // 2. 创建过滤器和配置
    let filter = SCContentFilter(display: display!, excludingWindows: [])
    let config = SCStreamConfiguration()
    config.width = Int(display!.width)
    config.height = Int(display!.height)
    config.minimumFrameInterval = CMTime(value: 1, timescale: 60) // 60fps
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.showsCursor = true

    // 3. 创建并启动流
    let stream = SCStream(filter: filter, configuration: config, delegate: self)
    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global())
    try await stream.startCapture()
    ```
    输出 `CMSampleBuffer` → 转 `CIImage` → 传给视图层渲染。
    需要屏幕录制权限：首次使用弹出授权对话框。
  - 验证：启动捕获后能获取到显示器画面帧

- [x] 实现串流窗口 (`FreeDisplay/Views/StreamWindow.swift`)
  - 实现提示：
    创建独立 NSWindow 显示捕获画面：
    - `NSWindow(contentRect:, styleMask: [.titled, .closable, .resizable], ...)`
    - 内容用 `MetalView`（MTKView）或 `CAMetalLayer` 高性能渲染 CMSampleBuffer
    - 或使用 SwiftUI `Image` 从 CIImage 转换（性能较低，但简单）
    推荐 Metal 渲染路径：
    ```swift
    class MetalStreamView: MTKView {
        // 将 CMSampleBuffer → CVPixelBuffer → MTLTexture → 渲染
    }
    ```
    窗口支持：调整大小时按比例缩放内容。
  - 验证：串流窗口实时显示目标显示器画面

- [x] 实现串流选项 (`FreeDisplay/ViewModels/StreamViewModel.swift`)
  - 实现提示：仿照 BetterDisplay 截图的屏幕串流区域，实现以下选项：
    - 显示鼠标指针：`config.showsCursor = true/false`
    - 1:1 像素映射：窗口大小 = 捕获分辨率
    - 整数缩放：窗口宽高只能是捕获分辨率的整数倍/分
    - 自由宽高比：允许非等比缩放
    - 视频滤镜：用 CIFilter 处理帧（灰度、模糊、锐化等）
    - 启用裁剪：在窗口中只显示捕获画面的一部分（用户可拖拽裁剪框）
    - 翻转（水平/垂直）：CIFilter `CIAffineTransform`
    - 旋转（0°/90°/180°/270°）：CIFilter `CIAffineTransform`
    - 缩放滑块（0.1x~4.0x）
    - 欠扫描滑块（裁剪边缘百分比）
    - 透明度滑块（`window.alphaValue`）
    - "连接时恢复串流"：UserDefaults 持久化
  - 验证：各选项切换后串流画面实际变化

- [x] 实现画中画 (`FreeDisplay/Views/PiPWindow.swift`)
  - 实现提示：
    画中画 = 更小的浮动串流窗口 + 额外控制选项。
    基于 StreamWindow 扩展，增加：
    - 窗口层级：正常层级 / 置于其他窗口之上 / 置于菜单栏之上
      `window.level = .normal / .floating / .statusBar + 1`
    - 显示/隐藏标题栏：`window.styleMask.insert/remove(.titled)`
    - 不可移动：`window.isMovable = false`
    - 禁止调整大小：`window.styleMask.remove(.resizable)`
    - 吸附 25% 增量：拖拽结束后 snap 到最近的 25% 屏幕宽度位置
    - 鼠标点击穿透：`window.ignoresMouseEvents = true`
    - 窗口阴影：`window.hasShadow = true/false`
    - 排除画中画窗口（不被自身捕获）：ScreenCaptureKit 的 `excludingWindows` 参数
  - 验证：PiP 窗口浮动在其他窗口之上，各选项工作

- [x] 实现串流/PiP 的菜单 UI (`FreeDisplay/Views/StreamControlView.swift`, `PiPControlView.swift`)
  - 实现提示：
    两个可展开的 section："屏幕串流"和"画中画"，仿照 BetterDisplay 截图。
    串流区域：目标选择列表 + 停止按钮 + 所有选项开关/滑块
    画中画区域：开启/自启动 + 层级选择 + 所有选项开关/滑块 + 翻转旋转按钮组
    底部按钮："新增串流配置"/"新增画中画设定"（支持多个同时运行的串流/PiP）
  - 验证：UI 与 BetterDisplay 截图完全一致

## Phase 验收

- 屏幕串流实时显示目标显示器画面，帧率流畅
- 所有串流选项（鼠标、缩放、旋转、裁剪、滤镜、透明度）工作
- 画中画浮动窗口在最顶层，所有 PiP 选项工作
- 支持多个串流/PiP 同时运行
- UI 与 BetterDisplay 截图一致

**完成后**: 建议运行 project-optimize 反思
