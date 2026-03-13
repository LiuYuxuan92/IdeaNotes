import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/models/note.dart';
import '../../core/models/note_entry.dart';
import '../../core/storage/database_helper.dart';
import '../../core/storage/image_storage.dart';
import '../../core/parser/entry_parser.dart';
import '../../shared/widgets/entry_row.dart';

class NoteDetailScreen extends StatefulWidget {
  final Note note;

  const NoteDetailScreen({super.key, required this.note});

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  Uint8List? _snapshotBytes;
  String _recognizedText = '';
  List<NoteEntry> _entries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNoteDetail();
  }

  Future<void> _loadNoteDetail() async {
    setState(() => _isLoading = true);

    // 加载快照图片
    if (widget.note.snapshotImagePath != null) {
      _snapshotBytes = await ImageStorage.loadSnapshot(widget.note.snapshotImagePath!);
    }

    _recognizedText = widget.note.recognizedText ?? '';

    // 优先读取数据库里的结构化条目，保证和保存时的数据源一致
    final entryMaps = await DatabaseHelper.instance.getNoteEntries(widget.note.id);
    if (entryMaps.isNotEmpty) {
      _entries = entryMaps.map((map) => NoteEntry.fromMap(map)).toList();
    } else if (_recognizedText.isNotEmpty) {
      // 数据库里暂无条目时，再退回到按 OCR 文本现场解析
      _entries = EntryParser.parseMultiLine(_recognizedText);
    } else {
      _entries = [];
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_formatDate(widget.note.createdAt)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _shareNote,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOverviewCard(context),
                  const SizedBox(height: 16),
                  if (_snapshotBytes != null) ...[
                    _buildSectionTitle(context, '手写原稿'),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        _snapshotBytes!,
                        fit: BoxFit.contain,
                        width: double.infinity,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_recognizedText.isNotEmpty) ...[
                    _buildSectionTitle(context, '识别文本'),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _recognizedText,
                        style: const TextStyle(fontSize: 14, height: 1.5),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_entries.isNotEmpty) ...[
                    _buildSectionTitle(context, '解析结果'),
                    const SizedBox(height: 8),
                    ..._entries.map((entry) => EntryRow(entry: entry)),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildOverviewCard(BuildContext context) {
    final expenseCount = _entries.where((e) => e.type == NoteEntryType.expense).length;
    final eventCount = _entries.where((e) => e.type == NoteEntryType.event).length;
    final memoCount = _entries.where((e) => e.type == NoteEntryType.memo).length;
    final totalChars = _recognizedText.trim().isEmpty ? 0 : _recognizedText.trim().length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '笔记概览',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildOverviewChip('消费 $expenseCount'),
              _buildOverviewChip('事项 $eventCount'),
              _buildOverviewChip('备忘 $memoCount'),
              _buildOverviewChip('识别字数 $totalChars'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日';
  }

  void _shareNote() {
    // TODO: 实现分享功能
  }
}
