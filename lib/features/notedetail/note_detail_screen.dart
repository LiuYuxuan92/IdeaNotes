import 'package:flutter/material.dart';
import '../../core/models/note.dart';
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
  final ImageStorage _imageStorage = ImageStorage();
  final EntryParser _entryParser = EntryParser();
  
  Image? _snapshotImage;
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
      _snapshotImage = await _imageStorage.loadSnapshot(widget.note.snapshotImagePath!);
    }

    // 解析识别文本
    _recognizedText = widget.note.recognizedText ?? '';
    if (_recognizedText.isNotEmpty) {
      _entries = _entryParser.parse(_recognizedText);
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
                  if (_snapshotImage != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        _snapshotImage!.bytes,
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
