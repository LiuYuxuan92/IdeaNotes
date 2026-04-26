import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../features/canvas/canvas_screen.dart';

/// 监听系统分享 intent（其他 App "分享" 出来的文本），收到后跳到新建笔记页并预填文本。
///
/// 用法（在 root widget 的 initState 里调用一次）：
/// ```dart
/// final handler = ShareIntentHandler(navigatorKey: _navKey)..start();
/// ```
class ShareIntentHandler {
  final GlobalKey<NavigatorState> navigatorKey;
  StreamSubscription<List<SharedMediaFile>>? _streamSub;

  ShareIntentHandler({required this.navigatorKey});

  /// 注册冷启动 + 热运行两条管道。
  void start() {
    // 冷启动：APP 通过分享被打开
    ReceiveSharingIntent.instance.getInitialMedia().then((media) {
      _handleMedia(media, fromInitial: true);
      // 关键：消费掉，避免每次切回都重复触发
      ReceiveSharingIntent.instance.reset();
    }).catchError((Object _) {});

    // 热运行：APP 已开着，用户分享过来
    _streamSub = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen((media) => _handleMedia(media, fromInitial: false))
      ..onError((Object _) {});
  }

  void dispose() {
    _streamSub?.cancel();
    _streamSub = null;
  }

  void _handleMedia(List<SharedMediaFile> media, {required bool fromInitial}) {
    if (media.isEmpty) return;
    final text = _extractText(media);
    if (text == null || text.trim().isEmpty) return;

    // 等导航器就绪后再 push（冷启动时 navigatorKey 可能还没挂上）
    void doPush() {
      final navigator = navigatorKey.currentState;
      if (navigator == null) {
        // 再等一帧
        WidgetsBinding.instance.addPostFrameCallback((_) => doPush());
        return;
      }
      navigator.push(
        PageRouteBuilder<void>(
          pageBuilder: (_, __, ___) =>
              CanvasScreen(initialOcrText: text.trim()),
          transitionDuration: const Duration(milliseconds: 240),
        ),
      );
    }

    if (fromInitial) {
      WidgetsBinding.instance.addPostFrameCallback((_) => doPush());
    } else {
      doPush();
    }
  }

  /// receive_sharing_intent 把分享文本放在 SharedMediaFile.path（type=text 时）
  String? _extractText(List<SharedMediaFile> media) {
    for (final m in media) {
      if (m.type == SharedMediaType.text || m.type == SharedMediaType.url) {
        return m.path;
      }
      if (m.message != null && m.message!.trim().isNotEmpty) {
        return m.message;
      }
    }
    return null;
  }
}
