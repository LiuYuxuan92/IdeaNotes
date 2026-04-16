# Codebase Concerns

**Analysis Date:** 2026-04-16

**验证基线：**
- 已检查核心目录、平台配置、存储层、Canvas/OCR/AI 链路、查询与测试代码。
- 已在当前仓库执行 `flutter analyze` 与 `flutter test`；当前代码库存在编译级错误，且测试基建在当前 Windows 环境不可用。

## Tech Debt

**结构化数据仍然处于“双写 + 双读”过渡态：**
- Issue: 保存时同时写入旧表 `note_entries` 和新表 `entries`，详情页又在结构化读取失败时回退到旧表或再次本地解析，数据流已经分叉。
- Files: `lib/features/canvas/services/canvas_save_service.dart`, `lib/core/storage/database_migrations.dart`, `lib/core/storage/database_helper.dart`, `lib/core/storage/entry_repository.dart`, `lib/features/notedetail/note_detail_screen.dart`
- Impact: 任何一侧 schema、解析规则或保存逻辑变化，都可能造成新旧数据不一致、详情页展示不一致、回归范围扩大。
- Fix approach: 明确迁移终点，只保留一条主写路径；旧表只做一次性迁移或兼容读，移除运行时双写与详情页兜底分支。

**Canvas 相关 UI 与业务逻辑过度集中在巨型文件：**
- Issue: `CanvasScreen` 同时承载画布手势、OCR、AI 预览、语音、权限、保存、布局适配和多个私有 Widget。
- Files: `lib/features/canvas/canvas_screen.dart`, `lib/features/canvas/widgets/canvas_painter.dart`, `lib/features/canvas/services/canvas_save_service.dart`, `lib/features/canvas/services/canvas_ai_preview_service.dart`, `lib/features/canvas/services/voice_recognition_service.dart`
- Impact: 单文件改动面过大，容易出现局部修改影响整页交互；编译错误和测试失败也会被放大到整个 Canvas 功能域。
- Fix approach: 按“画布渲染 / OCR / AI 预览 / 语音 / 保存编排 / 页面布局”拆分控制器和视图组件，缩小变更半径。

**基础设施仍依赖全局单例和页面内直接实例化：**
- Issue: `DatabaseHelper.instance` 被多个页面直接引用，`CanvasScreen` 和记录中心也直接 new 服务对象，依赖注入边界不统一。
- Files: `lib/core/storage/database_helper.dart`, `lib/app/app.dart`, `lib/features/canvas/canvas_screen.dart`, `lib/features/records/records_hub_screen.dart`, `lib/features/notedetail/note_detail_screen.dart`
- Impact: 测试替换依赖需要通过 `injectDatabase()` 之类的测试专用入口，页面级重构成本高，跨环境行为难以稳定模拟。
- Fix approach: 将存储与服务依赖统一收口到应用根或 feature scope provider，通过构造注入替代页面内部直接创建。

## Known Bugs

**AI 相关代码当前会直接导致静态检查和测试编译失败：**
- Symptoms: `flutter analyze` 当前报 6 个错误；`flutter test` 也因为同一组编译问题导致多组 widget test 无法加载。
- Files: `lib/core/extraction/deepseek_api_defaults.dart`, `lib/core/extraction/deepseek_ocr_text_correction_engine.dart`, `lib/core/extraction/deepseek_text_understanding_engine.dart`, `lib/features/canvas/canvas_screen.dart`, `test/extraction/deepseek_text_understanding_engine_test.dart`
- Trigger: 执行 `flutter analyze` 或 `flutter test`；涉及不存在的 `DeepSeekApiDefaults.apiKey`、对非 `const` 构造函数的 `const` 调用、测试中错误使用 `const DeepSeekTextUnderstandingEngine(...)`。
- Workaround: 无稳定绕过方案，需先修正默认配置与构造调用，再恢复分析和测试。

**数据库测试基建在当前 Windows 环境下不可运行：**
- Symptoms: 多个 bloc、service、migration 测试在启动内存数据库时抛出 `Unable to load sqlite3 dynamic library`。
- Files: `test/bloc/note_list_bloc_test.dart`, `test/services/canvas_save_service_test.dart`, `test/storage/database_migrations_test.dart`
- Trigger: 在当前 Windows 开发环境执行 `flutter test`；测试代码只尝试加载 Linux `.so` 路径和 `libsqlite3.so`。
- Workaround: 临时切到 Linux/WSL 环境，或先把测试初始化改成 `sqfliteFfiInit()` / 平台感知加载逻辑。

**编辑已有笔记时会遗留旧快照和缩略图文件：**
- Symptoms: 同一笔记多次保存后，数据库只保留最新路径，但旧 PNG 文件仍留在应用文档目录中。
- Files: `lib/core/storage/image_storage.dart`, `lib/features/canvas/services/canvas_save_service.dart`
- Trigger: 打开已有笔记并重复保存；`saveSnapshot()` / `saveThumbnail()` 每次生成新 UUID 文件名，更新流程没有清理旧文件。
- Workaround: 目前只有手工调用 `ImageStorage.deleteNoteImages(noteId)` 或清空图片目录，缺少自动回收。

## Security Considerations

**LLM API Key 仍走客户端直连模式，密钥边界不安全：**
- Risk: `DEEPSEEK_API_KEY` 虽然不再硬编码在仓库里，但仍被设计为直接注入客户端应用并由移动端向 DeepSeek 发起请求；一旦发布安装包，密钥可以被逆向或抓包复用。
- Files: `lib/core/config/app_secrets.dart`, `lib/core/extraction/deepseek_text_understanding_engine.dart`, `lib/core/extraction/deepseek_ocr_text_correction_engine.dart`
- Current mitigation: 使用 `String.fromEnvironment('DEEPSEEK_API_KEY')` 避免源码明文泄漏。
- Recommendations: 将 AI 请求迁移到受控后端或短期令牌代理，不在客户端长期持有第三方服务密钥。

**OCR 文本、AI 原始响应和结构化结果以明文落地到本地 SQLite：**
- Risk: `recognized_text`、`input_text`、`raw_response_json`、`normalized_entries_json` 可能包含个人隐私、健康信息和消费记录，但当前没有加密存储或二次脱敏。
- Files: `lib/core/storage/database_migrations.dart`, `lib/core/storage/entry_repository.dart`, `lib/features/canvas/services/canvas_save_service.dart`
- Current mitigation: 未检测到本地加密、字段脱敏或按敏感级别拆分存储。
- Recommendations: 为本地数据库和图片文件引入加密或至少敏感字段裁剪策略；对 `ai_extractions` 设定保留期和可关闭开关。

**iOS 网络与权限面配置偏宽：**
- Risk: `NSAllowsArbitraryLoads` 全局放开 ATS，会扩大明文或弱 TLS 连接面；同时 iOS/Android 声明了较多权限和能力，包含相机、麦克风、相册、Face ID、后台模式等，而当前代码并未展示完整的最小权限治理。
- Files: `ios/Runner/Info.plist`, `android/app/src/main/AndroidManifest.xml`, `lib/features/canvas/canvas_screen.dart`
- Current mitigation: 运行时通过 `permission_handler` 请求部分权限。
- Recommendations: 收紧 ATS 到必要域名；删除未使用的能力声明；将权限说明与实际功能保持一一对应，减少审核和隐私风险。

## Performance Bottlenecks

**记录中心的统计与时间线依赖“全量拉取后在 Dart 聚合”：**
- Problem: `AnalyticsService` 和 `TimelineService` 先调用 `EntryRepository.queryEntries()` 拉取结果集，再在内存里做金额汇总、分类汇总、月份趋势和分组。
- Files: `lib/core/query/analytics_service.dart`, `lib/core/query/timeline_service.dart`, `lib/core/storage/entry_repository.dart`, `lib/features/records/records_hub_screen.dart`
- Cause: 缺少 SQL 聚合、分页和按需查询，页面每次切换 tab/range 都重跑整套查询。
- Improvement path: 将金额汇总、趋势、分组下推到 SQL 层；为记录中心增加分页和轻量化统计接口。

**Canvas 截图、裁剪、缩放和 PNG 编码在 UI 路径上同步执行：**
- Problem: 画布保存和缩略图生成会在页面逻辑里进行图片裁剪、缩放和编码，笔迹越多、图片越大，越容易拉长交互等待时间。
- Files: `lib/features/canvas/canvas_screen.dart`, `lib/core/storage/image_storage.dart`
- Cause: `image` 包处理和 PNG 编码没有下沉到 isolate，保存按钮串联了多步 CPU 密集操作。
- Improvement path: 将重型图片处理迁移到 isolate 或后台任务；为保存流程引入分阶段进度和缓存策略。

**图片文件累积会带来长期 I/O 与存储压力：**
- Problem: 快照和缩略图使用 UUID 文件名追加写入，旧版本图片不自动回收。
- Files: `lib/core/storage/image_storage.dart`, `lib/features/canvas/services/canvas_save_service.dart`
- Cause: 现有实现只负责写新文件，不负责替换式更新和定期清理。
- Improvement path: 对同一 `noteId` 使用稳定路径或保存前清理旧版本，并增加存储统计告警与后台清扫。

## Fragile Areas

**Canvas 功能栈是当前最脆弱的改动区域：**
- Files: `lib/features/canvas/canvas_screen.dart`, `lib/features/canvas/bloc/canvas_bloc.dart`, `lib/features/canvas/services/canvas_save_service.dart`, `lib/features/canvas/services/canvas_ai_preview_service.dart`, `lib/features/canvas/services/handwriting_recognition_service.dart`
- Why fragile: UI、状态机、平台权限、OCR、AI、语音、保存全部耦合在同一特性域，且存在多个 `catch (_) {}` 静默降级分支，问题容易被吞掉。
- Safe modification: 先补足 feature 级集成测试，再拆接口和依赖注入；避免在同一次变更里同时碰保存、OCR 和布局。
- Test coverage: 当前有 `test/services/canvas_save_service_test.dart`、`test/widgets/canvas_screen_test.dart`，但前者受 SQLite FFI 环境影响，后者又被编译错误阻断。

**详情页同时兼容新旧数据展示路径，容易出现展示分叉：**
- Files: `lib/features/notedetail/note_detail_screen.dart`, `lib/core/storage/entry_repository.dart`, `lib/core/storage/database_helper.dart`, `lib/core/parser/entry_parser.dart`
- Why fragile: 页面优先读结构化表，失败后再读旧表或重新 parse 文本，任何一步行为变化都可能改变最终 UI。
- Safe modification: 先确定详情页唯一数据源，再删掉兜底回退；保留迁移脚本，不保留运行时多路解释。
- Test coverage: 现有 `test/widgets/note_detail_screen_test.dart` 覆盖不了双路数据一致性，而且当前也被编译错误阻塞。

**测试基础设施本身就是脆弱点：**
- Files: `test/bloc/note_list_bloc_test.dart`, `test/storage/database_migrations_test.dart`, `test/services/canvas_save_service_test.dart`
- Why fragile: 三套测试都内嵌了 Linux 专用 SQLite 动态库加载逻辑，环境一变就会整体失效。
- Safe modification: 提取统一测试数据库初始化工具，使用官方 FFI 初始化路径；把平台差异封装掉。
- Test coverage: 当前不是“覆盖不足”而是“覆盖无法稳定执行”，对回归保护价值被显著削弱。

## Scaling Limits

**笔记搜索目前依赖全量加载到内存后过滤：**
- Current capacity: 适合小型本地数据集；`NoteListBloc` 先全量 `getNotes()`，再用 `searchableText.contains()` 过滤。
- Limit: 当笔记数量和 OCR 文本长度继续增长时，搜索与列表刷新会同时受到内存占用和字符串扫描成本影响。
- Scaling path: 将搜索切换到存储层查询或 FTS；统一 `SearchScreen`、`NoteListBloc` 与 `DatabaseHelper.searchNotes()` 的实现路径。
- Files: `lib/features/notelist/bloc/note_list_bloc.dart`, `lib/features/search/search_screen.dart`, `lib/core/storage/database_helper.dart`, `lib/core/models/note.dart`

**结构化记录页面没有分页、没有增量加载：**
- Current capacity: 当前页面默认以“近 30 天 / 90 天 / 1 年 / 全部”整段区间查询。
- Limit: 记录条目持续增加后，`RecordsHubScreen` 的首屏加载、tab 切换和时间范围切换都会线性变慢。
- Scaling path: 引入分页、窗口化时间线和 SQL 预聚合视图。
- Files: `lib/features/records/records_hub_screen.dart`, `lib/core/query/analytics_service.dart`, `lib/core/query/timeline_service.dart`, `lib/core/storage/entry_repository.dart`

**本地图片与 AI 审计数据没有保留上限：**
- Current capacity: 未检测到图片保留策略、AI 审计裁剪策略或定期清理任务。
- Limit: 长期使用后，`images/` 目录和 `ai_extractions` 表会持续膨胀，影响磁盘占用、备份体积和查询延迟。
- Scaling path: 增加按笔记版本回收、按时间淘汰、用户可关闭 AI 审计等机制。
- Files: `lib/core/storage/image_storage.dart`, `lib/core/storage/database_migrations.dart`, `lib/core/storage/entry_repository.dart`

## Dependencies at Risk

**`sqflite_common_ffi` / `sqlite3`：**
- Risk: 当前测试代码没有走官方跨平台初始化，而是手写 Linux 动态库路径列表，导致 Windows 环境直接失效。
- Impact: 本地与 CI 的数据库测试不可移植，回归保护随环境变化而失效。
- Migration plan: 使用 `sqfliteFfiInit()` 或平台分支加载；抽出统一测试 helper，避免每个测试文件复制一套加载逻辑。
- Files: `test/bloc/note_list_bloc_test.dart`, `test/services/canvas_save_service_test.dart`, `test/storage/database_migrations_test.dart`

**`google_mlkit_text_recognition` / `google_mlkit_digital_ink_recognition`：**
- Risk: OCR 与手写识别依赖移动端插件、模型可用性和设备能力，桌面/测试环境无法真实覆盖。
- Impact: OCR 与手写识别的失败模式主要在真机上暴露，容易形成“开发环境正常、线上设备异常”的落差。
- Migration plan: 保持接口抽象，同时补充真机回归脚本、错误上报和远程开关；必要时增加服务端或替代引擎兜底。
- Files: `lib/core/ocr/mlkit_ocr.dart`, `lib/core/ocr/vision_ocr.dart`, `lib/features/canvas/services/handwriting_recognition_service.dart`, `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`

## Missing Critical Features

**自动化 CI 护栏缺失：**
- Problem: 仓库只有 `.github/pull_request_template.md`，没有 `.github/workflows/` 下的分析、测试或构建流水线。
- Blocks: 阻碍在提交和合并前自动发现当前这类编译失败、测试环境失配和平台配置回归。

**本地隐私保护能力缺失：**
- Problem: 当前没有数据库加密、图片加密、AI 审计开关、敏感字段裁剪或导出/清理策略。
- Blocks: 阻碍应用安全地承载健康记录、消费记录和 OCR 原文这类高敏感数据。
- Files: `lib/core/storage/database_migrations.dart`, `lib/core/storage/entry_repository.dart`, `lib/core/storage/image_storage.dart`

**端到端验证链路缺失：**
- Problem: 当前没有 integration test / 真机回归脚本去覆盖“画布书写 -> OCR -> AI 预览 -> 保存 -> 列表/详情回显”的主链路。
- Blocks: 阻碍对最核心用户路径建立稳定回归保障。
- Files: `lib/features/canvas/canvas_screen.dart`, `lib/features/notelist/note_list_screen.dart`, `lib/features/notedetail/note_detail_screen.dart`, `test/widgets/canvas_screen_test.dart`

## Test Coverage Gaps

**平台能力与权限链路没有可执行的自动化验证：**
- What's not tested: 麦克风权限、语音识别、ML Kit OCR、手写识别、iOS/Android 平台配置是否与代码一致。
- Files: `lib/features/canvas/canvas_screen.dart`, `lib/features/canvas/services/voice_recognition_service.dart`, `lib/core/ocr/mlkit_ocr.dart`, `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`
- Risk: 权限拒绝、插件初始化失败、平台配置缺失会在真机首发后才暴露。
- Priority: High

**主保存链路缺少稳定的跨环境回归：**
- What's not tested: 编辑已有笔记后的旧图片清理、AI 预览后保存、重新打开详情页后的新旧数据一致性。
- Files: `lib/features/canvas/services/canvas_save_service.dart`, `lib/core/storage/image_storage.dart`, `lib/features/notedetail/note_detail_screen.dart`
- Risk: 容易在“保存成功但数据/图片/详情展示不一致”这类问题上出现静默回归。
- Priority: High

**搜索与记录中心的规模化行为没有覆盖：**
- What's not tested: 大量笔记、大量结构化记录、长 OCR 文本场景下的性能与正确性。
- Files: `lib/features/notelist/bloc/note_list_bloc.dart`, `lib/features/search/search_screen.dart`, `lib/features/records/records_hub_screen.dart`, `lib/core/query/analytics_service.dart`
- Risk: 当前功能在小数据量下可用，但上线后可能因为数据规模变化出现卡顿或错误统计。
- Priority: Medium

## 建议优先级

1. **P0：先恢复“能编译、能分析、能跑测试”的基线。**
- 立即修复 `DeepSeekApiDefaults.apiKey` 悬空引用和错误的 `const` 调用，保证 `flutter analyze`、`flutter test` 至少能进入可执行状态。
- Files: `lib/core/extraction/deepseek_ocr_text_correction_engine.dart`, `lib/features/canvas/canvas_screen.dart`, `test/extraction/deepseek_text_understanding_engine_test.dart`

2. **P0：修复 SQLite 测试基建的跨平台初始化。**
- 否则当前仓库在 Windows 环境下没有可信回归护栏。
- Files: `test/bloc/note_list_bloc_test.dart`, `test/services/canvas_save_service_test.dart`, `test/storage/database_migrations_test.dart`

3. **P1：收敛客户端安全边界与隐私风险。**
- 重点处理“客户端直连 LLM 密钥”“本地明文存储 AI/OCR 敏感数据”“iOS ATS/权限面过宽”三项。
- Files: `lib/core/config/app_secrets.dart`, `lib/core/extraction/deepseek_text_understanding_engine.dart`, `lib/core/storage/entry_repository.dart`, `ios/Runner/Info.plist`, `android/app/src/main/AndroidManifest.xml`

4. **P1：修复图片文件泄漏与长期存储膨胀。**
- 这是会随使用时间放大的问题，应在功能继续扩展前处理。
- Files: `lib/core/storage/image_storage.dart`, `lib/features/canvas/services/canvas_save_service.dart`

5. **P2：拆分巨型页面并结束新旧数据双轨运行。**
- 这两项直接决定后续 OCR、AI、详情页和查询中心的可维护性。
- Files: `lib/features/canvas/canvas_screen.dart`, `lib/features/notedetail/note_detail_screen.dart`, `lib/features/canvas/services/canvas_save_service.dart`, `lib/core/storage/database_migrations.dart`

6. **P2：补齐 CI 与端到端主链路验证。**
- 没有自动护栏，后续任何重构都会重复引入类似的编译和环境问题。
- Files: `.github`, `test/widgets/canvas_screen_test.dart`, `lib/features/canvas/canvas_screen.dart`

---

*Concerns audit: 2026-04-16*
