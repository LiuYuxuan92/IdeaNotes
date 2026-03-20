import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/design_system.dart';
import '../notedetail/note_detail_screen.dart';
import '../notelist/bloc/note_list_bloc.dart';
import '../notelist/note_list_item.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _didSyncInitialQuery = false;

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), () {
      context.read<NoteListBloc>().add(SearchNotes(query));
    });
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
      body: SafeArea(
        child: BlocBuilder<NoteListBloc, NoteListState>(
          builder: (context, state) {
            _syncControllerFromState(state.searchQuery);

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(horizontal, 18, horizontal, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTopBar(context),
                      const SizedBox(height: 18),
                      _buildSearchHero(context, state),
                      const SizedBox(height: 18),
                      Expanded(child: _buildBody(context, state)),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _syncControllerFromState(String query) {
    if (_didSyncInitialQuery) return;
    if (query.isEmpty) return;
    _searchController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _didSyncInitialQuery = true;
  }

  Widget _buildTopBar(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: () => Navigator.maybePop(context),
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Search Center',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(
                '像命令中心一样搜索笔记、OCR 文本与后续结构化内容',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchHero(BuildContext context, NoteListState state) {
    final query = state.searchQuery;
    final hasQuery = query.isNotEmpty;

    return AppSurface(
      padding: const EdgeInsets.all(20),
      radius: 32,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFF7FAFB)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            eyebrow: '全局搜索',
            title: '像命令中心一样查找笔记',
            description: '后续也可以在这里直接询问 AI，例如支出汇总、事项时间线和健康记录。',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '搜索笔记内容...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _debounce?.cancel();
                        context.read<NoteListBloc>().add(const SearchNotes(''));
                        setState(() {});
                      },
                    ),
            ),
            onSubmitted: (value) {
              _debounce?.cancel();
              context.read<NoteListBloc>().add(SearchNotes(value));
            },
            onChanged: (value) {
              setState(() {});
              _onSearchChanged(value);
            },
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SuggestionChip(
                icon: Icons.history_rounded,
                label: hasQuery ? '当前关键词：$query' : '最近搜索',
              ),
              _SuggestionChip(
                icon: Icons.sell_outlined,
                label:
                    hasQuery ? '结果 ${state.filteredNotes.length} 条' : '按标签筛选',
              ),
              const _SuggestionChip(
                icon: Icons.auto_awesome_rounded,
                label: '问问 AI：上周我花了多少钱？',
                accent: AppColors.aiAccent,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, NoteListState state) {
    final query = state.searchQuery;

    if (query.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: AppSurface(
            isFlat: true,
            backgroundColor: const Color(0xFFF9FAFB),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.search, size: 56, color: AppColors.textMuted),
                const SizedBox(height: 14),
                Text(
                  '输入关键词搜索笔记',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '可以搜 OCR 文本、事项、金额关键词，后续也会扩展到 AI 查询入口。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (state.filteredNotes.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: AppSurface(
            isFlat: true,
            backgroundColor: const Color(0xFFF9FAFB),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.search_off,
                  size: 56,
                  color: AppColors.textMuted,
                ),
                const SizedBox(height: 14),
                Text(
                  '未找到相关笔记',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '试试换一个关键词，或者回到最近的笔记继续补充识别内容。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _InfoChip(text: '关键词：$query'),
            _InfoChip(text: '结果 ${state.filteredNotes.length} 条'),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: state.filteredNotes.length,
            itemBuilder: (context, index) {
              final note = state.filteredNotes[index];
              return NoteListItem(
                note: note,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) => NoteDetailScreen(note: note),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _SuggestionChip({
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
            : const Color(0xFFF3F5F6),
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

class _InfoChip extends StatelessWidget {
  final String text;

  const _InfoChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .primaryContainer
            .withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
