import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 应用本地诊断日志单例。
///
/// 用 JSON-lines 写入 `<documents>/logs/app.log`，按 [_maxBytes] 轮转，
/// 最多保留 [_keepFiles] 个文件。所有写入串行化，写入异常被吞掉以保证
/// 日志器自身永远不会成为故障源。
class ErrorLog {
  ErrorLog._();
  static final ErrorLog instance = ErrorLog._();

  static const int _maxBytes = 256 * 1024;
  static const int _keepFiles = 5;
  static const String _baseName = 'app.log';

  Future<Directory?>? _dirFuture;
  Future<void> _writeChain = Future.value();

  /// 公开 API 故意返回 void：日志写入由 [_writeChain] 串行化，
  /// 调用方可以放心 fire-and-forget，避免每个 catch 都得 await。
  void info(
    String tag,
    String message, {
    Object? error,
    StackTrace? stack,
  }) {
    _enqueue('info', tag, message, error, stack);
  }

  void warn(
    String tag,
    String message, {
    Object? error,
    StackTrace? stack,
  }) {
    _enqueue('warn', tag, message, error, stack);
  }

  void error(
    String tag,
    String message, {
    Object? error,
    StackTrace? stack,
  }) {
    _enqueue('error', tag, message, error, stack);
  }

  /// 返回当前及历史日志文件，最新的在前。仅返回真实存在的文件。
  Future<List<File>> latestLogFiles() async {
    final dir = await _ensureDirectory();
    if (dir == null) return const [];
    final files = <File>[];
    final current = File('${dir.path}/$_baseName');
    if (await current.exists()) {
      files.add(current);
    }
    for (var i = 1; i < _keepFiles; i++) {
      final f = File('${dir.path}/$_baseName.$i');
      if (await f.exists()) {
        files.add(f);
      }
    }
    return files;
  }

  void _enqueue(
    String level,
    String tag,
    String message,
    Object? error,
    StackTrace? stack,
  ) {
    final record = <String, Object?>{
      'ts': DateTime.now().toUtc().toIso8601String(),
      'level': level,
      'tag': tag,
      'message': message,
      if (error != null) 'error': error.toString(),
      if (stack != null) 'stack': stack.toString(),
    };
    final line = '${jsonEncode(record)}\n';
    _writeChain = _writeChain.then((_) => _writeLine(line)).catchError((_) {});
  }

  Future<void> _writeLine(String line) async {
    try {
      final dir = await _ensureDirectory();
      if (dir == null) return;
      final file = File('${dir.path}/$_baseName');
      if (await file.exists() && await file.length() + line.length > _maxBytes) {
        await _rotate(dir);
      }
      await file.writeAsString(line, mode: FileMode.append, flush: false);
    } catch (_) {
      // 日志失败永远不能把调用方搞挂。
    }
  }

  Future<void> _rotate(Directory dir) async {
    try {
      final oldest = File('${dir.path}/$_baseName.${_keepFiles - 1}');
      if (await oldest.exists()) {
        await oldest.delete();
      }
      for (var i = _keepFiles - 2; i >= 1; i--) {
        final src = File('${dir.path}/$_baseName.$i');
        if (await src.exists()) {
          await src.rename('${dir.path}/$_baseName.${i + 1}');
        }
      }
      final current = File('${dir.path}/$_baseName');
      if (await current.exists()) {
        await current.rename('${dir.path}/$_baseName.1');
      }
    } catch (_) {
      // 旋转失败时让下一次写入直接 append，最坏情况是日志文件超过 _maxBytes。
    }
  }

  Future<Directory?> _ensureDirectory() {
    return _dirFuture ??= _resolveDirectory();
  }

  Future<Directory?> _resolveDirectory() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/logs');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (_) {
      return null;
    }
  }
}
