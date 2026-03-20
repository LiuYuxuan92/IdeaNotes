import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/design_system.dart';
import '../../core/models/note.dart';
import '../../core/models/note_entry.dart';
import '../../core/parser/entry_parser.dart';
import '../../core/storage/database_helper.dart';
import '../../core/storage/image_storage.dart';
import '../../shared/widgets/entry_row.dart';

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
  final GlobalKey _summarySectionKey = GlobalKey();
  final GlobalKey _entriesSectionKey = GlobalKey();
  Uint8List? _snapshotBytes;
  late String _recognizedText;
  List<NoteEntry> _entries = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _recognizedText = widget.note.recognizedText?.trim() ?? '';
    _loadNoteDetail();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadNoteDetail() async {
    setState(() => _isLoading = true);
    if (widget.note.snapshotImagePath != null) {
      _snapshotBytes =
          await ImageStorage.loadSnapshot(widget.note.snapshotImagePath!);
    }

    if (_recognizedText.isNotEmpty) {
      try {
        final entryMaps =
            await DatabaseHelper.instance.getNoteEntries(widget.note.id);
        if (entryMaps.isNotEmpty) {
          _entries = entryMaps.map(NoteEntry.fromMap).toList();
        } else {
          _entries = EntryParser.parseMultiLine(_recognizedText);
        }
      } catch (_) {
        _entries = EntryParser.parseMultiLine(_recognizedText);
      }
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final horizontal =
        context.isLarge ? 28.0 : (context.isCompact ? 16.0 : 20.0);

    return Scaffold(
      appBar: AppBar(
        title: Text(_formattedDate(widget.note.createdAt)),
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
    return SingleChildScrollView(
      controller: _scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderCard(context),
          const SizedBox(height: 18),
          _buildSectionNavigator(context),
          const SizedBox(height: 18),
          KeyedSubtree(
            key: _canvasSectionKey,
            child: _buildCanvasCard(context),
          ),
          const SizedBox(height: 18),
          KeyedSubtree(
            key: _recognizedSectionKey,
            child: _buildRecognizedCard(context),
          ),
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
        ],
      ),
    );
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
          '更新于 ${_timeText(widget.note.updatedAt)}',
        ),
        _metaPill(
          context,
          Icons.text_snippet_outlined,
          _recognizedText.isEmpty ? '待识别' : '${_entries.length} 条解析结果',
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
            icon: Icons.draw_rounded,
            label: '手写原稿',
            onTap: () => _scrollToSection(_canvasSectionKey),
          ),
          _SectionJumpChip(
            icon: Icons.notes_rounded,
            label: 'OCR 文本',
            onTap: () => _scrollToSection(_recognizedSectionKey),
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
        ],
      ),
    );
  }

  Widget _buildCanvasCard(BuildContext context, {bool isPinned = false}) {
    final preview = Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 240),
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
            trailing: IconButton(
              onPressed: _recognizedText.isEmpty ? null : _shareNote,
              tooltip: '分享识别文本',
              icon: const Icon(Icons.ios_share_rounded),
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

  Widget _buildStructuredSummaryCard(BuildContext context) {
    final expenseCount =
        _entries.where((entry) => entry.type == NoteEntryType.expense).length;
    final eventCount =
        _entries.where((entry) => entry.type == NoteEntryType.event).length;
    final healthCount =
        _entries.where((entry) => entry.type == NoteEntryType.health).length;
    final memoCount =
        _entries.where((entry) => entry.type == NoteEntryType.memo).length;

    final bullets = _entries.isEmpty
        ? const [
            '当前页已保留手写原稿与 OCR 文本',
            '识别更完整后，这里会统计本页的花费、事项、健康和备忘',
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
            title: _entries.isEmpty ? '这页还没有提取出结构化条目' : '这页已经提取出可复用的信息',
            description: _recognizedText.isEmpty
                ? '先识别出文本后，系统才能继续拆出花费、事项、健康和备忘。'
                : '这里展示的是当前页已经落库的结构化结果，不是占位说明。',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _entries.isEmpty
                    ? const Color(0xFFF3E8D0)
                    : const Color(0xFFDDEEE6),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _entries.isEmpty ? '等待识别' : '已提取',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _entries.isEmpty
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
                label: '$eventCount 条事项',
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
                label: '$memoCount 条备忘',
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
          const AppSectionHeader(
            eyebrow: '解析结果',
            title: '系统已帮你拆出重点信息',
            description: '系统会先按当前识别文本拆出花费、事项、健康和备忘，方便你核对这一页的重点。',
          ),
          const SizedBox(height: 16),
          if (_entries.isEmpty)
            const EmptyStateView(
              icon: Icons.layers_clear_outlined,
              title: '暂时没有解析结果',
              description: '这不影响保存和查看。等文本更完整后，再识别一次会更容易提取结构。',
            )
          else
            ..._entries.map((entry) => EntryRow(entry: entry)),
        ],
      ),
    );
  }

  List<String> _entrySummaryBullets() {
    final expenseCount =
        _entries.where((entry) => entry.type == NoteEntryType.expense).length;
    final eventCount =
        _entries.where((entry) => entry.type == NoteEntryType.event).length;
    final healthCount =
        _entries.where((entry) => entry.type == NoteEntryType.health).length;
    final memoCount =
        _entries.where((entry) => entry.type == NoteEntryType.memo).length;

    return [
      '当前共识别出 ${_entries.length} 条结构化线索',
      '其中包含 $expenseCount 条花费、$eventCount 条事项、$healthCount 条健康、$memoCount 条备忘',
      '这些结果会和 OCR 文本一起保存，后面在查询页里可直接按分类或时间线继续看',
    ];
  }

  String _formattedDate(DateTime date) =>
      '${date.year}年${date.month}月${date.day}日';

  String _timeText(DateTime date) =>
      '${date.month}月${date.day}日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  void _shareNote() {
    if (_recognizedText.isEmpty) return;
    Share.share(_recognizedText, subject: 'IdeaNotes 笔记');
  }

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
