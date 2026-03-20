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
    final horizontal = context.isLarge ? 28.0 : 20.0;

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
                      _buildAiPlaceholder(context),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderCard(context),
          const SizedBox(height: 18),
          _buildSectionNavigator(context),
          const SizedBox(height: 18),
          _buildCanvasCard(context),
          const SizedBox(height: 18),
          _buildRecognizedCard(context),
          const SizedBox(height: 18),
          _buildAiPlaceholder(context),
          const SizedBox(height: 18),
          _buildEntriesCard(context),
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
            : '左侧保留手写现场，右侧用于核对识别文本与解析结果，后续也会接入 AI 洞察。',
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
      child: const Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _NavChip(icon: Icons.draw_rounded, label: '手写原稿'),
          _NavChip(icon: Icons.notes_rounded, label: 'OCR 文本'),
          _NavChip(
            icon: Icons.auto_awesome_rounded,
            label: '提取内容',
            accent: AppColors.aiAccent,
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

  Widget _buildAiPlaceholder(BuildContext context) {
    final bullets = _entries.isEmpty
        ? const [
            '未来可按时间汇总一年内支出和事项',
            '可追溯 OCR 文本与结构化提取来源',
            '可对宝宝、家庭、工作等主题做连续洞察',
          ]
        : [
            '当前已识别 ${_entries.length} 条结构化线索',
            '后续可自动归并时间线、金额与健康记录',
            '后续可结合 OCR + AI 做纠错与归类增强',
          ];

    return AiInsightPlaceholder(
      title: '这页内容正在积累未来可分析的数据',
      description: _recognizedText.isEmpty
          ? '等识别文本更完整后，这里可以生成总结、趋势和跨时间查询结果。'
          : '当前先保留洞察位，后续可在这里展示支出分类、事项时间线和多主题总结。',
      bullets: bullets,
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
            description: '你可以先浏览拆分后的信息，未来这里还会补充提取来源与 AI 审计能力。',
          ),
          const SizedBox(height: 16),
          if (_entries.isEmpty)
            const EmptyStateView(
              icon: Icons.layers_clear_outlined,
              title: '暂时没有解析结果',
              description: '这不影响保存和查看。等文本更完整后，再识别一次会更容易提取结构。',
            )
          else ...[
            ..._entries.map((entry) => EntryRow(entry: entry)),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: null,
              icon: const Icon(Icons.source_outlined),
              label: const Text('查看提取来源（敬请期待）'),
            ),
          ],
        ],
      ),
    );
  }

  String _formattedDate(DateTime date) =>
      '${date.year}年${date.month}月${date.day}日';

  String _timeText(DateTime date) =>
      '${date.month}月${date.day}日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  void _shareNote() {
    if (_recognizedText.isEmpty) return;
    Share.share(_recognizedText, subject: 'IdeaNotes 笔记');
  }
}

class _NavChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _NavChip({
    required this.icon,
    required this.label,
    this.accent = AppColors.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}
