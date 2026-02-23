import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/models/note.dart';
import 'bloc/note_list_bloc.dart';
import 'note_list_item.dart';
import '../notedetail/note_detail_screen.dart';
import '../canvas/canvas_screen.dart';

/// 笔记列表主页面
/// 显示所有笔记的列表，支持搜索和新建
class NoteListScreen extends StatefulWidget {
  const NoteListScreen({super.key});

  @override
  State<NoteListScreen> createState() => _NoteListScreenState();
}

class _NoteListScreenState extends State<NoteListScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    // 加载笔记列表
    context.read<NoteListBloc>().add(LoadNotes());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: BlocBuilder<NoteListBloc, NoteListState>(
        builder: (context, state) {
          return Column(
            children: [
              // 搜索框
              if (_isSearching) _buildSearchBar(),
              
              // 笔记列表
              Expanded(
                child: _buildContent(state),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewNote,
        tooltip: '新建笔记',
        child: const Icon(Icons.add),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: _isSearching
          ? null
          : const Text('我的笔记'),
      actions: [
        // 搜索按钮
        IconButton(
          icon: Icon(_isSearching ? Icons.close : Icons.search),
          onPressed: _toggleSearch,
          tooltip: _isSearching ? '关闭搜索' : '搜索',
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        decoration: InputDecoration(
          hintText: '搜索笔记内容...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    context.read<NoteListBloc>().add(const SearchNotes(''));
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
          fillColor: Colors.white,
        ),
        onChanged: (value) {
          context.read<NoteListBloc>().add(SearchNotes(value));
        },
      ),
    );
  }

  Widget _buildContent(NoteListState state) {
    switch (state.status) {
      case NoteListStatus.initial:
      case NoteListStatus.loading:
        return const Center(child: CircularProgressIndicator());
      
      case NoteListStatus.error:
        return _buildErrorState(state.errorMessage);
      
      case NoteListStatus.loaded:
        if (state.filteredNotes.isEmpty) {
          return _buildEmptyState(state.searchQuery.isNotEmpty);
        }
        return _buildNotesList(state);
    }
  }

  Widget _buildNotesList(NoteListState state) {
    return RefreshIndicator(
      onRefresh: () async {
        context.read<NoteListBloc>().add(RefreshNotes());
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: state.filteredNotes.length,
        itemBuilder: (context, index) {
          final note = state.filteredNotes[index];
          return NoteListItem(
            note: note,
            onTap: () => _openNoteDetail(note),
            onDelete: () => _deleteNote(note.id),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(bool isSearching) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSearching ? Icons.search_off : Icons.note_add,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            isSearching ? '没有找到匹配的笔记' : '还没有任何笔记',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isSearching ? '试试其他关键词' : '点击右下角按钮创建第一篇笔记',
            style: TextStyle(
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String? errorMessage) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 80,
            color: Colors.red.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            '加载失败',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            errorMessage ?? '未知错误',
            style: TextStyle(
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              context.read<NoteListBloc>().add(LoadNotes());
            },
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        context.read<NoteListBloc>().add(const SearchNotes(''));
      }
    });
  }

  void _createNewNote() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CanvasScreen(
          onSave: () {
            // 刷新列表
            context.read<NoteListBloc>().add(RefreshNotes());
          },
        ),
      ),
    );
  }

  void _openNoteDetail(Note note) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NoteDetailScreen(note: note),
      ),
    );
  }

  void _deleteNote(String noteId) {
    context.read<NoteListBloc>().add(DeleteNote(noteId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('笔记已删除'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
