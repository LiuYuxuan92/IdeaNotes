import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 图片存储服务
/// 负责保存、加载和删除笔记相关的图片（快照和缩略图）
class ImageStorage {
  static const _uuid = Uuid();
  
  /// 获取图片存储根目录
  static Future<Directory> _getImageDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final imageDir = Directory('${appDir.path}/images');
    if (!await imageDir.exists()) {
      await imageDir.create(recursive: true);
    }
    return imageDir;
  }

  /// 获取快照存储目录
  static Future<Directory> _getSnapshotDirectory() async {
    final imageDir = await _getImageDirectory();
    final snapshotDir = Directory('${imageDir.path}/snapshots');
    if (!await snapshotDir.exists()) {
      await snapshotDir.create(recursive: true);
    }
    return snapshotDir;
  }

  /// 获取缩略图存储目录
  static Future<Directory> _getThumbnailDirectory() async {
    final imageDir = await _getImageDirectory();
    final thumbnailDir = Directory('${imageDir.path}/thumbnails');
    if (!await thumbnailDir.exists()) {
      await thumbnailDir.create(recursive: true);
    }
    return thumbnailDir;
  }

  /// 保存快照图片
  /// 返回保存后的文件路径
  static Future<String> saveSnapshot(Uint8List imageBytes, String noteId) async {
    final snapshotDir = await _getSnapshotDirectory();
    final fileName = '${noteId}_${_uuid.v4()}.png';
    final filePath = '${snapshotDir.path}/$fileName';
    
    final file = File(filePath);
    await file.writeAsBytes(imageBytes);
    
    return filePath;
  }

  /// 保存缩略图图片
  /// 返回保存后的文件路径
  static Future<String> saveThumbnail(Uint8List imageBytes, String noteId) async {
    final thumbnailDir = await _getThumbnailDirectory();
    final fileName = '${noteId}_thumb_${_uuid.v4()}.png';
    final filePath = '${thumbnailDir.path}/$fileName';
    
    final file = File(filePath);
    await file.writeAsBytes(imageBytes);
    
    return filePath;
  }

  /// 加载快照图片
  /// 返回图片字节数据，如果不存在返回 null
  static Future<Uint8List?> loadSnapshot(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      return await file.readAsBytes();
    }
    return null;
  }

  /// 加载缩略图图片
  /// 返回图片字节数据，如果不存在返回 null
  static Future<Uint8List?> loadThumbnail(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      return await file.readAsBytes();
    }
    return null;
  }

  /// 删除指定笔记相关的所有图片（快照和缩略图）
  static Future<void> deleteNoteImages(String noteId) async {
    // 删除快照
    await _deleteImagesInDirectory(await _getSnapshotDirectory(), noteId);
    // 删除缩略图
    await _deleteImagesInDirectory(await _getThumbnailDirectory(), noteId);
  }

  /// 在指定目录中删除与笔记相关的图片
  static Future<void> _deleteImagesInDirectory(Directory dir, String noteId) async {
    if (!await dir.exists()) return;
    
    final files = await dir.list().toList();
    for (final entity in files) {
      if (entity is File && entity.path.contains(noteId)) {
        try {
          await entity.delete();
        } catch (e) {
          // 忽略删除错误，继续删除其他文件
          print('Failed to delete image: ${entity.path}, error: $e');
        }
      }
    }
  }

  /// 检查快照是否存在
  static Future<bool> snapshotExists(String filePath) async {
    return File(filePath).exists();
  }

  /// 检查缩略图是否存在
  static Future<bool> thumbnailExists(String filePath) async {
    return File(filePath).exists();
  }

  /// 获取图片存储的统计信息
  static Future<Map<String, int>> getStorageStats() async {
    int snapshotCount = 0;
    int thumbnailCount = 0;
    int snapshotSize = 0;
    int thumbnailSize = 0;

    final snapshotDir = await _getSnapshotDirectory();
    final thumbnailDir = await _getThumbnailDirectory();

    if (await snapshotDir.exists()) {
      final snapshotFiles = await snapshotDir.list().toList();
      snapshotCount = snapshotFiles.whereType<File>().length;
      for (final entity in snapshotFiles) {
        if (entity is File) {
          snapshotSize += await entity.length();
        }
      }
    }

    if (await thumbnailDir.exists()) {
      final thumbnailFiles = await thumbnailDir.list().toList();
      thumbnailCount = thumbnailFiles.whereType<File>().length;
      for (final entity in thumbnailFiles) {
        if (entity is File) {
          thumbnailSize += await entity.length();
        }
      }
    }

    return {
      'snapshotCount': snapshotCount,
      'thumbnailCount': thumbnailCount,
      'snapshotSize': snapshotSize,
      'thumbnailSize': thumbnailSize,
      'totalCount': snapshotCount + thumbnailCount,
      'totalSize': snapshotSize + thumbnailSize,
    };
  }

  /// 清理所有图片（谨慎使用）
  static Future<void> clearAllImages() async {
    final snapshotDir = await _getSnapshotDirectory();
    final thumbnailDir = await _getThumbnailDirectory();

    if (await snapshotDir.exists()) {
      await snapshotDir.delete(recursive: true);
    }
    if (await thumbnailDir.exists()) {
      await thumbnailDir.delete(recursive: true);
    }
  }
}
