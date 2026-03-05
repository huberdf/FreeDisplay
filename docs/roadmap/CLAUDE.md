# Roadmap — FreeDisplay

> 创建: 2026-03-02 | 目标: 完整替代 BetterDisplay 的免费 macOS 显示器管理菜单栏应用

## 背景与动机

BetterDisplay 是 macOS 上功能最全面的显示器管理工具，但价格昂贵。本项目旨在构建一个功能对等的免费开源替代品，涵盖 DDC 控制、HiDPI 管理、屏幕串流/画中画、虚拟显示器等全部核心功能。

## 需求摘要

### 功能域 1: 显示器基础管理
- 多显示器检测与列表展示（含内建 + 外接）
- 亮度滑块控制（DDC 协议控制外接，系统 API 控制内建）
- 分辨率切换（含 HiDPI 模式列表，原生 + 缩放模式）
- 设为主显示屏
- 屏幕旋转（90°/180°/270°）
- 排列显示器（可视化拖拽）

### 功能域 2: DDC/CI 完整控制
- 亮度、对比度、音量读取与设置
- 输入源切换
- 从设备读取并更新所有 VCP 参数

### 功能域 3: 色彩与图像
- 色彩模式切换（8-bit/10-bit、SDR/HDR、帧缓存类型）
- ICC 颜色描述文件切换
- 图像调整（对比度、伽马、增益、色温、RGB 通道独立调节）
- 反转色彩

### 功能域 4: 屏幕镜像与串流
- 屏幕镜像（选择源→目标）
- 屏幕串流（含翻转/旋转/缩放/欠扫描/透明度/裁剪/视频滤镜）
- 画中画（浮动窗口，含层级、锁定、点击穿透、阴影等选项）

### 功能域 5: 高级功能
- 虚拟显示器/Dummy Display 创建与管理
- 配置保护（防止系统重置分辨率/刷新率/色彩等设置）
- 自动亮度
- 显示刘海管理
- 连接时防止进入睡眠

## 技术方案概要

- **技术栈**: Swift 6.2 + SwiftUI (MenuBarExtra) + IOKit + CoreGraphics + ScreenCaptureKit + ColorSync
- **架构模式**: macOS 菜单栏应用（MenuBarExtra），MVVM 架构，xcodegen 管理项目
- **最低系统**: macOS 14.0（CGVirtualDisplay 需要 macOS 14+）
- **关键约束**: 需要辅助功能权限（DDC）、屏幕录制权限（串流）、App Sandbox 关闭

### 核心设计决策

| 决策 | 选择 | 原因 |
|------|------|------|
| UI 框架 | SwiftUI MenuBarExtra | macOS 13+ 原生支持，轻量不占 Dock |
| 项目管理 | xcodegen + project.yml | CLI 友好，避免手动管理 .xcodeproj |
| DDC 通信 | IOKit I2C 直接通信 | 不依赖第三方库，参考 MonitorControl 开源实现 |
| 屏幕捕获 | ScreenCaptureKit | Apple 官方 API，macOS 12.3+，替代弃用的 CGDisplayStream |
| 虚拟显示 | CGVirtualDisplay | macOS 14+ 官方 API，比旧的 IOKit 方式更稳定 |
| 色彩管理 | ColorSync + CoreGraphics | 系统原生 ICC 管理 |
| 架构模式 | MVVM | SwiftUI 最佳实践，View-ViewModel-Service 分层 |

## 阶段概览

| Phase | 名称 | 状态 | 详情 |
|-------|------|------|------|
| 0-17 | 已归档 | ✅ | [archive/](archive/) |
| 18 | 稳定性加固 | ✅ | [phase-18.md](phase-18.md) |
| 19 | 显示器预设系统 | ✅ | [phase-19.md](phase-19.md) |
| 20 | 发布准备 | ✅ | [phase-20.md](phase-20.md) |
| 21 | 功能精简 | ✅ | [phase-21.md](phase-21.md) |
| 22 | 自动亮度重写 | ✅ | [phase-22.md](phase-22.md) |

## 决策记录

| 日期 | 决策 | 备选方案 | 理由 |
|------|------|---------|------|
| 2026-03-02 | 使用 xcodegen 而非手动 Xcode 项目 | SPM executable, 手动 xcodeproj | CLI 友好，可 git 管理，自动生成 xcodeproj |
| 2026-03-02 | MenuBarExtra 而非 NSStatusItem | NSStatusItem + NSPopover | SwiftUI 原生，代码更简洁，macOS 13+ 支持 |
| 2026-03-02 | 最低 macOS 14 | macOS 12/13 | CGVirtualDisplay 需要 14+，用户当前 macOS 15 |
| 2026-03-02 | 无第三方依赖 | MonitorControl/Lunar 库 | 完全自主可控，学习底层 API |
| 2026-03-04 | Phase 18-20 规划 | 继续 bug 修复 | 功能已完整，聚焦稳定性→预设系统→发布分发 |

## 需求对接记录

| 日期 | 确认项 | 内容 |
|------|--------|------|
| 2026-03-02 | 功能范围 | 用户确认：全部功能都要，包括串流/PiP/虚拟显示器 |
| 2026-03-02 | 项目位置 | ~/Desktop/FreeDisplay |
| 2026-03-02 | 开发环境 | Xcode 已安装，xcodegen 2.44.1 已安装 |
| 2026-03-02 | 用户硬件 | MacBook 内建显示屏 + HKC H2435Q 2K 外接显示器 |
| 2026-03-04 | HiDPI 调试经验 | CGVirtualDisplay vendorID 非零、主线程创建、HiDPI 配置纯运行时等约束已记入 lessons |
