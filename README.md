# IdeaNotes

跨平台手写笔记应用

## 项目介绍

IdeaNotes 是一款跨平台的手写笔记应用，支持在移动设备上进行手写输入、笔记管理和 OCR 文字识别功能。

### 主要特性

- ✍️ **手写笔记** - 支持在画布上进行流畅的手写输入
- 📷 **OCR 识别** - 拍照识别手写文字，支持离线模型
- 📁 **笔记管理** - 分类、标签、搜索功能
- 🔄 **跨平台** - 支持 iOS、Android 等多平台
- 💾 **数据持久化** - 本地存储与云端同步

### 技术栈

- **Flutter** - 跨平台 UI 框架
- **Dart** - 编程语言
- **Google ML Kit** - OCR 文字识别
- **SQLite** - 本地数据存储

## 环境要求

- Flutter SDK >= 3.0.0
- Dart SDK >= 3.0.0
- Android SDK (API 21+)
- Xcode (iOS 开发，仅 macOS)

## 安装说明

### 1. 克隆项目

```bash
git clone <repository-url>
cd IdeaNotes
```

### 2. 安装依赖

```bash
flutter pub get
```

### 3. 运行应用

```bash
# 运行 debug 版本
flutter run

# 运行 release 版本
flutter build apk --release
```

### 4. 构建特定平台

#### Android

```bash
# Debug APK
flutter build apk --debug

# Release APK
flutter build apk --release
```

#### iOS (仅 macOS)

```bash
# Debug
flutter build ios --debug

# Release
flutter build ios --release
```

## 快速开始

### 基本使用

1. **创建笔记** - 点击主界面右下角的 "+" 按钮创建新笔记
2. **手写输入** - 在画布区域使用手指或触控笔进行书写
3. **保存笔记** - 点击保存按钮保存当前笔记
4. **OCR 识别** - 点击相机图标拍摄手写内容进行文字识别

### 权限说明

首次使用时，应用会请求以下权限：

- **相机权限** - 用于拍摄手写内容进行 OCR 识别
- **存储权限** - 用于保存和读取笔记数据
- **网络权限** - 用于下载 OCR 识别模型

## 项目结构

```
lib/
├── main.dart                 # 应用入口
├── models/                   # 数据模型
├── views/                    # 视图层
├── controllers/              # 控制器层
├── services/                 # 服务层
└── utils/                    # 工具类
```

## 贡献指南

欢迎提交 Pull Request 或创建 Issue！

## 许可证

MIT License
