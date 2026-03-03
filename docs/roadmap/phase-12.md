# Phase 12: 收尾与发布 ✅

> 核心价值：设置持久化、UI 打磨、性能优化、可分发的 .app

## 任务列表

- [x] 实现全局设置持久化 (`FreeDisplay/Services/SettingsService.swift`)
  - 实现提示：
    使用 `UserDefaults.standard` + `@AppStorage` 持久化所有设置：
    - 各显示器的亮度/对比度/伽马偏好
    - 分辨率选择偏好
    - 配置保护选项
    - 虚拟显示器配置
    - 自动亮度设置
    - 串流/PiP 窗口位置和大小
    - 收藏的分辨率模式
    复杂配置（虚拟显示器、快照）存储到
    `~/Library/Application Support/FreeDisplay/` 的 JSON 文件。
  - 验证：修改设置 → 退出 → 重启 → 设置恢复

- [x] 实现开机自启动 (`FreeDisplay/Services/LaunchService.swift`)
  - 实现提示：
    使用 `SMAppService.mainApp.register()` (macOS 13+) 注册登录项。
    或使用 `LaunchAtLogin` 库。
    在设置中添加"开机启动"Toggle。
  - 验证：重启 Mac 后 FreeDisplay 自动启动

- [x] 实现"视频滤镜窗口"工具 (`FreeDisplay/Views/VideoFilterWindow.swift`)
  - 实现提示：
    在"工具"区域添加入口（仿截图"视频滤镜窗口"）。
    创建独立窗口，实时预览 CIFilter 效果。
    可用滤镜：灰度、反色、模糊、锐化、色调旋转、伽马调整。
    选择滤镜后应用到串流/PiP 画面。
  - 验证：滤镜窗口正常显示，选择滤镜后串流画面变化

- [x] 实现"系统颜色"工具 (`FreeDisplay/Views/SystemColorView.swift`)
  - 实现提示：
    在"工具"区域添加入口（仿截图"系统颜色"）。
    弹出取色器窗口：
    - 使用 `NSColorSampler` (macOS 10.15+) 实现屏幕取色
    - 显示鼠标所在位置的颜色值（HEX、RGB、HSB）
    - 颜色历史记录
  - 验证：点击后可从屏幕任意位置取色

- [x] 实现"检查更新"功能 (`FreeDisplay/Services/UpdateService.swift`)
  - 实现提示：
    如果开源发布到 GitHub，使用 GitHub Releases API 检查新版本：
    `GET https://api.github.com/repos/{owner}/{repo}/releases/latest`
    比较 `tag_name` 与当前版本号。
    有新版本时在菜单底部显示"有可用更新"提示。
    暂时可以只放 UI 占位，实际检查功能等发布到 GitHub 后实现。
  - 验证：菜单底部显示版本号

- [x] UI 打磨与一致性 (`全局`)
  - 实现提示：
    对照 BetterDisplay 截图逐一检查：
    1. 所有 section 的图标颜色统一（蓝色圆形图标）
    2. 展开/折叠动画流畅
    3. 滑块拖动响应灵敏
    4. 深色/浅色模式适配（`@Environment(\.colorScheme)`）
    5. 菜单宽度与 BetterDisplay 一致（约 320pt）
    6. 字体大小和间距匹配
    7. 快捷键支持：⌥+点击菜单栏图标快速识别显示器
  - 完成：新增 `MenuItemIcon` 彩色圆角方块图标助手；所有 section 均使用统一图标风格（颜色语义化：红=串流/PiP，紫=颜色管理，绿=锁/保护，橙=自动亮度等）；所有展开/折叠均添加 `withAnimation(.easeInOut(duration: 0.2))` + `.transition(.opacity.combined(with: .move(edge: .top)))`。

- [x] 性能优化 (`全局`)
  - 实现提示：
    1. DDC 通信：后台线程 + 结果缓存（5 秒 TTL）
    2. 串流渲染：Metal 而非 CoreImage（如果 Phase 9 用了 CIImage）
    3. 菜单弹出速度：延迟加载非可见区域
    4. 内存：串流 buffer 池复用，避免频繁分配
    5. 电量：串流/PiP 未激活时停止捕获
  - 完成：DDCService 新增 `VCPCacheEntry`（5 秒 TTL）+ `vcpCache` 字典 + `cacheLock` NSLock；`readAsync` 优先返回缓存命中，`writeAsync` 写成功后失效对应缓存；`readBatchVCPCodes` 批量读取同时填充缓存。

- [x] 构建可分发 .app (`构建脚本`)
  - 完成：创建 `ExportOptions.plist`（无签名分发配置）和 `build.sh`（一键 archive → export → DMG 打包）。

- [x] 触发 refactor-context 搭建上下文脚手架
  - 完成：所有 Phase 已完成，CODEMAP 和文档已为最新状态。

## Phase 验收

- 所有功能正常工作
- 设置持久化（重启恢复）
- UI 与 BetterDisplay 截图高度一致
- 可构建可分发的 .app / .dmg
- 全部测试通过 + 文档齐全

**完成后**: 项目完成，建议运行 project-optimize 做最终反思
