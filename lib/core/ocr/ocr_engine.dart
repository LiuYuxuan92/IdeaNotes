import 'dart:typed_data';

/// OCR 引擎抽象接口
/// 定义 OCR 功能的统一接口
abstract class OcrEngine {
  /// 引擎名称
  String get engineName;

  /// 是否可用
  Future<bool> isAvailable();

  /// 从图片字节数据中识别文字
  /// 返回识别到的文本列表（每行一个）
  Future<List<String>> recognizeText(Uint8List imageBytes);

  /// 从图片文件路径中识别文字
  Future<List<String>> recognizeTextFromFile(String imagePath);

  /// 释放资源
  void dispose();
}
