import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// OCR 结果展示组件
/// 显示识别文本，包含复制和编辑功能
class OcrResultBanner extends StatelessWidget {
  final String result;
  final VoidCallback? onCopy;
  final VoidCallback? onEdit;
  final VoidCallback? onSave;
  final bool showSaveButton;

  const OcrResultBanner({
    super.key,
    required this.result,
    this.onCopy,
    this.onEdit,
    this.onSave,
    this.showSaveButton = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.text_snippet, size: 18),
                const SizedBox(width: 8),
                Text(
                  'OCR 识别结果',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                // 复制按钮
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: result.isNotEmpty ? _handleCopy : null,
                  tooltip: '复制',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                // 编辑按钮
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  onPressed: result.isNotEmpty ? onEdit : null,
                  tooltip: '编辑',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                // 保存按钮（可选）
                if (showSaveButton) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.save, size: 18),
                    onPressed: result.isNotEmpty ? onSave : null,
                    tooltip: '保存到笔记',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ],
            ),
          ),
          
          // 结果内容
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: result.isEmpty
                  ? Text(
                      '点击 OCR 按钮识别手写内容',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  : SelectableText(
                      result,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            height: 1.5,
                          ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleCopy() {
    Clipboard.setData(ClipboardData(text: result));
    onCopy?.call();
  }
}
