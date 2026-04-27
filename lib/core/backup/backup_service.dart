import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../diagnostics/error_log.dart';
import '../storage/database_helper.dart';
import '../storage/database_migrations.dart';

class BackupResult {
  final File zipFile;
  final int sizeBytes;
  final int noteCount;
  final DateTime exportedAt;

  const BackupResult({
    required this.zipFile,
    required this.sizeBytes,
    required this.noteCount,
    required this.exportedAt,
  });
}

class RestoreResult {
  final bool success;
  final String? errorMessage;
  final int? restoredNoteCount;

  const RestoreResult.success({this.restoredNoteCount})
      : success = true,
        errorMessage = null;

  const RestoreResult.failure(String message)
      : success = false,
        errorMessage = message,
        restoredNoteCount = null;
}

/// 个人级备份/恢复服务。
///
/// - 自动备份：App 启动时若距上次备份超过 [defaultAutoInterval] 则导出一份 zip
///   到 `Android/data/<package>/files/IdeaNotes/backups/auto-YYYYMMDD-HHmm.zip`，
///   保留最近 [_keepBackups] 份。
/// - 手动「另存到 Download」：通过 MainActivity 的 `media_store` MethodChannel
///   把 zip 复制到 `Download/IdeaNotes/`，能在卸载后存活（视设备而定）。
/// - 恢复：先把当前 db + images 改名为 `*.pre_restore`，再解压；恢复失败可回滚。
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const Duration defaultAutoInterval = Duration(hours: 24);
  static const int _keepBackups = 7;
  static const String _appVersion = '1.0.3+4';
  static const String _imagesDirName = 'images';
  static const String _databaseFileName = 'idea_notes.db';
  static const _channel = MethodChannel('com.ideanotes.app/media_store');

  Future<Directory> getBackupDirectory() async {
    final external = await getExternalStorageDirectory();
    final base = external ?? await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'IdeaNotes', 'backups'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 列出现有备份，最新在前。
  Future<List<File>> listBackups() async {
    final dir = await getBackupDirectory();
    final files = await dir
        .list()
        .where((e) => e is File && e.path.toLowerCase().endsWith('.zip'))
        .cast<File>()
        .toList();
    files.sort((a, b) {
      final aStat = a.statSync();
      final bStat = b.statSync();
      return bStat.modified.compareTo(aStat.modified);
    });
    return files;
  }

  /// 距上次备份超过 [interval] 时执行一次自动备份；非阻塞使用。
  Future<void> autoBackupIfNeeded({
    Duration interval = defaultAutoInterval,
    DateTime? now,
  }) async {
    try {
      final backups = await listBackups();
      final reference = now ?? DateTime.now();
      if (backups.isNotEmpty) {
        final lastModified = backups.first.statSync().modified;
        if (reference.difference(lastModified).abs() < interval) {
          return;
        }
      }
      await exportBackup(now: reference, autoTriggered: true);
    } catch (e, st) {
      ErrorLog.instance.warn('backup.auto', '自动备份失败',
          error: e, stack: st);
    }
  }

  Future<BackupResult> exportBackup({
    DateTime? now,
    bool autoTriggered = false,
  }) async {
    final exportedAt = now ?? DateTime.now();
    final stamp = _stampFor(exportedAt);
    final prefix = autoTriggered ? 'auto' : 'manual';

    final backupDir = await getBackupDirectory();
    final tempDir = Directory(p.join(backupDir.path, '.tmp-$stamp'));
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    await tempDir.create(recursive: true);
    final tempDbPath = p.join(tempDir.path, _databaseFileName);

    int noteCount = 0;
    try {
      // VACUUM INTO 给一份原子化 DB 快照，无需关闭活跃连接。
      final db = await DatabaseHelper.instance.database;
      await db.execute('VACUUM INTO ?', [tempDbPath]);
      noteCount = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM notes')) ??
          0;

      final encoder = ZipFileEncoder();
      final outPath = p.join(backupDir.path, '$prefix-$stamp.zip');
      encoder.create(outPath);
      try {
        await encoder.addFile(File(tempDbPath), 'db/$_databaseFileName');

        final imagesDir = Directory(
            p.join((await getApplicationDocumentsDirectory()).path,
                _imagesDirName));
        if (await imagesDir.exists()) {
          await encoder.addDirectory(imagesDir, includeDirName: true);
        }

        final manifest = <String, dynamic>{
          'schemaVersion': kDatabaseVersion,
          'appVersion': _appVersion,
          'exportedAt': exportedAt.toUtc().toIso8601String(),
          'noteCount': noteCount,
          'autoTriggered': autoTriggered,
        };
        final manifestBytes = utf8.encode(jsonEncode(manifest));
        encoder.addArchiveFile(
          ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
        );
      } finally {
        await encoder.close();
      }

      final zipFile = File(outPath);
      await _pruneOldBackups(backupDir);
      return BackupResult(
        zipFile: zipFile,
        sizeBytes: await zipFile.length(),
        noteCount: noteCount,
        exportedAt: exportedAt,
      );
    } finally {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  /// 通过 MediaStore 把备份复制到系统 Download/IdeaNotes/ 目录。
  /// 仅 Android 支持；返回 true 表示成功。
  Future<bool> exportToDownloads(File backup) async {
    if (!Platform.isAndroid) return false;
    try {
      final result =
          await _channel.invokeMethod<String>('exportToDownloads', {
        'source': backup.path,
        'displayName': p.basename(backup.path),
        'mimeType': 'application/zip',
      });
      return result != null && result.isNotEmpty;
    } on PlatformException catch (e, st) {
      ErrorLog.instance.error('backup.export_to_downloads',
          '另存到系统 Download 失败',
          error: e, stack: st);
      return false;
    } catch (e, st) {
      ErrorLog.instance.error('backup.export_to_downloads',
          '另存到系统 Download 时出错',
          error: e, stack: st);
      return false;
    }
  }

  Future<RestoreResult> restoreBackup(File zipFile) async {
    if (!await zipFile.exists()) {
      return const RestoreResult.failure('备份文件不存在');
    }

    final docs = await getApplicationDocumentsDirectory();
    final dbPath = p.join(await getDatabasesPath(), _databaseFileName);
    final imagesPath = p.join(docs.path, _imagesDirName);

    final preStamp =
        DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final preDbBackup = '$dbPath.pre_restore_$preStamp';
    final preImagesBackup = '$imagesPath.pre_restore_$preStamp';

    try {
      await DatabaseHelper.instance.close();

      final originalDb = File(dbPath);
      if (await originalDb.exists()) {
        await originalDb.rename(preDbBackup);
      }
      final originalImages = Directory(imagesPath);
      if (await originalImages.exists()) {
        await originalImages.rename(preImagesBackup);
      }

      final inputStream = InputFileStream(zipFile.path);
      final archive = ZipDecoder().decodeBuffer(inputStream);
      var foundDb = false;
      try {
        for (final entry in archive) {
          final name = entry.name;
          if (entry.isFile) {
            Uint8List bytes = entry.content as Uint8List;
            if (name == 'db/$_databaseFileName' || name == _databaseFileName) {
              final f = File(dbPath);
              await f.create(recursive: true);
              await f.writeAsBytes(bytes, flush: true);
              foundDb = true;
            } else if (name.startsWith('$_imagesDirName/')) {
              final out = File(p.join(docs.path, name));
              await out.create(recursive: true);
              await out.writeAsBytes(bytes, flush: true);
            }
            // manifest.json 与其他无关文件忽略。
          }
        }
      } finally {
        await inputStream.close();
      }

      if (!foundDb) {
        await _rollbackRestore(
          dbPath: dbPath,
          imagesPath: imagesPath,
          preDbBackup: preDbBackup,
          preImagesBackup: preImagesBackup,
        );
        return const RestoreResult.failure('备份文件不完整：未找到数据库');
      }

      final db = await DatabaseHelper.instance.database;
      final restored = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM notes'));
      return RestoreResult.success(restoredNoteCount: restored);
    } catch (e, st) {
      ErrorLog.instance.error('backup.restore', '恢复备份失败',
          error: e, stack: st);
      await _rollbackRestore(
        dbPath: dbPath,
        imagesPath: imagesPath,
        preDbBackup: preDbBackup,
        preImagesBackup: preImagesBackup,
      );
      return RestoreResult.failure(e.toString());
    }
  }

  Future<void> _rollbackRestore({
    required String dbPath,
    required String imagesPath,
    required String preDbBackup,
    required String preImagesBackup,
  }) async {
    try {
      final attemptedDb = File(dbPath);
      if (await attemptedDb.exists()) {
        await attemptedDb.delete();
      }
      final attemptedImages = Directory(imagesPath);
      if (await attemptedImages.exists()) {
        await attemptedImages.delete(recursive: true);
      }
      final preDb = File(preDbBackup);
      if (await preDb.exists()) {
        await preDb.rename(dbPath);
      }
      final preImages = Directory(preImagesBackup);
      if (await preImages.exists()) {
        await preImages.rename(imagesPath);
      }
    } catch (e, st) {
      ErrorLog.instance.error('backup.rollback', '恢复回滚失败',
          error: e, stack: st);
    }
  }

  Future<void> _pruneOldBackups(Directory dir) async {
    final files = await listBackups();
    if (files.length <= _keepBackups) return;
    for (var i = _keepBackups; i < files.length; i++) {
      try {
        await files[i].delete();
      } catch (_) {}
    }
  }

  String _stampFor(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}';
  }
}
