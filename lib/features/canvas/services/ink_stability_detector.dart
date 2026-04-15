import 'dart:async';

import 'package:flutter/material.dart';

class StableRegion {
  final Rect bounds;
  final DateTime stableAt;

  const StableRegion({required this.bounds, required this.stableAt});
}

class InkStabilityDetector {
  final Duration idleThreshold;
  Timer? _timer;
  Rect? _pendingBounds;
  final _controller = StreamController<StableRegion>.broadcast();

  InkStabilityDetector(
      {this.idleThreshold = const Duration(milliseconds: 1500)});

  Stream<StableRegion> get onRegionStabilized => _controller.stream;

  void registerStrokeBounds(Rect bounds) {
    _pendingBounds = _pendingBounds == null
        ? bounds
        : _pendingBounds!.expandToInclude(bounds);
    _timer?.cancel();
    _timer = Timer(idleThreshold, () {
      final region = _pendingBounds;
      if (region != null) {
        _controller.add(StableRegion(bounds: region, stableAt: DateTime.now()));
      }
      _pendingBounds = null;
    });
  }

  void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}
