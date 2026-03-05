# Roadmap — FreeDisplay

> 创建: 2026-03-02 | 目标: 完整替代 BetterDisplay 的免费 macOS 显示器管理菜单栏应用
> **详细实现提示见**: `docs/roadmap/phase-N.md`

## 已归档 Phase (0-17)

> 详情见: `docs/roadmap/archive/`

- Phase 0: 项目初始化 ✅
- Phase 1: 显示器检测与菜单 UI ✅
- Phase 2: 亮度控制（DDC + 内建） ✅
- Phase 3: 分辨率管理与 HiDPI ✅
- Phase 4: 屏幕旋转与显示器排列 ✅
- Phase 5: 色彩管理 ✅
- Phase 6: 图像调整 ✅
- Phase 7: 显示器高级管理 ✅
- Phase 8: 屏幕镜像 ✅
- Phase 9: 屏幕串流与画中画 ✅
- Phase 10: 虚拟显示器 ✅
- Phase 11: 配置保护与自动亮度 ✅
- Phase 12: 收尾与发布 ✅
- Phase 13: 关键 Bug 修复 ✅
- Phase 14: 性能优化（消除卡顿） ✅
- Phase 15: 交互体验打磨 ✅
- Phase 16: 全面 Bug 修复 ✅
- Phase 17: 核心功能专项修复 — DDC/HiDPI/刘海 ✅

## Phase 18: 稳定性加固 ✅
> 详情: `docs/roadmap/phase-18.md`

### Task 1: 统一 CG 阻塞调用超时保护
- [x] 将 VirtualDisplayService 的 `runWithTimeout` 提取为公共工具函数
- [x] MirrorService: `enableMirror`/`disableMirror` 加超时保护
- [x] ArrangementService: `setPosition` 加超时保护
- [x] ResolutionService: `applyModeSync` 加 10 秒超时保护

### Task 2: 显示器配置变更自动重排列
- [x] 注册 `CGDisplayRegisterReconfigurationCallback`
- [x] 配置变更完成后延迟 500ms 调用 `arrangeExternalAboveBuiltin()`
- [x] 防抖机制（500ms 内多次回调只执行最后一次）

### Task 3: 睡眠/唤醒后自动恢复 HiDPI
- [x] 唤醒时检查 HiDPI 活跃会话，丢失则重新创建
- [x] 恢复序列：create → apply settings → sleep 500ms → mirror → setDisplayMode → arrange
- [x] 持久化 HiDPI 状态到 UserDefaults（`fd.hiDPI.activePhysicalIDs`）

### Task 4: 错误恢复与用户反馈
- [x] CG 调用超时时显示菜单栏状态提示
- [x] HiDPI 恢复失败时提示用户手动重新开启
- [x] 连续失败 3 次后自动禁用 HiDPI 并提示

## Phase 19: 显示器预设系统 ✅
> 详情: `docs/roadmap/phase-19.md`

### Task 1: 预设数据模型
- [x] 创建 `Models/DisplayPreset.swift`
- [x] 创建 `Services/PresetService.swift`：加载/保存/应用预设
- [x] 预设存储在 `~/Library/Application Support/FreeDisplay/presets.json`

### Task 2: 内置默认预设
- [x] "HiDPI 模式"：enableHiDPIVirtual + 1920×1080 + 排列
- [x] "原生模式"：禁用 HiDPI 虚拟 + 恢复原生分辨率 + 排列
- [x] 内置预设不可删除（`isBuiltin: true`）

### Task 3: 保存当前状态为预设
- [x] 菜单栏添加"保存为预设"按钮
- [x] 内联表单：输入名称、选择图标
- [x] 自动捕获当前所有显示器状态并保存

### Task 4: 预设列表与一键切换
- [x] 在 MenuBarView 中显示预设列表（替换 HiDPIPresetRow 位置）
- [x] 每个预设显示图标 + 名称 + 当前匹配徽章
- [x] 点击预设 → 应用（loading spinner）
- [x] 长按/右键 → 删除（非内置预设）

## Phase 20: 发布准备 ✅
> 详情: `docs/roadmap/phase-20.md`

### Task 1: App 图标
- [x] 设计显示器图标，生成 AppIcon.appiconset 所有尺寸
- [x] 更新 project.yml 引用 AppIcon

### Task 2: Launch at Login 优化
- [x] 确认使用 `SMAppService.mainApp`（macOS 13+）
- [x] 首次启动时提示用户是否开机自启

### Task 3: DMG 打包
- [x] 创建 `scripts/build-dmg.sh` 脚本
- [x] Release 构建 + DMG 打包（FreeDisplay.app + Applications 快捷方式）

### Task 4: GitHub Release
- [x] README.md 添加功能截图
- [x] 添加 CHANGELOG.md
- [x] `scripts/release.sh`：构建 → 打包 DMG → gh release create

### Task 5: UpdateService 完善
- [x] 确认检查更新逻辑指向 GitHub Releases API
- [x] 检测到新版本时显示下载链接
- [x] "启动时检查更新"toggle 确认可用
