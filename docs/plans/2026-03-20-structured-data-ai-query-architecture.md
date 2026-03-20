# IdeaNotes 结构化数据与 AI 查询架构方案

**项目**: IdeaNotes  
**日期**: 2026-03-20  
**版本**: 1.0.0-draft  
**范围**: 本地 SQLite 数据层、OCR/AI 抽取链路、时间查询能力、统计分析能力、后续模型接入边界  

## 1. 背景与目标

IdeaNotes 当前已经具备以下基础能力：

- 手写画布记录
- OCR 文本识别结果保存
- 将 OCR 文本按行解析为 `expense / event / memo`
- 笔记列表与关键字搜索

但当前系统仍然是“笔记中心”的，而不是“事实中心”的：

- 查询入口仍以笔记列表为主
- 搜索仅匹配 `recognized_text`
- `note_entries` 仅用于展示，没有形成长期可检索的数据资产
- 无时间范围聚合、无分类统计、无对象档案、无自然语言查询

本方案的目标不是继续强化“OCR 笔记”，而是将 IdeaNotes 升级为：

1. **按日期组织的事实库**
2. **兼容 OCR + AI 双轨抽取**
3. **支持时间轴、分类统计、对象档案、自然语言查询**
4. **保留原始手写证据、OCR 原文、AI 抽取结果三层证据链**

## 2. 为什么必须从 OCR 走向 AI + OCR

纯 OCR 只能解决“识别出文字”，不能稳定解决以下问题：

- 一段文字里包含多条事实，如何拆分
- “今天”“下个月”“去年”“周三”如何归一化到准确日期
- “宝宝打了五联疫苗，自费 628 元，下个月复查”属于几条记录
- 金额、类别、对象、动作、状态之间如何关联
- “疫苗”“体检”“复查”“奶粉”“报销”“会议”这类跨领域信息如何统一检索

因此建议采用双层理解架构：

- **OCR 层**：负责把图像变成尽可能完整的文本
- **AI 层**：负责把文本理解为结构化事实

最终目标不是“更强的 OCR”，而是“更强的事实提取与查询”。

## 3. 当前代码基线

当前仓库中，与本方案直接相关的已有实现包括：

- OCR 引擎抽象：`lib/core/ocr/ocr_engine.dart`
- 画布 OCR 服务：`lib/features/canvas/services/canvas_ocr_service.dart`
- OCR 结果保存与 `note_entries` 写库：`lib/features/canvas/services/canvas_save_service.dart`
- 规则解析器：`lib/core/parser/entry_parser.dart`
- 花费提取器：`lib/core/parser/expense_extractor.dart`
- SQLite 表定义：`lib/core/storage/database_helper.dart`

当前的优势：

- 已存在本地数据库
- 已存在 OCR 抽象层
- 已存在规则抽取器
- 已存在 `note_entries` 结构化入口

当前的限制：

- `note_entries` 类型过粗，只适合展示，不适合长期查询
- 没有跨笔记、跨时间范围的结构化查询接口
- 没有 AI 抽取结果持久化与纠错机制
- 没有对象、标签、关系、置信度、确认状态等事实管理能力

## 4. 目标架构总览

建议将系统拆为五层：

### 4.1 证据层

保存不可丢失的原始材料：

- 原始画布数据
- 画布快照
- 缩略图
- 原始 OCR 文本
- OCR 行块与置信度（后续升级）

### 4.2 规则抽取层

继续保留现有 `EntryParser`，但定位调整为：

- 显式金额提取
- 显式日期提取
- 简单事项关键词提取
- 为 AI 提供先验候选结果

### 4.3 AI 抽取层

新增统一抽取服务：

- 输入：OCR 文本、笔记日期、规则抽取结果、上下文设定
- 输出：标准化事实数组 JSON
- 能力：拆分事实、归一化日期、分类、对象识别、关系提取、摘要、置信度

### 4.4 持久化层

将规则结果与 AI 结果合并后写入 SQLite：

- 可追溯
- 可统计
- 可回滚
- 可人工修正

### 4.5 查询与分析层

提供：

- 时间轴查询
- 分类统计
- 对象档案
- 专题筛选
- 自然语言检索

## 5. 数据模型重构方案

### 5.1 保留现有 `notes` 表

`notes` 继续作为原始笔记容器，负责：

- 画布
- 快照
- 原始 OCR 文本
- 创建/更新时间

其角色变为“证据源”，而非唯一查询主实体。

### 5.2 将 `note_entries` 升级为通用事实表 `entries`

建议新增 `entries` 表，而不是继续沿用现有 `note_entries` 字段集合硬扩。

建议字段如下：

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | TEXT PK | 事实 ID |
| `note_id` | TEXT NOT NULL | 来源笔记 |
| `entry_type` | TEXT NOT NULL | 事实类型 |
| `domain` | TEXT NOT NULL | 领域，如 finance/health/work/life |
| `occurred_at` | INTEGER | 精确时间戳 |
| `occurred_date` | TEXT NOT NULL | 归一化日期，格式 `YYYY-MM-DD` |
| `end_at` | INTEGER | 区间事件结束时间，可空 |
| `title` | TEXT NOT NULL | 标准标题 |
| `summary` | TEXT | AI 归纳摘要 |
| `raw_text` | TEXT NOT NULL | 原始 OCR 片段 |
| `normalized_json` | TEXT | 结构化扩展 JSON |
| `amount_value` | TEXT | 金额，文本存储 Decimal |
| `amount_currency` | TEXT | 币种，如 CNY |
| `category_l1` | TEXT | 一级分类 |
| `category_l2` | TEXT | 二级分类 |
| `status` | TEXT | pending/done/cancelled/recorded |
| `confidence` | REAL | 0-1 |
| `is_user_confirmed` | INTEGER | 是否人工确认 |
| `source_engine` | TEXT | rule/ocr/ai/merged |
| `source_version` | TEXT | 抽取器或模型版本 |
| `created_at` | INTEGER | 创建时间 |
| `updated_at` | INTEGER | 更新时间 |

### 5.3 新增对象表 `entry_subjects`

用于表达“这条记录关于谁/什么”。

字段建议：

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | TEXT PK | 主键 |
| `entry_id` | TEXT NOT NULL | 关联事实 |
| `subject_name` | TEXT NOT NULL | 如 宝宝 / 妈妈 / 项目A / 车辆 |
| `subject_type` | TEXT NOT NULL | person/pet/object/project/custom |
| `role` | TEXT | patient/owner/payer/assignee 等 |
| `created_at` | INTEGER | 创建时间 |

说明：

- 一条事实可以挂多个对象
- 同一个对象可以在未来形成“对象档案页”

### 5.4 新增标签表 `entry_tags`

字段建议：

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | TEXT PK | 主键 |
| `entry_id` | TEXT NOT NULL | 关联事实 |
| `tag` | TEXT NOT NULL | 标签名 |
| `created_at` | INTEGER | 创建时间 |

### 5.5 新增关系表 `entry_links`

用于表达事实之间的关系：

- “复查”关联“疫苗记录”
- “报销”关联“消费”
- “任务完成”关联“原始待办”

字段建议：

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | TEXT PK | 主键 |
| `from_entry_id` | TEXT NOT NULL | 起点 |
| `to_entry_id` | TEXT NOT NULL | 终点 |
| `link_type` | TEXT NOT NULL | follow_up / related / caused_by / settles |
| `created_at` | INTEGER | 创建时间 |

### 5.6 新增 AI 抽取记录表 `ai_extractions`

用于审计、回放、纠错与未来模型升级。

字段建议：

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | TEXT PK | 主键 |
| `note_id` | TEXT NOT NULL | 来源笔记 |
| `engine_name` | TEXT NOT NULL | gemini/openai/local 等 |
| `engine_model` | TEXT NOT NULL | 模型名 |
| `prompt_version` | TEXT NOT NULL | Prompt 版本 |
| `input_text` | TEXT NOT NULL | 输入 OCR 文本 |
| `raw_response_json` | TEXT NOT NULL | 模型原始返回 |
| `normalized_entries_json` | TEXT NOT NULL | 标准化后事实数组 |
| `status` | TEXT NOT NULL | success/failed/review_required |
| `created_at` | INTEGER | 创建时间 |

### 5.7 新增保存视图/查询模板表 `saved_filters`

用于保存常用查询：

- 近一年花费
- 近半年医疗记录
- 本月待办
- 年度出行

字段建议：

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | TEXT PK | 主键 |
| `name` | TEXT NOT NULL | 查询名 |
| `filter_json` | TEXT NOT NULL | 过滤条件 JSON |
| `sort_json` | TEXT | 排序配置 |
| `created_at` | INTEGER | 创建时间 |
| `updated_at` | INTEGER | 更新时间 |

## 6. 建议的事实类型与领域体系

### 6.1 `entry_type`

建议首批支持：

- `expense`
- `income`
- `task`
- `appointment`
- `health_record`
- `vaccination`
- `medication`
- `metric`
- `purchase`
- `travel`
- `document`
- `memo`
- `custom`

### 6.2 `domain`

建议首批支持：

- `finance`
- `health`
- `family`
- `work`
- `learning`
- `life`
- `travel`
- `custom`

### 6.3 分类体系

对于金额类记录，建议保留两级分类：

- `category_l1`
  - 餐饮
  - 交通
  - 购物
  - 医疗
  - 教育
  - 居住
  - 娱乐
  - 育儿
  - 办公
  - 其他
- `category_l2`
  - 由 AI 或规则进一步细分，例如：
  - 疫苗
  - 药品
  - 奶粉
  - 报销
  - 打车
  - 外卖

## 7. 数据库迁移方案

### 7.1 迁移原则

- 保留旧数据
- 不破坏现有 `notes`
- `note_entries` 可在过渡阶段继续保留
- 新功能全部落在新表

### 7.2 版本建议

建议从当前 `version: 3` 迁移到 `version: 6`

#### v4

- 新建 `entries`
- 新建索引

#### v5

- 新建 `entry_subjects`
- 新建 `entry_tags`
- 新建 `entry_links`

#### v6

- 新建 `ai_extractions`
- 新建 `saved_filters`
- 新建 FTS 虚表

### 7.3 迁移脚本策略

启动时执行：

1. 建新表
2. 将旧 `note_entries` 数据映射迁移到 `entries`
3. 为历史数据生成默认字段：
   - `occurred_date`: 优先使用 `event_date`，否则回退 `notes.created_at`
   - `entry_type`: 映射旧 type
   - `domain`: `expense -> finance`，`event -> life`，`memo -> life`
   - `source_engine`: `rule-legacy`
4. 历史迁移完成后保留 `note_entries` 一段时间，待稳定后再删除

## 8. OCR + AI 编排方案

### 8.1 现有边界

当前已有：

- `OcrEngine`
- `CanvasOcrService`
- `CanvasSaveService`

建议新增以下抽象：

- `TextUnderstandingEngine`
- `AiExtractionService`
- `EntryMergeService`
- `EntryPersistenceService`
- `ExtractionOrchestrator`

### 8.2 新的处理链路

#### Step 1: 采集

- 用户在画布上书写
- 系统保存原始画布与快照

#### Step 2: OCR

- OCR 输出：
  - 原始全文
  - 行数组
  - 块信息（后续）

#### Step 3: 规则抽取

- 运行 `EntryParser`
- 快速得到显式金额/显式日期/显式事件

#### Step 4: AI 抽取

- 将 OCR 文本、笔记日期、规则候选结果一并送入 AI
- 输出标准 JSON

#### Step 5: 合并

- 规则结果与 AI 结果做对齐
- 冲突时保留证据
- 低置信度项标记待确认

#### Step 6: 写库

- 写 `entries`
- 写 `entry_subjects`
- 写 `entry_tags`
- 写 `entry_links`
- 写 `ai_extractions`

#### Step 7: 建索引与查询缓存

- 更新 FTS
- 更新分析聚合缓存（如果后面需要）

## 9. AI 抽取 JSON Schema

### 9.1 设计原则

AI 输出必须：

- 结构稳定
- 字段可验证
- 允许空值
- 不依赖模型自由发挥字段名
- 可做版本控制

### 9.2 顶层结构

```json
{
  "schema_version": "1.0",
  "note_context": {
    "note_id": "string",
    "note_created_at": "2026-03-20T10:30:00+08:00",
    "timezone": "Asia/Shanghai",
    "locale": "zh-CN"
  },
  "ocr_summary": {
    "full_text": "string",
    "line_count": 4
  },
  "entries": [],
  "warnings": [],
  "unparsed_segments": []
}
```

### 9.3 `entries[]` 单条结构

```json
{
  "entry_id": "uuid-or-stable-temp-id",
  "entry_type": "expense",
  "domain": "finance",
  "title": "五联疫苗费用",
  "summary": "宝宝今日接种五联疫苗并支付自费金额",
  "raw_text": "今天带宝宝打五联疫苗，自费628元",
  "occurred_at": "2026-03-20T09:30:00+08:00",
  "occurred_date": "2026-03-20",
  "end_at": null,
  "status": "recorded",
  "amount": {
    "value": "628.00",
    "currency": "CNY"
  },
  "category": {
    "l1": "医疗",
    "l2": "疫苗"
  },
  "subjects": [
    {
      "name": "宝宝",
      "type": "person",
      "role": "patient"
    }
  ],
  "tags": [
    "疫苗",
    "儿保"
  ],
  "links": [
    {
      "target_entry_temp_id": "entry-follow-up-1",
      "type": "follow_up"
    }
  ],
  "normalized": {
    "vaccine_name": "五联疫苗",
    "dose": null,
    "hospital_name": null
  },
  "confidence": 0.93
}
```

### 9.4 特殊要求

AI 输出必须遵守：

1. 所有日期都必须归一化到绝对日期
2. 所有金额必须输出为字符串，不输出浮点
3. 所有分类都必须使用给定枚举或回退到 `其他`
4. 无法确认的字段必须写 `null`
5. 不得省略 `raw_text`
6. 一段文本包含多事实时必须拆条

## 10. 查询 API / Service 设计

本项目是 Flutter 本地应用，建议先做 **Dart Service API**，不先做 HTTP API。

### 10.1 查询条件模型 `EntryQuery`

建议字段：

```dart
class EntryQuery {
  final DateTime? from;
  final DateTime? to;
  final Set<String> entryTypes;
  final Set<String> domains;
  final Set<String> categoryL1;
  final Set<String> categoryL2;
  final Set<String> subjectNames;
  final Set<String> tags;
  final String? keyword;
  final bool? confirmedOnly;
  final String sortBy;
  final bool descending;
}
```

### 10.2 时间轴查询服务 `TimelineService`

建议方法：

- `Future<List<TimelineDayGroup>> getDailyTimeline(EntryQuery query)`
- `Future<List<TimelineMonthGroup>> getMonthlyTimeline(EntryQuery query)`
- `Future<List<TimelineYearGroup>> getYearlyTimeline(EntryQuery query)`
- `Future<List<EntryRecord>> getEntriesByDate(DateTime day)`

### 10.3 统计服务 `AnalyticsService`

建议方法：

- `Future<AmountSummary> getAmountSummary(EntryQuery query)`
- `Future<List<CategoryAmountStat>> getAmountByCategory(EntryQuery query)`
- `Future<List<MonthlyTrendPoint>> getMonthlyAmountTrend(EntryQuery query)`
- `Future<List<EntryCountStat>> getEntryCountByType(EntryQuery query)`
- `Future<List<SubjectStat>> getTopSubjects(EntryQuery query)`

### 10.4 对象档案服务 `SubjectArchiveService`

建议方法：

- `Future<SubjectArchive> getArchive(String subjectName, EntryQuery baseQuery)`
- `Future<List<EntryRecord>> getEntriesForSubject(String subjectName, EntryQuery query)`
- `Future<List<CategoryAmountStat>> getAmountByCategoryForSubject(String subjectName, EntryQuery query)`

### 10.5 智能检索服务 `SmartSearchService`

建议两段式：

1. 结构化筛选阶段
2. AI 总结阶段

方法建议：

- `Future<StructuredSearchPlan> parseNaturalLanguageQuery(String query)`
- `Future<List<EntryRecord>> executeStructuredSearch(StructuredSearchPlan plan)`
- `Future<String> summarizeSearchResults(String query, List<EntryRecord> entries)`

## 11. 查询场景示例

### 11.1 查一年内的花费并按分类汇总

查询条件：

- `from = today - 365d`
- `to = today`
- `entry_type = expense`

输出：

- 总支出
- 分类占比
- 月趋势
- 明细列表

### 11.2 查一年内的医疗记录

查询条件：

- `domain = health`
- 日期范围近一年

输出：

- 时间轴
- 医疗相关费用
- 事项/复查/用药分组

### 11.3 查某对象的年度记录

例如：

- `subject_name = 宝宝`
- 日期范围今年

输出：

- 所有健康记录
- 所有医疗支出
- 所有复查事项
- 疫苗时间线

### 11.4 自然语言查询

例子：

- “近一年餐饮花费最多的是哪几个月”
- “今年有哪些复查事项还没完成”
- “宝宝去年打过哪些疫苗”
- “三月份所有跟报销有关的记录”

执行策略：

1. AI 先把自然语言转结构化查询计划
2. 本地 SQLite 执行
3. 必要时再用 AI 生成说明文字

## 12. 索引与性能策略

### 12.1 必备索引

建议为 `entries` 添加：

- `idx_entries_occurred_date`
- `idx_entries_type_date`
- `idx_entries_domain_date`
- `idx_entries_category_l1_date`
- `idx_entries_note_id`
- `idx_entries_status`

为 `entry_subjects` 添加：

- `idx_subjects_name`
- `idx_subjects_entry_id`

为 `entry_tags` 添加：

- `idx_tags_tag`
- `idx_tags_entry_id`

### 12.2 FTS 建议

建议增加 FTS 虚表，纳入：

- `title`
- `summary`
- `raw_text`
- `category_l1`
- `category_l2`
- `subject_name`
- `tags`

### 12.3 聚合策略

短期：

- 实时 SQL 聚合即可

中后期：

- 可增加月度缓存表 `entry_analytics_monthly`
- 在保存后异步更新

## 13. 置信度、纠错与人工确认机制

AI 接入后，必须有“可纠错”的产品机制。

### 13.1 每条事实保留置信度

规则：

- `>= 0.9` 自动入库，默认已接受
- `0.6 - 0.89` 入库但标记待确认
- `< 0.6` 仅进入候选区，不进入主时间轴

### 13.2 用户确认操作

用户应可以：

- 修改类型
- 修改日期
- 修改金额
- 修改分类
- 修改标题
- 增删标签
- 合并/拆分事实

### 13.3 纠错沉淀

建议保留：

- AI 原始输出
- 用户修改后的最终值
- 差异记录

未来可用于：

- Prompt 优化
- 本地规则增强
- 小样本微调/评估

## 14. 隐私与模型接入策略

### 14.1 建议的部署策略

建议按三档支持：

#### 档位 A：纯本地

- 仅 OCR
- 仅规则抽取
- 无云模型

#### 档位 B：OCR + 云 AI

- OCR 本地
- 结构化理解走云模型
- 适合高精度需求

#### 档位 C：OCR + 本地小模型 + 云大模型兜底

- 优先本地理解
- 复杂场景转云端

### 14.2 配置建议

新增设置项：

- 是否开启 AI 抽取
- AI 提供商
- 模型名称
- 是否上传原图
- 仅上传 OCR 文本 / 上传裁剪片段 / 上传整页图
- 是否保存 AI 原始响应

### 14.3 数据最小化

优先上传：

- OCR 文本
- 笔记日期
- 小范围上下文

非必要不要默认上传整张原图。

## 15. 模块拆分建议

建议新增目录：

```text
lib/
  core/
    extraction/
      extraction_models.dart
      text_understanding_engine.dart
      ai_extraction_service.dart
      entry_merge_service.dart
      extraction_orchestrator.dart
    query/
      entry_query.dart
      timeline_service.dart
      analytics_service.dart
      subject_archive_service.dart
      smart_search_service.dart
    storage/
      database_migrations.dart
      entry_repository.dart
      analytics_repository.dart
```

## 16. 分阶段实施建议

### Phase 1: 数据层重构

- 新建 `entries` 及相关表
- 迁移历史 `note_entries`
- 建立时间范围查询与统计查询

### Phase 2: 规则层增强

- 强化日期解析
- 强化金额与分类解析
- 强化事项与对象识别

### Phase 3: AI 抽取接入

- 定义 `TextUnderstandingEngine`
- 接入 Gemini / 其他模型
- 落 `ai_extractions`

### Phase 4: 时间轴与统计界面

- 时间轴页
- 分类统计页
- 对象档案页

### Phase 5: 智能检索

- 自然语言转结构化查询
- AI 总结结果

### Phase 6: 人工纠错与反馈闭环

- 待确认队列
- 手工修正
- 差异记录

## 17. 最终产品形态建议

IdeaNotes 后续不应只是：

- 手写 + OCR + 查看

而应进化为：

- 手写记录
- OCR 识别
- AI 理解
- 事实入库
- 时间检索
- 分类统计
- 对象档案
- 智能问答

也就是说，产品核心从“记一页笔记”升级为“持续积累一个可回溯、可统计、可追问的个人知识与生活事实库”。

## 18. 推荐的近期落地顺序

如果按工程性与长期价值排序，建议优先做：

1. `entries` 新表与迁移
2. 时间范围查询与统计查询
3. 时间轴页与分类页
4. AI 抽取 JSON Schema 与引擎抽象
5. Gemini 接入与 `ai_extractions` 持久化
6. 人工确认与修正
7. 自然语言查询

---

**结论**:

IdeaNotes 完全适合升级成“按日期组织的结构化事实系统”，而不是停留在 OCR 笔记应用。  
从当前代码基础出发，最正确的演进方向是：**保留 OCR，新增 AI 理解层，重构数据模型，优先建设时间查询与统计能力，再扩展到对象档案与自然语言问答。**
