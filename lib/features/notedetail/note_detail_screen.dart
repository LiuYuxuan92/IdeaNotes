import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/design_system.dart';
import '../../core/models/note.dart';
import '../../core/models/note_entry.dart';
import '../../core/parser/entry_parser.dart';
import '../../core/query/entry_record.dart';
import '../../core/storage/database_helper.dart';
import '../../core/storage/entry_repository.dart';
import '../../core/storage/image_storage.dart';
import '../canvas/canvas_screen.dart';
import '../../shared/widgets/entry_row.dart';
import 'widgets/entry_share_card.dart';

class NoteDetailScreen extends StatefulWidget {
  final Note note;

  const NoteDetailScreen({super.key, required this.note});

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _canvasSectionKey = GlobalKey();
  final GlobalKey _recognizedSectionKey = GlobalKey();
  final GlobalKey _aiSectionKey = GlobalKey();
  final GlobalKey _summarySectionKey = GlobalKey();
  final GlobalKey _entriesSectionKey = GlobalKey();
  late final EntryRepository _entryRepository;
  late Note _currentNote;
  Uint8List? _snapshotBytes;
  late String _recognizedText;
  List<NoteEntry> _entries = const [];
  List<EntryRecord> _structuredEntries = const [];
  AiExtractionAuditSnapshot? _latestAiExtraction;
  bool _isLoading = true;
  bool _isRecognizedExpanded = false;
  bool _showAllPhoneEntries = false;
  bool _isAiExpanded = false;
  bool _isCanvasExpanded = false;

  @override
  void initState() {
    super.initState();
    _entryRepository = EntryRepository(databaseHelper: DatabaseHelper.instance);
    _currentNote = widget.note;
    _recognizedText = _currentNote.recognizedText?.trim() ?? '';
    _loadNoteDetail();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadNoteDetail() async {
    setState(() => _isLoading = true);
    _entries = const [];
    _structuredEntries = const [];
    _latestAiExtraction = null;
    _snapshotBytes = null;

    final latestNote = await DatabaseHelper.instance.getNote(_currentNote.id);
    if (latestNote != null) {
      _currentNote = Note.fromMap(latestNote);
    }
    _recognizedText = _currentNote.recognizedText?.trim() ?? '';

    if (_currentNote.snapshotImagePath != null) {
      _snapshotBytes =
          await ImageStorage.loadSnapshot(_currentNote.snapshotImagePath!);
    }

    if (_recognizedText.isNotEmpty) {
      _structuredEntries =
          await _entryRepository.queryEntriesForNote(_currentNote.id);
      _latestAiExtraction =
          await _entryRepository.getLatestAiExtraction(_currentNote.id);

      // 无结构化条目时直接 fallback 到本地解析；不再回查 legacy note_entries。
      if (_structuredEntries.isEmpty) {
        _entries = EntryParser.parseMultiLine(_recognizedText);
      } else {
        _entries = const [];
      }
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
        _isRecognizedExpanded = false;
        _showAllPhoneEntries = false;
        _isAiExpanded = false;
        _isCanvasExpanded = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final horizontal =
        context.isLarge ? 28.0 : (context.isCompact ? 16.0 : 20.0);

    return Scaffold(
      appBar: AppBar(
        title: Text(_formattedDate(_currentNote.createdAt)),
        actions: [
          IconButton(
            onPressed: _recognizedText.isEmpty ? null : _shareNote,
            tooltip: '分享识别文本',
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1220),
                      child: Padding(
                        padding:
                            EdgeInsets.fromLTRB(horizontal, 12, horizontal, 24),
                        child: context.isLarge
                            ? _buildLargeLayout(context, constraints.maxHeight)
                            : _buildCompactLayout(context),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildLargeLayout(BuildContext context, double maxHeight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeaderCard(context),
        const SizedBox(height: 18),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 10,
                child: SizedBox(
                  height: maxHeight,
                  child: _buildCanvasCard(context, isPinned: true),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                flex: 9,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildRecognizedCard(context),
                      const SizedBox(height: 18),
                      _buildAiCard(context),
                      const SizedBox(height: 18),
                      _buildStructuredSummaryCard(context),
                      const SizedBox(height: 18),
                      _buildEntriesCard(context),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompactLayout(BuildContext context) {
    if (context.isCompact) {
      return _buildPhoneLayout(context);
    }

    final sections = <Widget>[
      _buildHeaderCard(context),
      const SizedBox(height: 18),
      KeyedSubtree(
        key: _recognizedSectionKey,
        child: _buildRecognizedCard(context),
      ),
      const SizedBox(height: 18),
      _buildSectionNavigator(context),
      const SizedBox(height: 18),
      KeyedSubtree(
        key: _summarySectionKey,
        child: _buildStructuredSummaryCard(context),
      ),
      const SizedBox(height: 18),
      KeyedSubtree(
        key: _entriesSectionKey,
        child: _buildEntriesCard(context),
      ),
      const SizedBox(height: 18),
      KeyedSubtree(
        key: _aiSectionKey,
        child: _buildAiCard(context),
      ),
    ];

    if (_hasSnapshot) {
      sections.addAll([
        const SizedBox(height: 18),
        KeyedSubtree(
          key: _canvasSectionKey,
          child: _buildCanvasCard(context),
        ),
      ]);
    }

    return SingleChildScrollView(
      controller: _scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: sections,
      ),
    );
  }

  Widget _buildPhoneLayout(BuildContext context) {
    final sections = <Widget>[
      _buildPhoneOverviewCard(context),
      const SizedBox(height: 12),
      KeyedSubtree(
        key: _recognizedSectionKey,
        child: _buildPhoneRecognizedCard(context),
      ),
      const SizedBox(height: 12),
      KeyedSubtree(
        key: _summarySectionKey,
        child: _buildPhoneSummaryCard(context),
      ),
      const SizedBox(height: 12),
      KeyedSubtree(
        key: _entriesSectionKey,
        child: _buildPhoneEntriesCard(context),
      ),
      const SizedBox(height: 12),
      KeyedSubtree(
        key: _aiSectionKey,
        child: _buildPhoneAiCard(context),
      ),
    ];

    if (_hasSnapshot) {
      sections.addAll([
        const SizedBox(height: 12),
        KeyedSubtree(
          key: _canvasSectionKey,
          child: _buildPhoneCanvasCard(context),
        ),
      ]);
    }

    return SingleChildScrollView(
      controller: _scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: sections,
      ),
    );
  }

  Widget _buildPhoneOverviewCard(BuildContext context) {
    final previewLine = _recognizedText.isEmpty
        ? '先回到手写页做一次识别，再回来核对结果。'
        : _recognizedText.split('\n').first.trim();
    final statusColor =
        _recognizedText.isEmpty ? AppColors.warning : AppColors.success;
    final statusLabel = _recognizedText.isEmpty ? '待识别' : '已识别';

    return AppSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '笔记详情',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: AppColors.textMuted,
                            letterSpacing: 1.2,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      previewLine,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metaPill(
                context,
                Icons.schedule_rounded,
                _timeText(_currentNote.updatedAt),
              ),
              _metaPill(
                context,
                Icons.checklist_rounded,
                _recognizedText.isEmpty ? '0 条结果' : '$_displayedEntryCount 条结果',
              ),
              if (_hasAiStructuredData)
                _metaPill(
                  context,
                  Icons.auto_awesome_rounded,
                  'AI已整理',
                ),
              if (_hasSnapshot)
                _metaPill(
                  context,
                  Icons.draw_rounded,
                  '有手写原稿',
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openCanvasEditor,
                  icon: const Icon(Icons.edit_note_rounded),
                  label: Text(_recognizedText.isEmpty ? '去识别' : '继续编辑'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _recognizedText.isEmpty ? null : _shareNote,
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('分享文本'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneRecognizedCard(BuildContext context) {
    final canExpand =
        _recognizedText.length > 140 || _recognizedText.split('\n').length > 5;

    return AppSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCompactSectionHeader(
            context,
            icon: Icons.text_snippet_outlined,
            title: '识别文本',
            subtitle:
                _recognizedText.isEmpty ? '还没有识别结果' : '默认只展示前几行，避免手机上一整块铺满',
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFB),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: _recognizedText.isEmpty
                ? Text(
                    '这页目前还是原始手写内容。回到画布后点一下“识别”，系统会把文本整理到这里。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.55,
                        ),
                  )
                : _isRecognizedExpanded
                    ? SelectableText(
                        _recognizedText,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              height: 1.6,
                            ),
                      )
                    : Text(
                        _recognizedText,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              height: 1.6,
                            ),
                      ),
          ),
          if (canExpand) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _isRecognizedExpanded = !_isRecognizedExpanded;
                });
              },
              icon: Icon(
                _isRecognizedExpanded
                    ? Icons.unfold_less_rounded
                    : Icons.unfold_more_rounded,
              ),
              label: Text(_isRecognizedExpanded ? '收起全文' : '展开全文'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhoneSummaryCard(BuildContext context) {
    final expenseCount = _expenseCount;
    final eventCount = _eventCount;
    final healthCount = _healthCount;
    final memoCount = _memoCount;

    final summaryText = _displayedEntryCount == 0
        ? '当前只保留 OCR 文本。识别更完整后，会继续归纳成花费、待办、健康、记录 4 类。'
        : '本页共 $_displayedEntryCount 条结果；同一条可同时带多个标签，例如饮食会同时算健康和记录。';

    return AppSurface(
      padding: const EdgeInsets.all(16),
      backgroundColor: const Color(0xFFF8FAFB),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCompactSectionHeader(
            context,
            icon: Icons.insights_outlined,
            title: '结构化概览',
            subtitle: summaryText,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _summaryChip(
                context,
                icon: Icons.attach_money_rounded,
                label: '$expenseCount 条花费',
                accent: AppColors.warning,
              ),
              _summaryChip(
                context,
                icon: Icons.event_note_rounded,
                label: '$eventCount 条待办',
                accent: AppColors.inkBlue,
              ),
              _summaryChip(
                context,
                icon: Icons.health_and_safety_outlined,
                label: '$healthCount 条健康',
                accent: AppColors.success,
              ),
              _summaryChip(
                context,
                icon: Icons.sticky_note_2_outlined,
                label: '$memoCount 条记录',
                accent: AppColors.slateBlue,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneEntriesCard(BuildContext context) {
    final allEntryWidgets = _buildDisplayedEntryWidgets();
    final hasMoreEntries = allEntryWidgets.length > 4;
    final visibleEntryWidgets = hasMoreEntries && !_showAllPhoneEntries
        ? allEntryWidgets.take(4).toList(growable: false)
        : allEntryWidgets;

    return AppSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCompactSectionHeader(
            context,
            icon: Icons.checklist_rounded,
            title: '解析结果',
            subtitle: _displayedEntryCount == 0
                ? '暂时没有可展示的解析条目'
                : '默认先看前 4 条，避免详情页在手机上拉得过长',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _displayedEntryCount == 0
                    ? const Color(0xFFF3E8D0)
                    : const Color(0xFFDDEEE6),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$_displayedEntryCount 条',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _displayedEntryCount == 0
                          ? AppColors.warning
                          : AppColors.success,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_displayedEntryCount == 0)
            const EmptyStateView(
              icon: Icons.layers_clear_outlined,
              title: '暂时没有解析结果',
              description: '这不影响保存和查看。等文本更完整后，再识别一次会更容易提取结构。',
            )
          else ...[
            ...visibleEntryWidgets,
            if (hasMoreEntries) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _showAllPhoneEntries = !_showAllPhoneEntries;
                  });
                },
                icon: Icon(
                  _showAllPhoneEntries
                      ? Icons.unfold_less_rounded
                      : Icons.unfold_more_rounded,
                ),
                label: Text(
                  _showAllPhoneEntries
                      ? '收起多余条目'
                      : '展开剩余 ${allEntryWidgets.length - 4} 条',
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildPhoneAiCard(BuildContext context) {
    final audit = _latestAiExtraction;
    final aiCount = _structuredEntries
        .where((entry) => entry.sourceEngine != 'rule-parser')
        .length;
    final hasAiResult = audit != null || aiCount > 0;
    final statusLabel = audit == null
        ? '待生成'
        : audit.status == 'success'
            ? '已完成'
            : '失败';
    final statusColor = audit == null
        ? AppColors.warning
        : audit.status == 'success'
            ? AppColors.success
            : AppColors.error;

    return _buildCompactExpandableCard(
      context,
      icon: Icons.auto_awesome_rounded,
      title: 'AI整理',
      subtitle: _recognizedText.isEmpty
          ? '先识别出文本，AI 才能继续整理'
          : hasAiResult
              ? '已有整理结果，默认折叠，避免详情页继续拉长'
              : '当前还没有 AI 整理记录',
      accent: AppColors.aiAccent,
      expanded: _isAiExpanded,
      onToggle: () {
        setState(() {
          _isAiExpanded = !_isAiExpanded;
        });
      },
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          statusLabel,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
      backgroundColor:
          _recognizedText.isEmpty ? Colors.white : AppColors.aiAccentSoft,
      border: BorderSide(
        color: _recognizedText.isEmpty
            ? Theme.of(context).colorScheme.outlineVariant
            : AppColors.aiAccent.withValues(alpha: 0.18),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _summaryChip(
                context,
                icon: Icons.auto_awesome_rounded,
                label: audit == null
                    ? '未记录模型'
                    : '${audit.engineName} · ${audit.engineModel}',
                accent: AppColors.aiAccent,
              ),
              _summaryChip(
                context,
                icon: Icons.fact_check_outlined,
                label: '$aiCount 条 AI 结果',
                accent: AppColors.success,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._aiBullets().map(
            (bullet) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                bullet,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneCanvasCard(BuildContext context) {
    return _buildCompactExpandableCard(
      context,
      icon: Icons.draw_rounded,
      title: '手写原稿',
      subtitle: _isCanvasExpanded ? '可直接核对字迹和布局' : '默认折叠，避免原稿预览在手机上占太高',
      expanded: _isCanvasExpanded,
      onToggle: () {
        setState(() {
          _isCanvasExpanded = !_isCanvasExpanded;
        });
      },
      trailing: IconButton(
        onPressed: _openCanvasEditor,
        tooltip: '继续编辑',
        icon: const Icon(Icons.edit_note_rounded),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            height: 200,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F5F1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: _snapshotBytes == null
                ? Center(
                    child: Text(
                      '当前没有可显示的画布快照。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: Image.memory(
                        _snapshotBytes!,
                        fit: BoxFit.contain,
                        width: double.infinity,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _openCanvasEditor,
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('继续编辑手写页'),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactSectionHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    Color accent = AppColors.textSecondary,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.45,
                    ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing,
        ],
      ],
    );
  }

  Widget _buildCompactExpandableCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool expanded,
    required VoidCallback onToggle,
    required Widget body,
    Widget? trailing,
    Color accent = AppColors.textSecondary,
    Color? backgroundColor,
    BorderSide? border,
  }) {
    return AppSurface(
      padding: const EdgeInsets.all(16),
      backgroundColor: backgroundColor,
      border: border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildCompactSectionHeader(
                      context,
                      icon: icon,
                      title: title,
                      subtitle: subtitle,
                      accent: accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (trailing != null) trailing,
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 12),
            body,
          ],
        ],
      ),
    );
  }

  List<Widget> _buildDisplayedEntryWidgets() {
    if (_structuredEntries.isNotEmpty) {
      return _structuredEntries
          .map((entry) => _StructuredEntryRow(entry: entry))
          .toList(growable: false);
    }
    return _entries
        .map((entry) => EntryRow(entry: entry))
        .toList(growable: false);
  }

  Widget _buildHeaderCard(BuildContext context) {
    return AppSurface(
      child: AppSectionHeader(
        eyebrow: '笔记详情',
        title: _recognizedText.isEmpty ? '这页内容还没识别' : '这页手写内容已经整理为可阅读文本',
        description: _recognizedText.isEmpty
            ? '你可以回到画布继续补写，或重新识别一次，让内容更容易搜索和整理。'
            : '左侧保留手写现场，右侧用于核对识别文本与解析结果，方便你确认这一页的实际内容。',
        trailing: _buildMeta(context),
      ),
    );
  }

  Widget _buildMeta(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.end,
      children: [
        _metaPill(
          context,
          Icons.schedule_rounded,
          '更新于 ${_timeText(_currentNote.updatedAt)}',
        ),
        _metaPill(
          context,
          Icons.text_snippet_outlined,
          _recognizedText.isEmpty ? '待识别' : '$_displayedEntryCount 条解析结果',
        ),
        if (_hasAiStructuredData)
          _metaPill(context, Icons.auto_awesome_rounded, 'AI已整理'),
        if (_latestAiExtraction != null)
          _metaPill(
            context,
            Icons.memory_rounded,
            _latestAiExtraction!.engineModel,
          ),
      ],
    );
  }

  Widget _metaPill(BuildContext context, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _buildSectionNavigator(BuildContext context) {
    return AppSurface(
      isFlat: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      backgroundColor: Colors.white.withValues(alpha: 0.78),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _SectionJumpChip(
            icon: Icons.notes_rounded,
            label: 'OCR 文本',
            onTap: () => _scrollToSection(_recognizedSectionKey),
          ),
          _SectionJumpChip(
            icon: Icons.auto_awesome_rounded,
            label: 'AI整理',
            accent: AppColors.aiAccent,
            onTap: () => _scrollToSection(_aiSectionKey),
          ),
          _SectionJumpChip(
            icon: Icons.insights_outlined,
            label: '结构化概览',
            onTap: () => _scrollToSection(_summarySectionKey),
          ),
          _SectionJumpChip(
            icon: Icons.checklist_rounded,
            label: '解析结果',
            accent: AppColors.inkBlue,
            onTap: () => _scrollToSection(_entriesSectionKey),
          ),
          if (_hasSnapshot)
            _SectionJumpChip(
              icon: Icons.draw_rounded,
              label: '手写原稿',
              onTap: () => _scrollToSection(_canvasSectionKey),
            ),
        ],
      ),
    );
  }

  Widget _buildCanvasCard(BuildContext context, {bool isPinned = false}) {
    final preview = Container(
      width: double.infinity,
      constraints: BoxConstraints(
        minHeight: isPinned ? 240 : (_hasSnapshot ? 160 : 112),
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F5F1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: _snapshotBytes != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.memory(
                  _snapshotBytes!,
                  fit: BoxFit.contain,
                  width: double.infinity,
                ),
              ),
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '当前没有可显示的画布快照。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ),
            ),
    );

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            eyebrow: '原始画布',
            title: isPinned ? '左侧固定保留你的手写现场' : '保留你的手写现场',
            description: '这里保留了原始书写状态，方便你核对字迹、布局和上下文。',
          ),
          const SizedBox(height: 16),
          if (isPinned) Expanded(child: preview) else preview,
        ],
      ),
    );
  }

  Widget _buildRecognizedCard(BuildContext context) {
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            eyebrow: '识别文本',
            title: _recognizedText.isEmpty ? '还没有识别结果' : '先通读一遍识别文本',
            description: _recognizedText.isEmpty
                ? '如果这页需要搜索、复制或分享，请回到画布触发一次识别。'
                : '如果发现错字或漏字，建议先回到画布补充书写，再重新识别一次。',
            trailing: Wrap(
              spacing: 4,
              children: [
                IconButton(
                  onPressed: _openCanvasEditor,
                  tooltip: '继续编辑',
                  icon: const Icon(Icons.edit_note_rounded),
                ),
                IconButton(
                  onPressed: _recognizedText.isEmpty ? null : _shareNote,
                  tooltip: '分享识别文本',
                  icon: const Icon(Icons.ios_share_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            constraints: BoxConstraints(
              minHeight: context.isCompact ? 180 : 240,
            ),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFB),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: _recognizedText.isEmpty
                ? Text(
                    '这页目前还是原始手写内容。回到画布后点一下“识别”，系统会把文本整理到这里。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  )
                : SelectableText(
                    _recognizedText,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          height: 1.68,
                        ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiCard(BuildContext context) {
    final audit = _latestAiExtraction;

    if (_recognizedText.isEmpty) {
      return const AppSurface(
        backgroundColor: AppColors.aiAccentSoft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSectionHeader(
              eyebrow: 'AI整理',
              title: '先识别出文本，AI 才能继续整理',
              description: '这一步会在识别文本存在后才触发，用来补全分类、时间和结构化字段。',
            ),
          ],
        ),
      );
    }

    final aiCount = _structuredEntries
        .where((entry) => entry.sourceEngine != 'rule-parser')
        .length;
    final hasAiResult = audit != null || aiCount > 0;
    final statusLabel = audit == null
        ? '待生成'
        : audit.status == 'success'
            ? '已完成'
            : '失败';
    final statusColor = audit == null
        ? AppColors.warning
        : audit.status == 'success'
            ? AppColors.success
            : AppColors.error;

    return AppSurface(
      backgroundColor: AppColors.aiAccentSoft,
      border: BorderSide(color: AppColors.aiAccent.withValues(alpha: 0.18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            eyebrow: 'AI整理',
            title: hasAiResult ? '这页已经做过 AI 整理' : '这页还没有 AI 整理记录',
            description: hasAiResult
                ? '这里显示本页最近一次 AI 整理的模型、状态和落库结果，便于确认这次整理是否真的生效。'
                : '当前还没看到 AI 审计记录。通常在保存含 OCR 文本的笔记后，这里就会出现模型和整理状态。',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                statusLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _summaryChip(
                context,
                icon: Icons.auto_awesome_rounded,
                label: audit == null
                    ? '未记录模型'
                    : '${audit.engineName} · ${audit.engineModel}',
                accent: AppColors.aiAccent,
              ),
              _summaryChip(
                context,
                icon: Icons.fact_check_outlined,
                label: '$aiCount 条 AI 结果',
                accent: AppColors.success,
              ),
              if (audit != null)
                _summaryChip(
                  context,
                  icon: Icons.schedule_rounded,
                  label: _timeText(audit.createdAt),
                  accent: AppColors.inkBlue,
                ),
            ],
          ),
          const SizedBox(height: 16),
          ..._aiBullets().map(
            (bullet) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(
                      Icons.subdirectory_arrow_right_rounded,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      bullet,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStructuredSummaryCard(BuildContext context) {
    final expenseCount = _expenseCount;
    final eventCount = _eventCount;
    final healthCount = _healthCount;
    final memoCount = _memoCount;

    final bullets = _displayedEntryCount == 0
        ? const [
            '当前页已保留手写原稿与 OCR 文本',
            '识别更完整后，这里会统计本页的花费、待办、健康和记录',
            '这些结构化结果会直接进入后续查询页继续使用',
          ]
        : _entrySummaryBullets();

    return AppSurface(
      backgroundColor: const Color(0xFFF8FAFB),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            eyebrow: '结构化概览',
            title:
                _displayedEntryCount == 0 ? '这页还没有提取出结构化条目' : '这页已经提取出可复用的信息',
            description: _recognizedText.isEmpty
                ? '先识别出文本后，系统才能继续拆出花费、待办、健康和记录。'
                : _structuredEntries.isNotEmpty
                    ? '这里展示的是结构化 entries 表里的结果，优先反映 AI 与规则合并后的最终落库内容。'
                    : '当前还在展示兼容旧版本的解析结果；重新保存后会切换成新的结构化结果。',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _displayedEntryCount == 0
                    ? const Color(0xFFF3E8D0)
                    : const Color(0xFFDDEEE6),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _displayedEntryCount == 0 ? '等待识别' : '已提取',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _displayedEntryCount == 0
                          ? AppColors.warning
                          : AppColors.success,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _summaryChip(
                context,
                icon: Icons.attach_money_rounded,
                label: '$expenseCount 条花费',
                accent: AppColors.warning,
              ),
              _summaryChip(
                context,
                icon: Icons.event_note_rounded,
                label: '$eventCount 条待办',
                accent: AppColors.inkBlue,
              ),
              _summaryChip(
                context,
                icon: Icons.health_and_safety_outlined,
                label: '$healthCount 条健康',
                accent: AppColors.success,
              ),
              _summaryChip(
                context,
                icon: Icons.sticky_note_2_outlined,
                label: '$memoCount 条记录',
                accent: AppColors.slateBlue,
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...bullets.map(
            (bullet) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(
                      Icons.subdirectory_arrow_right_rounded,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      bullet,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntriesCard(BuildContext context) {
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            eyebrow: '解析结果',
            title: '系统已帮你拆出重点信息',
            description: _structuredEntries.isNotEmpty
                ? '下面展示的是结构化查询表中的最终条目，后续搜索、时间线和分类统计都直接使用这些数据。'
                : '当前展示的是兼容旧版本的解析结果；重新保存后会使用结构化条目视图。',
          ),
          const SizedBox(height: 16),
          if (_displayedEntryCount == 0)
            const EmptyStateView(
              icon: Icons.layers_clear_outlined,
              title: '暂时没有解析结果',
              description: '这不影响保存和查看。等文本更完整后，再识别一次会更容易提取结构。',
            )
          else if (_structuredEntries.isNotEmpty)
            ..._structuredEntries
                .map((entry) => _StructuredEntryRow(entry: entry))
          else
            ..._entries.map((entry) => EntryRow(entry: entry)),
        ],
      ),
    );
  }

  List<String> _entrySummaryBullets() {
    final expenseCount = _expenseCount;
    final eventCount = _eventCount;
    final healthCount = _healthCount;
    final memoCount = _memoCount;

    return [
      '当前共识别出 $_displayedEntryCount 条结构化线索',
      '按标签维度看，包含 $expenseCount 条花费、$eventCount 条待办、$healthCount 条健康、$memoCount 条记录；同一条可以重复计入多个标签',
      _structuredEntries.isNotEmpty
          ? '这些结果已经进入结构化查询表，后面在查询页里会直接按这些条目继续筛选和统计'
          : '这些结果会和 OCR 文本一起保存，后面在查询页里可直接按分类或时间线继续看',
    ];
  }

  List<String> _aiBullets() {
    final audit = _latestAiExtraction;
    if (audit == null && !_hasAiStructuredData) {
      return const [
        '当前还没拿到 AI 审计记录，所以前台还不能确认这页是否真正跑过模型。',
        '如果你刚识别完但还没保存，这里还是空的；保存带 OCR 文本的笔记后才会写入记录。',
        '一旦成功，这里会显示模型、状态和写入结构化表的结果数量。',
      ];
    }

    return [
      if (audit != null) '最近一次整理状态：${audit.status}，模型是 ${audit.engineModel}',
      if (_hasAiStructuredData)
        '当前有 $_displayedEntryCount 条结构化结果，其中 $_aiStructuredCount 条带 AI 来源',
      if (audit != null)
        '整理时间：${_formattedDate(audit.createdAt)} ${_timeText(audit.createdAt)}',
    ];
  }

  int get _displayedEntryCount => _structuredEntries.isNotEmpty
      ? _structuredEntries.length
      : _entries.length;

  bool get _hasAiStructuredData => _aiStructuredCount > 0;

  int get _aiStructuredCount => _structuredEntries
      .where((entry) => entry.sourceEngine != 'rule-parser')
      .length;

  int get _expenseCount {
    if (_structuredEntries.isNotEmpty) {
      return _structuredEntries
          .where((entry) =>
              entry.domain == 'finance' ||
              const {'expense', 'income', 'purchase'}.contains(entry.entryType))
          .length;
    }
    return _entries
        .where((entry) => entry.type == NoteEntryType.expense)
        .length;
  }

  int get _eventCount {
    if (_structuredEntries.isNotEmpty) {
      return _structuredEntries
          .where((entry) =>
              const {'task', 'appointment'}.contains(entry.entryType))
          .length;
    }
    return _entries.where((entry) => entry.type == NoteEntryType.event).length;
  }

  int get _healthCount {
    if (_structuredEntries.isNotEmpty) {
      return _structuredEntries
          .where((entry) =>
              entry.domain == 'health' ||
              entry.tags.contains('健康') ||
              const {
                'health_record',
                'vaccination',
                'medication',
                'metric',
              }.contains(entry.entryType))
          .length;
    }
    return _entries.where((entry) => entry.type == NoteEntryType.health).length;
  }

  int get _memoCount {
    if (_structuredEntries.isNotEmpty) {
      return _structuredEntries
          .where(
            (entry) => entry.entryType == 'memo' || entry.tags.contains('记录'),
          )
          .length;
    }
    return _entries.where((entry) => entry.type == NoteEntryType.memo).length;
  }

  String _formattedDate(DateTime date) =>
      '${date.year}年${date.month}月${date.day}日';

  String _timeText(DateTime date) =>
      '${date.month}月${date.day}日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  void _shareNote() {
    if (_recognizedText.isEmpty) return;
    Share.share(_recognizedText, subject: 'IdeaNotes 笔记');
  }

  Future<void> _openCanvasEditor() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => CanvasScreen(noteId: _currentNote.id),
      ),
    );
    if (!mounted) return;
    await _loadNoteDetail();
  }

  bool get _hasSnapshot => _snapshotBytes != null;

  Widget _summaryChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  void _scrollToSection(GlobalKey key) {
    final targetContext = key.currentContext;
    if (targetContext == null) return;
    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: 0.04,
    );
  }
}

class _SectionJumpChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const _SectionJumpChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = AppColors.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: accent == AppColors.aiAccent
              ? AppColors.aiAccentSoft
              : const Color(0xFFF2F5F6),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: accent),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StructuredEntryRow extends StatelessWidget {
  final EntryRecord entry;

  const _StructuredEntryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _palette;
    final metadata = <String>[
      _entryTypeLabel(entry),
      if (_timeLabel != null) _timeLabel!,
      if (entry.categoryL1?.trim().isNotEmpty == true) entry.categoryL1!.trim(),
      if (entry.categoryL2?.trim().isNotEmpty == true) entry.categoryL2!.trim(),
      if (_statusLabel != null) _statusLabel!,
    ];
    final classificationTags = _classificationTags;

    return AppSurface(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      backgroundColor: palette.background,
      border: BorderSide(color: palette.border),
      boxShadow: const [],
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: palette.pill,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(palette.icon, color: palette.accent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        entry.title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (_amountLabel != null) ...[
                      const SizedBox(width: 12),
                      Text(
                        _amountLabel!,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AppColors.inkBlue,
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () =>
                          EntryShareCardExporter().shareEntry(context, entry),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(
                          Icons.ios_share_rounded,
                          size: 18,
                          color: AppColors.textSecondary,
                          semanticLabel: '分享这条记录',
                        ),
                      ),
                    ),
                  ],
                ),
                if (metadata.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    metadata.join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  _descriptionText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (classificationTags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: classificationTags
                        .map(
                          (tag) => _InfoChip(
                            icon: Icons.sell_outlined,
                            label: tag,
                            accent: _tagAccent(tag),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip(
                      icon: Icons.account_tree_outlined,
                      label: _sourceLabel(entry.sourceEngine),
                      accent: _sourceAccent(entry.sourceEngine),
                    ),
                    _InfoChip(
                      icon: Icons.folder_open_outlined,
                      label: entry.domain,
                      accent: AppColors.textSecondary,
                    ),
                    if (entry.confidence != null)
                      _InfoChip(
                        icon: Icons.tune_rounded,
                        label:
                            '置信 ${(entry.confidence! * 100).clamp(0, 100).toStringAsFixed(0)}%',
                        accent: AppColors.slateBlue,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _descriptionText {
    final summary = entry.summary?.trim();
    if (summary != null && summary.isNotEmpty) {
      return summary;
    }
    return entry.rawText;
  }

  String? get _amountLabel {
    final amount = entry.amountValue;
    if (amount == null) {
      return null;
    }
    if ((entry.amountCurrency ?? 'CNY') == 'CNY') {
      return '¥$amount';
    }
    return '${entry.amountCurrency} $amount';
  }

  String? get _timeLabel {
    final occurredAt = entry.occurredAt;
    if (occurredAt == null) {
      return '${entry.occurredDate.month}月${entry.occurredDate.day}日';
    }
    final hasClock = occurredAt.hour != 0 || occurredAt.minute != 0;
    final dateLabel = '${occurredAt.month}月${occurredAt.day}日';
    if (!hasClock) {
      return dateLabel;
    }
    final timeLabel =
        '${occurredAt.hour.toString().padLeft(2, '0')}:${occurredAt.minute.toString().padLeft(2, '0')}';
    return '$dateLabel $timeLabel';
  }

  String? get _statusLabel {
    switch (entry.status) {
      case 'done':
        return '已完成';
      case 'pending':
        return '待处理';
      case 'recorded':
      case null:
      case '':
        return null;
      default:
        return entry.status;
    }
  }

  List<String> get _classificationTags {
    final tags = <String>[];
    for (final tag in entry.tags) {
      final normalized = tag.trim();
      if (normalized.isEmpty) {
        continue;
      }
      if (!tags.contains(normalized)) {
        tags.add(normalized);
      }
    }
    return tags;
  }

  _EntryPalette get _palette {
    switch (entry.entryType) {
      case 'expense':
      case 'purchase':
      case 'income':
        return const _EntryPalette(
          background: Color(0xFFFAF6EE),
          border: Color(0xFFEADFC7),
          pill: Color(0xFFF3E8D0),
          accent: AppColors.warning,
          icon: Icons.payments_outlined,
        );
      case 'task':
      case 'appointment':
        return _EntryPalette(
          background: entry.domain == 'health'
              ? const Color(0xFFF1F7F3)
              : const Color(0xFFF1F5F7),
          border: entry.domain == 'health'
              ? const Color(0xFFD6E8DD)
              : const Color(0xFFD9E4EA),
          pill: entry.domain == 'health'
              ? const Color(0xFFDCEFE4)
              : const Color(0xFFDDE8EE),
          accent:
              entry.domain == 'health' ? AppColors.success : AppColors.inkBlue,
          icon: entry.domain == 'health'
              ? Icons.health_and_safety_outlined
              : Icons.event_note_rounded,
        );
      case 'vaccination':
        return const _EntryPalette(
          background: Color(0xFFF1F7F3),
          border: Color(0xFFD6E8DD),
          pill: Color(0xFFDCEFE4),
          accent: AppColors.success,
          icon: Icons.vaccines_rounded,
        );
      case 'medication':
        return const _EntryPalette(
          background: Color(0xFFF1F7F3),
          border: Color(0xFFD6E8DD),
          pill: Color(0xFFDCEFE4),
          accent: AppColors.success,
          icon: Icons.medication_outlined,
        );
      case 'health_record':
      case 'metric':
        return const _EntryPalette(
          background: Color(0xFFF1F7F3),
          border: Color(0xFFD6E8DD),
          pill: Color(0xFFDCEFE4),
          accent: AppColors.success,
          icon: Icons.favorite_border_rounded,
        );
      default:
        return const _EntryPalette(
          background: Color(0xFFF5F7F8),
          border: Color(0xFFDDE3E8),
          pill: Color(0xFFE4EAEE),
          accent: AppColors.slateBlue,
          icon: Icons.sticky_note_2_outlined,
        );
    }
  }

  static String _entryTypeLabel(EntryRecord entry) {
    if (entry.entryType == 'task' && entry.domain == 'health') {
      return '健康待办';
    }

    switch (entry.entryType) {
      case 'expense':
        return '花费';
      case 'income':
        return '收入';
      case 'purchase':
        return '消费';
      case 'task':
        return '待办';
      case 'appointment':
        return '预约';
      case 'vaccination':
        return '疫苗';
      case 'medication':
        return '用药';
      case 'health_record':
        return '健康记录';
      case 'metric':
        return '健康指标';
      case 'travel':
        return '出行';
      case 'document':
        return '资料';
      case 'memo':
        return '记录';
      default:
        return entry.entryType;
    }
  }

  static String _sourceLabel(String sourceEngine) {
    switch (sourceEngine) {
      case 'rule+ai':
        return '规则 + AI';
      case 'ai':
        return 'AI整理';
      case 'rule-parser':
        return '规则解析';
      default:
        return sourceEngine;
    }
  }

  static Color _sourceAccent(String sourceEngine) {
    switch (sourceEngine) {
      case 'rule+ai':
      case 'ai':
        return AppColors.aiAccent;
      case 'rule-parser':
      default:
        return AppColors.inkBlue;
    }
  }

  static Color _tagAccent(String tag) {
    switch (tag) {
      case '记录':
        return AppColors.slateBlue;
      case '健康':
      case '饮食':
      case '疫苗':
      case '用药':
      case '排便':
        return AppColors.success;
      case '宝宝':
        return AppColors.inkBlue;
      default:
        return AppColors.textSecondary;
    }
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _EntryPalette {
  final Color background;
  final Color border;
  final Color pill;
  final Color accent;
  final IconData icon;

  const _EntryPalette({
    required this.background,
    required this.border,
    required this.pill,
    required this.accent,
    required this.icon,
  });
}
