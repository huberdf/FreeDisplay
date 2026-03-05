# Phase 0: 项目初始化 ⏳

> 由 project-planner 自动执行

## 任务列表

- [ ] 创建项目目录结构
  ```
  FreeDisplay/
  ├── project.yml                    # xcodegen 项目配置
  ├── FreeDisplay/
  │   ├── App/
  │   │   ├── FreeDisplayApp.swift   # @main 入口，MenuBarExtra
  │   │   └── AppDelegate.swift      # NSApplicationDelegate，权限请求
  │   ├── Views/                     # SwiftUI 视图层
  │   ├── ViewModels/                # ViewModel 层
  │   ├── Models/                    # 数据模型
  │   ├── Services/                  # 底层服务（DDC、显示管理等）
  │   ├── Utilities/                 # 工具函数
  │   ├── Resources/
  │   │   └── Assets.xcassets/       # 图标资源
  │   └── FreeDisplay.entitlements   # 权限声明
  └── docs/
      └── roadmap/                   # 本文件所在
  ```
  - 实现提示：`mkdir -p` 创建所有目录

- [ ] 创建 `project.yml`（xcodegen 配置）
  - 实现提示：配置 macOS app target，最低部署 macOS 14.0，关闭 App Sandbox，
    配置 Hardened Runtime，链接 IOKit.framework、CoreGraphics.framework、
    ScreenCaptureKit.framework、ColorSync.framework。
    entitlements 文件指向 FreeDisplay/FreeDisplay.entitlements
  - 验证：`xcodegen generate` 成功生成 FreeDisplay.xcodeproj

- [ ] 创建 `FreeDisplay/FreeDisplay.entitlements`
  - 实现提示：关闭 App Sandbox (`com.apple.security.app-sandbox` = false)，
    开启 Hardened Runtime 相关权限
  - 验证：文件存在且 XML 格式合法

- [ ] 创建 `FreeDisplay/App/FreeDisplayApp.swift`
  - 实现提示：使用 `@main` + SwiftUI `App` 协议，
    `MenuBarExtra("FreeDisplay", systemImage: "display")` 创建菜单栏图标，
    菜单内先放一个 "FreeDisplay v0.1" 文本 + "Quit" 按钮。
    设置 `.menuBarExtraStyle(.window)` 以支持自定义视图。
  - 验证：编译运行后菜单栏出现显示器图标，点击弹出面板

- [ ] 创建 `FreeDisplay/App/AppDelegate.swift`
  - 实现提示：`NSApplicationDelegate`，在 `applicationDidFinishLaunching` 中
    隐藏 Dock 图标 (`NSApp.setActivationPolicy(.accessory)`)
  - 验证：运行后 Dock 无图标，仅菜单栏可见

- [ ] 创建 `FreeDisplay/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
  - 实现提示：使用标准 macOS app icon set 的 Contents.json 模板，暂时不放实际图标文件
  - 验证：xcodegen 生成项目时无 asset catalog 警告

- [ ] 创建骨架文件（带 TODO 注释）
  - `FreeDisplay/Models/DisplayInfo.swift`：`class DisplayInfo: ObservableObject, Identifiable` 存储单个显示器信息
  - `FreeDisplay/Services/DisplayManager.swift`：`class DisplayManager: ObservableObject` 管理所有显示器
  - `FreeDisplay/Services/DDCService.swift`：`class DDCService` DDC/CI I2C 通信
  - `FreeDisplay/Views/MenuBarView.swift`：主菜单视图骨架
  - 每个文件包含 import、类声明、关键方法签名 + `// TODO: Phase N` 注释

- [ ] 用 xcodegen 生成 Xcode 项目并编译
  - 实现提示：`cd ~/Desktop/FreeDisplay && xcodegen generate && xcodebuild -scheme FreeDisplay -configuration Debug build`
  - 验证：`xcodebuild build` 成功，无编译错误

## Phase 验收

```bash
cd ~/Desktop/FreeDisplay
xcodegen generate   # 成功生成 .xcodeproj
xcodebuild -scheme FreeDisplay -configuration Debug build  # 编译成功
# 运行后：菜单栏出现显示器图标，点击弹出 "FreeDisplay v0.1" + Quit 按钮
```
