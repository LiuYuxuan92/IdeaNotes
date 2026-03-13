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
  List<dynamic> _entries = [];
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
                  // 手写图片
                  if (_snapshotBytes != null) ...[
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

                  // 识别文本
                  if (_recognizedText.isNotEmpty) ...[
                    const Text(
                      '识别文本',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _recognizedText,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 解析结果
                  if (_entries.isNotEmpty) ...[
                    const Text(
                      '解析结果',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._entries.map((entry) => EntryRow(entry: entry)),
                  ],
                ],
              ),
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
