# Phase 21: 功能精简 — 删除无用功能

> 状态: 完成 | 预计: 中等复杂度

## 目标

删除不实用的功能（旋转、串流/PiP、色彩模式反色、镜像 UI），精简代码库，减少维护负担。

## 任务

### Task 1: 删除旋转功能
- [x] 删除 `Services/RotationService.swift`
- [x] 删除 `Views/RotationView.swift`
- [x] `DisplayDetailView.swift`：移除 `showRotation` 状态、旋转 DetailRow、RotationView embed、loadExpanded/saveExpanded("rotation")
- [x] `DisplayInfo.swift`：移除 `rotation: Double` 属性（grep 确认无其他引用）
- [x] `ConfigProtectionService.swift`：移除 `RotationService.shared.setRotation` 调用（约 2 处）、`ProtectedItems.rotation` 字段、`DisplayConfig.rotation` 字段
- [x] `ConfigProtectionView.swift`：移除旋转保护 toggle

**实现提示**: 先 grep `RotationService\|RotationView\|\.rotation` 找到所有引用，逐个清理。

### Task 2: 删除串流 + PiP + 视频滤镜
- [x] 删除 `Services/ScreenCaptureService.swift`
- [x] 删除 `ViewModels/StreamViewModel.swift`
- [x] 删除 `Views/StreamControlView.swift`
- [x] 删除 `Views/StreamWindow.swift`
- [x] 删除 `Views/PiPControlView.swift`
- [x] 删除 `Views/PiPWindow.swift`
- [x] 删除 `Views/VideoFilterWindow.swift`
- [x] `DisplayDetailView.swift`：移除 `showStream`、`showPiP` 状态 + 对应的 DetailRow + embed
- [x] `MenuBarView.swift`：移除 VideoFilterMenuEntry、SystemColorMenuEntry（如有）

**实现提示**: 这 7 个文件是孤岛，删除后 grep `ScreenCaptureService\|StreamViewModel\|StreamControlView\|PiPControlView\|PiPWindow\|VideoFilter` 确认无残留引用。

### Task 3: 删除色彩模式（反色/灰阶）和镜像 UI
- [x] 删除 `Views/ColorModeView.swift`
- [x] 删除 `Views/MirrorView.swift`（保留 `Services/MirrorService.swift`，HiDPI 依赖）
- [x] `DisplayDetailView.swift`：移除 `showColorMode`、`showMirror` 状态 + 对应 DetailRow + embed
- [x] `DisplayDetailView.swift`：清理 `colorModeDesc` 相关状态（`colorSpaceName` 保留，ColorProfile 需要）

**实现提示**: MirrorService.swift 不能删！VirtualDisplayService 的 HiDPI 功能依赖 MirrorService.enableMirror/disableMirror。

### Task 4: 编译验证 + 清理
- [x] `xcodegen generate && xcodebuild -scheme FreeDisplay -configuration Debug build`
- [x] 更新 `docs/CODEMAP.md`：移除已删除文件的记录
- [x] 更新 `README.md`：从功能列表中移除已删除功能
- [x] 更新 `CHANGELOG.md`：添加 v1.1.0 条目记录功能精简

## 验收标准

```bash
# 编译通过
xcodebuild -scheme FreeDisplay -configuration Debug build 2>&1 | tail -3

# 确认文件已删除
ls FreeDisplay/Services/RotationService.swift 2>&1  # should not exist
ls FreeDisplay/Views/RotationView.swift 2>&1         # should not exist
ls FreeDisplay/Views/StreamControlView.swift 2>&1    # should not exist

# 确认无残留引用
grep -r "RotationService\|RotationView\|StreamControlView\|PiPControlView\|ColorModeView\|MirrorView" FreeDisplay/ --include="*.swift" | grep -v "^Binary"
# should return nothing
```
