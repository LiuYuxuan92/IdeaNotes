# 技术栈

**分析日期：** 2026-04-16

## 语言

**主要语言：**
- Dart `>=3.0.0 <4.0.0`：应用主代码位于 `lib/main.dart`、`lib/app/app.dart`、`lib/core/`、`lib/features/`，版本约束定义在 `pubspec.yaml`。

**次要语言：**
- Kotlin：Android 启动层和原生宿主位于 `android/app/src/main/kotlin/com/ideanotes/ideanotes/MainActivity.kt`。
- Groovy Gradle DSL：Android 构建脚本位于 `android/app/build.gradle`、`android/build.gradle`、`android/settings.gradle`。
- Objective-C：iOS Flutter 插件注册位于 `ios/Runner/GeneratedPluginRegistrant.m`。
- C++ / CMake：Linux 桌面壳层位于 `linux/runner/main.cc`、`linux/CMakeLists.txt`。

## 运行时

**环境：**
- Flutter 应用运行时：项目类型为 app，记录在 `.metadata`。
- Flutter 渠道：`stable`，记录在 `.metadata`。
- Dart SDK：`>=3.0.0 <4.0.0`，配置在 `pubspec.yaml`。
- Android 构建 JVM：Java 17 / Kotlin JVM 17，配置在 `android/app/build.gradle`。

**包管理器：**
- Flutter Pub：依赖入口为 `pubspec.yaml`。
- 锁文件：已存在 `pubspec.lock`。

## 框架

**核心：**
- Flutter：跨平台 UI 应用框架，入口在 `lib/main.dart`，应用根组件在 `lib/app/app.dart`。
- `flutter_bloc` `^8.1.3`：状态管理，实际用于 `lib/app/app.dart`、`lib/features/notelist/bloc/note_list_bloc.dart`、`lib/features/canvas/bloc/canvas_bloc.dart`。
- `equatable` `^2.0.5`：值对象/状态比较，配合 bloc 与模型层使用，见 `pubspec.yaml`。

**数据与本地存储：**
- `sqflite` `^2.3.0`：本地 SQLite 存储，核心入口在 `lib/core/storage/database_helper.dart`，迁移在 `lib/core/storage/database_migrations.dart`。
- `path` `^1.8.3`：数据库路径拼接，见 `lib/core/storage/database_helper.dart`。
- `path_provider` `^2.1.1`：应用文档目录与图片目录管理，见 `lib/core/storage/image_storage.dart`。

**OCR / 手写 / 语音 / AI：**
- `google_mlkit_text_recognition` `^0.15.0`：图片 OCR，封装在 `lib/core/ocr/mlkit_ocr.dart`。
- `google_mlkit_digital_ink_recognition` `^0.14.2`：手写轨迹识别，封装在 `lib/features/canvas/services/handwriting_recognition_service.dart`。
- `speech_to_text` `^7.3.0`：语音转文字，封装在 `lib/features/canvas/services/voice_recognition_service.dart`。
- 自定义 DeepSeek 接入：通过 `dart:io` `HttpClient` 直接访问 `https://api.deepseek.com/chat/completions`，实现位于 `lib/core/extraction/deepseek_text_understanding_engine.dart` 与 `lib/core/extraction/deepseek_ocr_text_correction_engine.dart`。

**分享与导出：**
- `share_plus` `^7.2.1`：文本分享，实际调用位于 `lib/features/notedetail/note_detail_screen.dart`。
- `pdf` `^3.10.4`、`printing` `^5.11.1`、`screenshot` `^2.1.0`：依赖已在 `pubspec.yaml` 声明，插件也出现在 `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java` 与 `ios/Runner/GeneratedPluginRegistrant.m`，但当前仓库内未发现业务层直接调用。

**UI 与辅助：**
- `flutter_slidable` `^3.0.1`：列表交互增强，声明于 `pubspec.yaml`。
- `flutter_colorpicker` `^1.0.3`：颜色选择器，声明于 `pubspec.yaml`。
- `intl` `^0.18.1`：日期/本地化格式处理，声明于 `pubspec.yaml`。
- `uuid` `^4.2.1`：ID 生成，见 `lib/core/storage/image_storage.dart`、`lib/features/canvas/services/canvas_save_service.dart`、`lib/core/storage/entry_repository.dart`。
- `image` `^4.1.3`：缩略图生成，见 `lib/core/storage/image_storage.dart`。
- `decimal` `^2.3.3`：金额精度处理，模型与解析链路依赖它，见 `pubspec.yaml` 与 `lib/core/models/`。
- `path_drawing` `^1.0.1`：手写路径绘制辅助，声明于 `pubspec.yaml`。

**测试：**
- `flutter_test`：单元测试 / Widget 测试，测试目录为 `test/`。
- `sqlite3` `^2.9.4`、`sqflite_common_ffi` `^2.3.0`：测试中的 SQLite/Ffi 支撑，声明在 `pubspec.yaml`。

**构建与开发：**
- `flutter_lints` `^3.0.1`：静态检查规则，入口在 `analysis_options.yaml`。
- Android Gradle Plugin `8.11.1`：配置在 `android/settings.gradle`。
- Kotlin Android Plugin `2.2.20`：配置在 `android/settings.gradle`。
- Gradle Wrapper `8.14.0`：配置在 `android/gradle/wrapper/gradle-wrapper.properties`。

## 关键依赖

**关键：**
- `sqflite` `^2.3.0`：承载 `notebooks`、`notes`、`note_entries`、`entries`、`ai_extractions`、`saved_filters` 等核心表，定义见 `lib/core/storage/database_migrations.dart`。
- `google_mlkit_text_recognition` `^0.15.0`：提供图片 OCR 兜底识别，接入点在 `lib/core/ocr/mlkit_ocr.dart`。
- `google_mlkit_digital_ink_recognition` `^0.14.2`：提供手写轨迹识别主链路，接入点在 `lib/features/canvas/services/handwriting_recognition_service.dart`。
- `speech_to_text` `^7.3.0`：提供语音输入，调用链路从 `lib/features/canvas/canvas_screen.dart` 到 `lib/features/canvas/services/voice_recognition_service.dart`。
- `flutter_bloc` `^8.1.3`：支撑页面状态和列表刷新，见 `lib/app/app.dart` 与 `lib/features/notelist/bloc/note_list_bloc.dart`。

**基础设施：**
- `permission_handler` `^11.1.0`：统一权限申请，实际在 `lib/features/canvas/canvas_screen.dart` 使用，平台声明位于 `android/app/src/main/AndroidManifest.xml` 与 `ios/Runner/Info.plist`。
- `share_plus` `^7.2.1`：将识别文本分享给系统外部应用，见 `lib/features/notedetail/note_detail_screen.dart`。
- `path_provider` `^2.1.1` + `image` `^4.1.3`：负责快照与缩略图持久化，见 `lib/core/storage/image_storage.dart`。
- `uuid` `^4.2.1`：为笔记图片、结构化条目、AI 审计记录生成主键，见 `lib/core/storage/image_storage.dart`、`lib/core/storage/entry_repository.dart`。
- `http`：未在 `pubspec.yaml` 直接声明为顶层依赖，但已出现在 `pubspec.lock`；当前业务代码的 DeepSeek 调用实际使用 `dart:io` `HttpClient`，见 `lib/core/extraction/deepseek_text_understanding_engine.dart`。

## 配置

**环境配置：**
- Flutter/Dart 依赖入口：`pubspec.yaml`。
- Dart 分析配置：`analysis_options.yaml`。
- DeepSeek 密钥入口：`lib/core/config/app_secrets.dart` 通过 `String.fromEnvironment('DEEPSEEK_API_KEY')` 读取。
- Flutter 入口：`lib/main.dart`。
- 应用根组件：`lib/app/app.dart`。
- Android 权限与联网声明：`android/app/src/main/AndroidManifest.xml`。
- iOS 权限与 ATS 配置：`ios/Runner/Info.plist`。

**构建配置：**
- Android 应用构建：`android/app/build.gradle`。
- Android 仓库与全局构建：`android/build.gradle`。
- Android 插件版本与 Flutter Gradle loader：`android/settings.gradle`。
- Gradle 版本：`android/gradle/wrapper/gradle-wrapper.properties`。
- Flutter 项目元数据：`.metadata`。

## 平台要求

**开发环境：**
- 需要 Flutter stable 工具链，约束由 `.metadata` 与 `pubspec.yaml` 共同体现。
- Android 侧需要 Java 17 与 Kotlin/AGP 对应环境，见 `android/app/build.gradle` 与 `android/settings.gradle`。
- 本地开发默认依赖 Flutter Pub 解析依赖，锁文件为 `pubspec.lock`。

**运行与发布目标：**
- 主要目标平台是 Android 与 iOS，证据包括移动端权限声明 `android/app/src/main/AndroidManifest.xml`、`ios/Runner/Info.plist`，以及 OCR 可用性判断 `lib/core/ocr/mlkit_ocr.dart`。
- Linux 桌面壳工程已存在于 `linux/`，但 OCR 主实现 `lib/core/ocr/mlkit_ocr.dart` 仅对 Android/iOS 返回可用，说明当前能力重心是移动端。
- Android 发布构建开启 `minifyEnabled true` 与 `shrinkResources true`，见 `android/app/build.gradle`。

---

*技术栈分析：2026-04-16*
