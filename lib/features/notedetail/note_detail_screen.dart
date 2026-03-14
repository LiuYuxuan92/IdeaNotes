import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/design_system.dart';
import '../../core/models/note.dart';
import '../../core/models/note_entry.dart';
import '../../core/parser/entry_parser.dart';
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
      _entries = EntryParser.parseMultiLine(_recognizedText);
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = context.isLarge ? 32.0 : 20.0;
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
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSurface(
                        child: AppSectionHeader(
                          eyebrow: '笔记详情',
                          title: _recognizedText.isEmpty
                              ? '这页内容还没识别'
                              : '这页手写内容已经整理为可阅读文本',
                          description: _recognizedText.isEmpty
                              ? '你可以回到画布继续补写，或重新识别一次，让内容更容易搜索和整理。'
                              : '先核对识别文本，再查看下方自动解析出的事项、支出和备忘。',
                          trailing: _buildMeta(context),
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (context.isLarge)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                flex: 11, child: _buildCanvasCard(context)),
                            const SizedBox(width: 18),
                            Expanded(
                                flex: 9, child: _buildRecognizedCard(context)),
                          ],
                        )
                      else ...[
                        _buildCanvasCard(context),
                        const SizedBox(height: 18),
                        _buildRecognizedCard(context),
                      ],
                      const SizedBox(height: 18),
                      _buildEntriesCard(context),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildMeta(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.end,
      children: [
        _metaPill(context, Icons.schedule_rounded,
            '更新于 ${_timeText(widget.note.updatedAt)}'),
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

  Widget _buildCanvasCard(BuildContext context) {
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            eyebrow: '原始画布',
            title: '保留你的手写现场',
            description: '这里保留了原始书写状态，方便你核对字迹、布局和上下文。',
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 240),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F5F1),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: _snapshotBytes != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.memory(
                      _snapshotBytes!,
                      fit: BoxFit.contain,
                      width: double.infinity,
                    ),
                  )
                : const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('当前没有可显示的画布快照。'),
                    ),
                  ),
          ),
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
            constraints:
                BoxConstraints(minHeight: context.isCompact ? 180 : 240),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFB),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: _recognizedText.isEmpty
                ? Text(
                    '这页目前还是原始手写内容。回到画布后点一下“识别”，系统会把文本整理到这里。',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  )
                : SelectableText(
                    _recognizedText,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(height: 1.65),
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
            title: _entries.isEmpty ? '还没有可解析的结构化内容' : '系统已帮你拆出重点信息',
            description: _entries.isEmpty
                ? '当前只有原始文本，没有识别到明确的支出、事项或备忘结构。'
                : '你可以先浏览拆分后的信息，再决定是否继续整理到其他工具。',
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

  String _formattedDate(DateTime date) =>
      '${date.year}年${date.month}月${date.day}日';

  String _timeText(DateTime date) =>
      '${date.month}月${date.day}日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  void _shareNote() {
    if (_recognizedText.isEmpty) return;
    Share.share(_recognizedText, subject: 'IdeaNotes 笔记');
  }
}
