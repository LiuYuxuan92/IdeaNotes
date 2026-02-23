import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'bloc/canvas_bloc.dart';

/// 画布工具栏组件
/// 包含黑笔/蓝笔/红笔/铅笔/橡皮按钮和撤销/重做按钮
class CanvasToolbar extends StatelessWidget {
  const CanvasToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CanvasBloc, CanvasState>(
      builder: (context, state) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                // 绘图工具
                _buildToolGroup(context, state),
                
                const SizedBox(width: 16),
                
                // 分割线
                Container(
                  width: 1,
                  height: 32,
                  color: Theme.of(context).dividerColor,
                ),
                
                const SizedBox(width: 16),
                
                // 撤销/重做
                _buildUndoRedoGroup(context, state),
                
                const Spacer(),
                
                // 清除按钮
                _buildClearButton(context),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildToolGroup(BuildContext context, CanvasState state) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 黑笔
        _ToolButton(
          icon: Icons.edit,
          color: Colors.black,
          isSelected: state.currentTool == CanvasTool.pen,
          onTap: () => context.read<CanvasBloc>().add(
            const CanvasToolChanged(CanvasTool.pen),
          ),
          tooltip: '黑笔',
        ),
        
        // 蓝笔
        _ToolButton(
          icon: Icons.edit,
          color: const Color(0xFF1565C0),
          isSelected: state.currentTool == CanvasTool.bluePen,
          onTap: () => context.read<CanvasBloc>().add(
            const CanvasToolChanged(CanvasTool.bluePen),
          ),
          tooltip: '蓝笔',
        ),
        
        // 红笔
        _ToolButton(
          icon: Icons.edit,
          color: const Color(0xFFC62828),
          isSelected: state.currentTool == CanvasTool.redPen,
          onTap: () => context.read<CanvasBloc>().add(
            const CanvasToolChanged(CanvasTool.redPen),
          ),
          tooltip: '红笔',
        ),
        
        // 铅笔
        _ToolButton(
          icon: Icons.create,
          color: Colors.grey.shade700,
          isSelected: state.currentTool == CanvasTool.pencil,
          onTap: () => context.read<CanvasBloc>().add(
            const CanvasToolChanged(CanvasTool.pencil),
          ),
          tooltip: '铅笔',
        ),
        
        // 橡皮
        _ToolButton(
          icon: Icons.auto_fix_high,
          color: Colors.grey.shade400,
          isSelected: state.currentTool == CanvasTool.eraser,
          onTap: () => context.read<CanvasBloc>().add(
            const CanvasToolChanged(CanvasTool.eraser),
          ),
          tooltip: '橡皮',
          isEraser: true,
        ),
      ],
    );
  }

  Widget _buildUndoRedoGroup(BuildContext context, CanvasState state) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 撤销
        IconButton(
          icon: Icon(
            Icons.undo,
            color: state.canUndo 
                ? Theme.of(context).colorScheme.primary 
                : Theme.of(context).disabledColor,
          ),
          onPressed: state.canUndo
              ? () => context.read<CanvasBloc>().add(StrokeUndone())
              : null,
          tooltip: '撤销',
        ),
        
        // 重做
        IconButton(
          icon: Icon(
            Icons.redo,
            color: state.canRedo 
                ? Theme.of(context).colorScheme.primary 
                : Theme.of(context).disabledColor,
          ),
          onPressed: state.canRedo
              ? () => context.read<CanvasBloc>().add(StrokeRedone())
              : null,
          tooltip: '重做',
        ),
      ],
    );
  }

  Widget _buildClearButton(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.delete_outline),
      onPressed: () => _showClearDialog(context),
      tooltip: '清除',
    );
  }

  void _showClearDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清除画布'),
        content: const Text('确定要清除所有内容吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              context.read<CanvasBloc>().add(CanvasCleared());
              Navigator.pop(dialogContext);
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }
}

/// 单个工具按钮
class _ToolButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;
  final String tooltip;
  final bool isEraser;

  const _ToolButton({
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
    required this.tooltip,
    this.isEraser = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isSelected 
            ? Theme.of(context).colorScheme.primaryContainer 
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: isEraser 
                  ? (isSelected ? color : Colors.grey) 
                  : (isSelected ? color : Colors.grey.shade600),
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
