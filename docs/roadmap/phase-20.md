# Phase 20: 发布准备

> 状态: 已完成 | 预计: 中等复杂度

## 目标

将 FreeDisplay 从开发状态打包成可分发的正式 macOS 应用，含图标、代码清理、DMG 安装包、GitHub Release。

## 任务

### Task 1: 代码清理 + App 图标
- [x] 删除 MenuBarView 中已废弃的 `HiDPIPresetRow`（已被 PresetListView 替代）
- [x] 搜索并清理其他未使用代码/dead code
- [x] 用 Python PIL/Pillow 脚本生成 App 图标：圆角矩形显示器 + "F" 字母 + 渐变蓝紫色
- [x] 生成 AppIcon.appiconset 所有尺寸（16/32/64/128/256/512/1024）
- [x] 创建 `FreeDisplay/Assets.xcassets/AppIcon.appiconset/Contents.json` + PNG 文件
- [x] 更新 project.yml 引用 AppIcon asset catalog

**实现提示**: 用 Python 脚本生成 1024×1024 PNG，`sips -z H W` 缩放各尺寸。project.yml 需添加 `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`。

### Task 2: Launch at Login（SMAppService）
- [x] 在 `LaunchService.swift` 中将现有实现迁移到 `SMAppService.mainApp`（macOS 13+）
- [x] `register()` / `unregister()` 替换旧 API，需要 `import ServiceManagement`
- [x] 确认 SettingsService 已有的 `fd.launchAtLogin` toggle 正常联动
- [x] 首次启动提示：如果 `fd.launchAtLogin` 从未设置过，弹出一次性提示

**实现提示**: `SMAppService.mainApp.register()` 一行代码。状态检查用 `.status == .enabled`。

### Task 3: Release 构建 + Ad-hoc 签名 + DMG 打包
- [x] 创建 `scripts/build-dmg.sh` 一键脚本
- [x] Release 构建：`xcodebuild -scheme FreeDisplay -configuration Release build`
- [x] Ad-hoc 签名：`codesign --force --deep --sign - FreeDisplay.app`（无 Developer ID 时的最低要求）
- [x] 使用 `hdiutil` 打包 DMG：FreeDisplay.app + Applications 快捷方式
- [x] 在 README 中说明首次打开需要右键→打开（绕过 Gatekeeper）

**实现提示**: `hdiutil create -volname "FreeDisplay" -srcfolder build/ -ov -format UDZO FreeDisplay.dmg`。无 Developer ID 签名的 app 需要用户手动信任。

### Task 4: README + CHANGELOG + GitHub Release 脚本
- [x] 编写 README.md：项目简介、功能列表、安装说明、截图占位符、Gatekeeper 绕过说明
- [x] 编写 CHANGELOG.md：从 Phase 0-20 整理主要变更
- [x] 创建 `scripts/release.sh`：构建 → 签名 → 打包 DMG → `gh release create`
- [x] README 添加下载徽章

**实现提示**: 截图需要人工运行 app 后用 `screencapture` 截取，先用占位符。`gh release create v1.0.0 --title "FreeDisplay v1.0.0" --notes-file CHANGELOG.md *.dmg`。

### Task 5: UpdateService 完善
- [x] 确认 UpdateService 检查更新逻辑指向 GitHub Releases API
- [x] URL 用占位符 `https://api.github.com/repos/OWNER/FreeDisplay/releases/latest`（用户发布时替换）
- [x] 检测到新版本时在菜单栏显示下载链接
- [x] 设置界面的"启动时检查更新"toggle 确认正常

**实现提示**: GitHub Releases API 返回 JSON，解析 `tag_name` 与当前 `CFBundleShortVersionString` 对比。

## 验收标准

```bash
# Release 构建
xcodebuild -scheme FreeDisplay -configuration Release build 2>&1 | tail -3

# DMG 打包
./scripts/build-dmg.sh

# 验证
# 1. DMG 双击安装 → 拖拽到 Applications → 启动正常
# 2. App 图标在 Dock/Finder 中正确显示
# 3. Launch at Login toggle 功能正常
# 4. README/CHANGELOG 内容完整
```
