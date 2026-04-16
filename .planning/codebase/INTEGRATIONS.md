# 外部集成

**分析日期：** 2026-04-16

## API 与外部服务

**AI / 文本理解：**
- DeepSeek Chat Completions API：用于 OCR 文本校对与结构化抽取。
  - 接入实现：`lib/core/extraction/deepseek_text_understanding_engine.dart`、`lib/core/extraction/deepseek_ocr_text_correction_engine.dart`
  - 默认端点：`lib/core/extraction/deepseek_api_defaults.dart`
  - 触发入口：`lib/features/canvas/services/canvas_ai_preview_service.dart`、`lib/features/canvas/canvas_screen.dart`
  - 网络客户端：`dart:io` `HttpClient`，未发现 `dio` 或仓库自建 HTTP 层
  - 鉴权：`DEEPSEEK_API_KEY`，读取逻辑位于 `lib/core/config/app_secrets.dart`

**本地 OCR / 手写识别 SDK：**
- Google ML Kit Text Recognition：用于图片 OCR，封装在 `lib/core/ocr/mlkit_ocr.dart`，由 `lib/core/ocr/vision_ocr.dart` 统一工厂选择。
  - SDK 包：`google_mlkit_text_recognition`
  - 平台插件注册：`android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java`、`ios/Runner/GeneratedPluginRegistrant.m`
  - 运行时可用平台：`lib/core/ocr/mlkit_ocr.dart` 中仅 Android / iOS 返回可用
- Google ML Kit Digital Ink Recognition：用于手写轨迹识别，封装在 `lib/features/canvas/services/handwriting_recognition_service.dart`
  - SDK 包：`google_mlkit_digital_ink_recognition`
  - 模型下载：由 `DigitalInkRecognizerModelManager.downloadModel(...)` 触发，代码位于 `lib/features/canvas/services/handwriting_recognition_service.dart`
  - 网络依赖：依赖设备联网下载模型，因此 Android 显式声明了 `android.permission.INTERNET` 与 `android.permission.ACCESS_NETWORK_STATE`，见 `android/app/src/main/AndroidManifest.xml`

**语音识别：**
- 系统语音转写：通过 `speech_to_text` 调用系统能力，封装在 `lib/features/canvas/services/voice_recognition_service.dart`
  - UI 入口：`lib/features/canvas/canvas_screen.dart`、`lib/features/canvas/widgets/voice_capture_sheet.dart`
  - 鉴权方式：系统权限而非应用级 token

## 数据存储

**数据库：**
- SQLite 本地数据库：
  - 连接入口：`lib/core/storage/database_helper.dart`
  - Schema 与迁移：`lib/core/storage/database_migrations.dart`
  - Repository：`lib/core/storage/entry_repository.dart`
  - 数据文件：通过 `getDatabasesPath()` 创建 `idea_notes.db`，见 `lib/core/storage/database_helper.dart`
- 核心表：
  - `notebooks`、`notes`、`note_entries`：基础笔记与旧版条目结构，定义于 `lib/core/storage/database_migrations.dart`
  - `entries`、`entry_subjects`、`entry_tags`、`entry_links`：结构化检索模型，定义于 `lib/core/storage/database_migrations.dart`
  - `ai_extractions`：保存 AI 抽取审计快照，写入逻辑在 `lib/core/storage/entry_repository.dart`
  - `saved_filters`：保存筛选器配置，定义于 `lib/core/storage/database_migrations.dart`

**文件存储：**
- 本地文件系统：
  - 图片根目录：应用文档目录下的 `images/`，由 `lib/core/storage/image_storage.dart` 创建
  - 快照目录：`images/snapshots/`，见 `lib/core/storage/image_storage.dart`
  - 缩略图目录：`images/thumbnails/`，见 `lib/core/storage/image_storage.dart`
  - 缩略图生成：`image` 包，见 `lib/core/storage/image_storage.dart`

**缓存：**
- 未检测到 Redis、Hive、SharedPreferences 或远程缓存服务。
- 当前缓存/中间态主要依赖内存状态与 SQLite，本地状态管理代码在 `lib/features/canvas/bloc/canvas_bloc.dart` 与 `lib/features/notelist/bloc/note_list_bloc.dart`。

## 权限与身份

**认证提供方：**
- 未检测到用户账户体系、OAuth、Firebase Auth、Supabase Auth 或自定义登录接口。
- 当前“身份/权限”语义主要是设备级系统权限，不是业务用户鉴权。

**权限实现：**
- 统一权限库：`permission_handler`
  - 业务调用：`lib/features/canvas/canvas_screen.dart`
  - Android 清单：`android/app/src/main/AndroidManifest.xml`
  - iOS 清单：`ios/Runner/Info.plist`
- 已声明权限：
  - 网络：`INTERNET`、`ACCESS_NETWORK_STATE`，见 `android/app/src/main/AndroidManifest.xml`
  - 相机：`CAMERA`，见 `android/app/src/main/AndroidManifest.xml` 与 `ios/Runner/Info.plist`
  - 麦克风：`RECORD_AUDIO` 与 `NSMicrophoneUsageDescription`，见 `android/app/src/main/AndroidManifest.xml`、`ios/Runner/Info.plist`
  - 语音识别：iOS `NSSpeechRecognitionUsageDescription`，业务申请见 `lib/features/canvas/canvas_screen.dart`
  - 相册/图片读取：`READ_MEDIA_IMAGES`、`READ_EXTERNAL_STORAGE`、`WRITE_EXTERNAL_STORAGE` 与 iOS Photo Library 描述，见 `android/app/src/main/AndroidManifest.xml`、`ios/Runner/Info.plist`
- 权限申请逻辑：
  - 语音转写前会动态请求 `Permission.microphone`，iOS 额外请求 `Permission.speech`，实现位于 `lib/features/canvas/canvas_screen.dart`

## 导出 / 分享

**已接线能力：**
- 系统文本分享：
  - 实现：`lib/features/notedetail/note_detail_screen.dart`
  - SDK：`share_plus`
  - 共享内容：当前为 `_recognizedText` 文本，不是图片或 PDF

**已声明但未发现业务调用：**
- `pdf`：在 `pubspec.yaml` 中声明，并注册到 `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java` 与 `ios/Runner/GeneratedPluginRegistrant.m`，但当前仓库未发现 `Pdf` 生成逻辑。
- `printing`：在 `pubspec.yaml` 中声明，并注册到平台插件清单，但未发现业务层调用。
- `screenshot`：在 `pubspec.yaml` 中声明，但当前画布截图实际通过 `RenderRepaintBoundary` 自行捕获，代码位于 `lib/features/canvas/canvas_screen.dart`；未发现 `ScreenshotController` 调用。

## 语音 / OCR / AI 集成

**OCR：**
- 主链路：手写轨迹识别
  - 服务：`lib/features/canvas/services/handwriting_recognition_service.dart`
  - 输入：`lib/features/canvas/bloc/canvas_bloc.dart` 中维护的 `DrawingStroke`
  - 输出：识别文本回写到 `lib/features/canvas/canvas_screen.dart`
- 兜底链路：图片 OCR
  - 工厂：`lib/core/ocr/vision_ocr.dart`
  - Android：`MlKitOcr`
  - iOS：`VisionOcr` 目前内部仍复用 `MlKitOcr`
  - 页面调用：`lib/features/canvas/canvas_screen.dart` 的 `_runImageOcrFallback()`

**语音：**
- 服务抽象：`VoiceRecognitionService`，位于 `lib/features/canvas/services/voice_recognition_service.dart`
- 默认实现：`SpeechToTextVoiceRecognitionService`
- 页面入口：`lib/features/canvas/canvas_screen.dart`
- 交互 UI：`lib/features/canvas/widgets/voice_capture_sheet.dart`

**AI：**
- 文本校对：
  - 接口：`OcrTextCorrectionEngine`
  - DeepSeek 实现：`lib/core/extraction/deepseek_ocr_text_correction_engine.dart`
  - 预览流程接线：`lib/features/canvas/services/canvas_ai_preview_service.dart`
- 结构化理解：
  - 接口：`TextUnderstandingEngine`
  - DeepSeek 实现：`lib/core/extraction/deepseek_text_understanding_engine.dart`
  - 应用层封装：`lib/core/extraction/ai_extraction_service.dart`
  - 编排与规则融合：`lib/core/extraction/extraction_orchestrator.dart`
  - 保存审计记录：`lib/core/storage/entry_repository.dart`
- 保存流程中的 AI 集成：
  - 入口服务：`lib/features/canvas/services/canvas_save_service.dart`
  - 行为：规则解析结果与 AI 抽取结果合并后写入 `entries`，同时将 AI 响应写入 `ai_extractions`

## 监控与可观测性

**错误追踪：**
- 未检测到 Sentry、Crashlytics、Bugsnag 或其他第三方错误追踪。

**日志：**
- 以本地调试输出为主，典型位置见 `lib/core/ocr/mlkit_ocr.dart` 与 `lib/core/storage/image_storage.dart` 中的 `debugPrint(...)`。
- AI 抽取保留结构化审计快照到 SQLite `ai_extractions`，属于业务审计，不是统一日志平台，写入逻辑在 `lib/core/storage/entry_repository.dart`。

## CI / CD 与部署

**托管与发布：**
- 未检测到云托管平台配置、Fastlane、Codemagic、GitHub Actions workflow 或应用商店发布脚本。
- 当前可确认的是本地 Flutter 移动端工程结构：Android 位于 `android/`，iOS 位于 `ios/`，Linux 桌面壳位于 `linux/`。

**CI 流水线：**
- 未检测到 `.github/workflows/`。
- `.github/pull_request_template.md` 存在，但这不是构建流水线。

## 环境配置

**必需环境变量：**
- `DEEPSEEK_API_KEY`
  - 读取位置：`lib/core/config/app_secrets.dart`
  - 使用位置：`lib/core/extraction/deepseek_text_understanding_engine.dart`

**密钥位置：**
- 仓库内未检测到 `.env` 文件。
- 当前代码显式采用 Dart 编译期环境变量 `String.fromEnvironment(...)` 读取，说明应通过 Flutter 构建参数注入，而不是从仓库文件读取，证据位于 `lib/core/config/app_secrets.dart`。

## Webhook 与回调

**入站：**
- 未检测到 Webhook、推送回调、后台 HTTP 服务或 Socket 服务端入口。

**出站：**
- DeepSeek HTTPS 请求：`lib/core/extraction/deepseek_text_understanding_engine.dart`、`lib/core/extraction/deepseek_ocr_text_correction_engine.dart`
- ML Kit 手写模型下载：由 `lib/features/canvas/services/handwriting_recognition_service.dart` 触发
- 系统分享面板回调：`lib/features/notedetail/note_detail_screen.dart` 通过 `Share.share(...)` 调用系统能力

---

*外部集成审计：2026-04-16*
