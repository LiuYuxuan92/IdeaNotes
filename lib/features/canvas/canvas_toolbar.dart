import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/design_system.dart';
import 'bloc/canvas_bloc.dart';

class CanvasToolbar extends StatelessWidget {
  const CanvasToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CanvasBloc, CanvasState>(
      builder: (context, state) {
        final isCompact = context.isCompact;
        const tools = [
          _ToolSpec(
            tool: CanvasTool.pen,
            icon: Icons.edit_rounded,
            label: '墨蓝笔',
            swatch: AppColors.inkBlue,
          ),
          _ToolSpec(
            tool: CanvasTool.bluePen,
            icon: Icons.brush_rounded,
            label: '石板蓝',
            swatch: Color(0xFF3C617C),
          ),
          _ToolSpec(
            tool: CanvasTool.redPen,
            icon: Icons.draw_rounded,
            label: '批注红',
            swatch: Color(0xFF8A4145),
          ),
          _ToolSpec(
            tool: CanvasTool.pencil,
            icon: Icons.mode_edit_outline_rounded,
            label: '铅笔',
            swatch: Color(0xFF62717D),
          ),
          _ToolSpec(
            tool: CanvasTool.eraser,
            icon: Icons.auto_fix_high_rounded,
            label: '橡皮',
            swatch: AppColors.textMuted,
          ),
        ];

        return ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: context.isLarge ? 920 : double.infinity,
          ),
          child: AppSurface(
            padding: EdgeInsets.fromLTRB(
              isCompact ? 10 : 14,
              isCompact ? 10 : 12,
              isCompact ? 10 : 14,
              isCompact ? 10 : 12,
            ),
            radius: isCompact ? 28 : 32,
            backgroundColor: Colors.white.withValues(alpha: 0.96),
            border: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120D1B26),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isCompact)
                      Text(
                        _ToolbarLead.labelForTool(state.currentTool),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                      )
                    else
                      _ToolbarLead(tool: state.currentTool),
                    const Spacer(),
                    _CompactActionButton(
                      icon: Icons.undo_rounded,
                      label: '撤销',
                      enabled: state.canUndo,
                      onTap: state.canUndo
                          ? () => context.read<CanvasBloc>().add(StrokeUndone())
                          : null,
                    ),
                    const SizedBox(width: 8),
                    _CompactActionButton(
                      icon: Icons.redo_rounded,
                      label: '重做',
                      enabled: state.canRedo,
                      onTap: state.canRedo
                          ? () => context.read<CanvasBloc>().add(StrokeRedone())
                          : null,
                    ),
                    const SizedBox(width: 8),
                    _CompactActionButton(
                      icon: Icons.delete_sweep_rounded,
                      label: '清空画布',
                      isDanger: true,
                      onTap: () => _showClearDialog(context),
                    ),
                  ],
                ),
                SizedBox(height: isCompact ? 8 : 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < tools.length; i++) ...[
                        _ToolPill(
                          spec: tools[i],
                          isSelected: state.currentTool == tools[i].tool,
                          onTap: () => context
                              .read<CanvasBloc>()
                              .add(CanvasToolChanged(tools[i].tool)),
                        ),
                        if (i != tools.length - 1) const SizedBox(width: 10),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showClearDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空整张画布？'),
        content: const Text('这会移除当前所有笔迹。如果只是写错一点，建议先用撤销或橡皮。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('继续保留'),
          ),
          TextButton(
            onPressed: () {
              context.read<CanvasBloc>().add(CanvasCleared());
              Navigator.pop(dialogContext);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
  }
}

class _ToolbarLead extends StatelessWidget {
  final CanvasTool tool;

  const _ToolbarLead({required this.tool});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '画布工具',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.textMuted,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          labelForTool(tool),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AppColors.textPrimary,
              ),
        ),
      ],
    );
  }

  static String labelForTool(CanvasTool tool) {
    switch (tool) {
      case CanvasTool.pen:
        return '当前使用墨蓝笔';
      case CanvasTool.bluePen:
        return '当前使用石板蓝';
      case CanvasTool.redPen:
        return '当前使用批注红';
      case CanvasTool.pencil:
        return '当前使用铅笔';
      case CanvasTool.eraser:
        return '当前使用橡皮';
    }
  }
}

class _ToolPill extends StatelessWidget {
  final _ToolSpec spec;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToolPill({
    required this.spec,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = context.isCompact;

    return Semantics(
      label: '切换到${spec.label}',
      selected: isSelected,
      child: Tooltip(
        message: spec.label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 10 : 12,
            vertical: isCompact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color:
                isSelected ? const Color(0xFFE8EFF3) : const Color(0xFFF5F7F8),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isSelected
                  ? AppColors.selection
                  : Theme.of(context).colorScheme.outlineVariant,
              width: isSelected ? 1.2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: isCompact ? 30 : 34,
                height: isCompact ? 30 : 34,
                decoration: BoxDecoration(
                  color: spec.swatch.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(isCompact ? 12 : 14),
                ),
                child: Icon(spec.icon,
                    size: isCompact ? 16 : 18, color: spec.swatch),
              ),
              if (!isCompact) ...[
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spec.label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isSelected
                                ? AppColors.inkBlue
                                : AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 18,
                      height: 4,
                      decoration: BoxDecoration(
                        color: spec.swatch,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(width: 4),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: spec.swatch,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _CompactActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final bool isDanger;
  final VoidCallback? onTap;

  const _CompactActionButton({
    required this.icon,
    required this.label,
    this.enabled = true,
    this.isDanger = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = context.isCompact;
    final foreground = !enabled
        ? AppColors.disabled
        : isDanger
            ? AppColors.error
            : AppColors.inkBlue;
    final background = !enabled
        ? const Color(0xFFF0F2F4)
        : isDanger
            ? const Color(0xFFF9EFF0)
            : const Color(0xFFEAF1F4);

    return Tooltip(
      message: label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 10 : 12,
            vertical: isCompact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: foreground),
              if (context.isMedium || context.isLarge) ...[
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolSpec {
  final CanvasTool tool;
  final IconData icon;
  final String label;
  final Color swatch;

  const _ToolSpec({
    required this.tool,
    required this.icon,
    required this.label,
    required this.swatch,
  });
}
