import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/design_system.dart';
import '../../core/models/note.dart';
import '../canvas/canvas_screen.dart';
import '../notedetail/note_detail_screen.dart';
import 'bloc/note_list_bloc.dart';
import 'note_list_item.dart';

class NoteListScreen extends StatefulWidget {
  const NoteListScreen({super.key});

  @override
  State<NoteListScreen> createState() => _NoteListScreenState();
}

class _NoteListScreenState extends State<NoteListScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _isSearchExpanded = false;

  @override
  void initState() {
    super.initState();
    context.read<NoteListBloc>().add(LoadNotes());
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = context.isLarge ? 32.0 : 20.0;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNewNote,
        icon: const Icon(Icons.add_rounded),
        label: const Text('新建笔记'),
        tooltip: '新建笔记',
      ),
      body: SafeArea(
        child: BlocBuilder<NoteListBloc, NoteListState>(
          builder: (context, state) {
            return RefreshIndicator(
              onRefresh: () async {
                context.read<NoteListBloc>().add(RefreshNotes());
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding:
                        EdgeInsets.fromLTRB(horizontal, 18, horizontal, 12),
                    sliver: SliverToBoxAdapter(
                      child: _buildHeader(context, state),
                    ),
                  ),
                  if (_isSearchExpanded)
                    SliverPadding(
                      padding:
                          EdgeInsets.fromLTRB(horizontal, 0, horizontal, 12),
                      sliver:
                          SliverToBoxAdapter(child: _buildSearchBar(context)),
                    ),
                  SliverPadding(
                    padding:
                        EdgeInsets.fromLTRB(horizontal, 4, horizontal, 120),
                    sliver: _buildBody(context, state),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, NoteListState state) {
    final theme = Theme.of(context);
    final count = state.filteredNotes.length;
    final searchActive = _searchController.text.trim().isNotEmpty;

    return Column(
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
                    'IdeaNotes',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: AppColors.textMuted,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('把今天的手写想法，整理成可继续推进的内容',
                      style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 10),
                  Text(
                    searchActive
                        ? '已按关键词筛选，共找到 $count 条笔记。'
                        : count == 0
                            ? '还没有内容时，可以先写一页，再决定是否识别。'
                            : '最近更新的内容会优先显示，方便快速回到刚记录的想法。',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            IconButton.filledTonal(
              onPressed: _toggleSearch,
              tooltip: _isSearchExpanded ? '收起搜索' : '展开搜索',
              icon: Icon(_isSearchExpanded
                  ? Icons.close_rounded
                  : Icons.search_rounded),
            ),
          ],
        ),
        const SizedBox(height: 20),
        AppSurface(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _StatTile(
                label: '笔记总数',
                value: state.notes.length.toString(),
                icon: Icons.library_books_outlined,
              ),
              _StatTile(
                label: '可查看',
                value: state.filteredNotes.length.toString(),
                icon: Icons.visibility_outlined,
              ),
              _StatTile(
                label: '识别状态',
                value: _summarizeOcr(state.notes),
                icon: Icons.text_snippet_outlined,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return AppSurface(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: '搜标题关键词、识别文本或待办内容',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _searchController.clear();
                    context.read<NoteListBloc>().add(const SearchNotes(''));
                  },
                  tooltip: '清空搜索词',
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
        onChanged: (value) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 220), () {
            context.read<NoteListBloc>().add(SearchNotes(value));
          });
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, NoteListState state) {
    switch (state.status) {
      case NoteListStatus.initial:
      case NoteListStatus.loading:
        return const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        );
      case NoteListStatus.error:
        return SliverFillRemaining(
          hasScrollBody: false,
          child: _buildErrorState(context, state.errorMessage),
        );
      case NoteListStatus.loaded:
        if (state.filteredNotes.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: _buildEmptyState(context, state.searchQuery.isNotEmpty),
          );
        }
        return SliverList.separated(
          itemCount: state.filteredNotes.length,
          itemBuilder: (context, index) {
            final note = state.filteredNotes[index];
            return NoteListItem(
              note: note,
              onTap: () => _openNoteDetail(note),
              onDelete: () => _deleteNote(note.id),
            );
          },
          separatorBuilder: (_, __) => const SizedBox(height: 0),
        );
    }
  }

  Widget _buildEmptyState(BuildContext context, bool isSearching) {
    return EmptyStateView(
      icon:
          isSearching ? Icons.search_off_rounded : Icons.auto_stories_outlined,
      title: isSearching ? '没有找到相关笔记' : '先写下第一条想法吧',
      description: isSearching
          ? '换一个关键词，或直接打开最近的笔记继续整理。'
          : '新建一页手写内容后，可以继续识别、编辑，再整理成可执行的信息。',
      action: isSearching
          ? TextButton(
              onPressed: () {
                _searchController.clear();
                context.read<NoteListBloc>().add(const SearchNotes(''));
              },
              child: const Text('清空搜索词'),
            )
          : ElevatedButton.icon(
              onPressed: _createNewNote,
              icon: const Icon(Icons.add_rounded),
              label: const Text('新建第一条笔记'),
            ),
    );
  }

  Widget _buildErrorState(BuildContext context, String? errorMessage) {
    return EmptyStateView(
      icon: Icons.cloud_off_rounded,
      title: '笔记列表暂时打不开',
      description: errorMessage?.trim().isNotEmpty == true
          ? '$errorMessage\n你可以先重试，若仍失败再检查本地存储权限。'
          : '请先刷新一次；如果问题持续，再检查本地存储是否可用。',
      action: ElevatedButton.icon(
        onPressed: () => context.read<NoteListBloc>().add(LoadNotes()),
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('重新加载'),
      ),
    );
  }

  void _toggleSearch() {
    setState(() {
      _isSearchExpanded = !_isSearchExpanded;
      if (!_isSearchExpanded) {
        _searchController.clear();
        context.read<NoteListBloc>().add(const SearchNotes(''));
      }
    });
  }

  void _createNewNote() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => CanvasScreen(
          onSave: () => context.read<NoteListBloc>().add(RefreshNotes()),
        ),
      ),
    );
  }

  void _openNoteDetail(Note note) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (context) => NoteDetailScreen(note: note)),
    );
  }

  void _deleteNote(String noteId) {
    context.read<NoteListBloc>().add(DeleteNote(noteId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('这条笔记已删除。')),
    );
  }

  String _summarizeOcr(List<Note> notes) {
    if (notes.isEmpty) return '暂无内容';
    final recognized = notes
        .where((note) => (note.recognizedText ?? '').trim().isNotEmpty)
        .length;
    if (recognized == 0) return '待识别';
    return '$recognized/${notes.length} 已识别';
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7F8),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFDDE8EE),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: AppColors.inkBlue),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              const SizedBox(height: 2),
              Text(value, style: theme.textTheme.titleMedium),
            ],
          ),
        ],
      ),
    );
  }
}
