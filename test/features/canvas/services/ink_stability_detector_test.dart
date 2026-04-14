import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/features/canvas/services/ink_stability_detector.dart';

void main() {
  group('InkStabilityDetector', () {
    test('emits stable region after idle threshold elapses', () async {
      final detector = InkStabilityDetector(
        idleThreshold: const Duration(milliseconds: 100),
      );

      final regions = <StableRegion>[];
      detector.onRegionStabilized.listen(regions.add);

      detector.registerStrokeBounds(Rect.fromLTWH(10, 10, 20, 20));

      // Wait longer than idle threshold
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(regions, hasLength(1));
      expect(regions.first.bounds, equals(Rect.fromLTWH(10, 10, 20, 20)));
    });

    test('resets timer when new stroke arrives before threshold', () async {
      final detector = InkStabilityDetector(
        idleThreshold: const Duration(milliseconds: 100),
      );

      final regions = <StableRegion>[];
      detector.onRegionStabilized.listen(regions.add);

      detector.registerStrokeBounds(Rect.fromLTWH(10, 10, 20, 20));

      // Arrives before threshold - should reset timer
      await Future<void>.delayed(const Duration(milliseconds: 50));
      detector.registerStrokeBounds(Rect.fromLTWH(50, 50, 10, 10));

      // Wait past original threshold but within new one
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(regions, isEmpty);

      // Now wait past the reset threshold
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(regions, hasLength(1));
      // Bounds should be the union of both strokes
      expect(
        regions.first.bounds,
        equals(Rect.fromLTWH(10, 10, 50, 50)),
      );
    });

    test('does not emit if detector is disposed before threshold', () async {
      final detector = InkStabilityDetector(
        idleThreshold: const Duration(milliseconds: 100),
      );

      final regions = <StableRegion>[];
      detector.onRegionStabilized.listen(regions.add);

      detector.registerStrokeBounds(Rect.fromLTWH(10, 10, 20, 20));
      detector.dispose();

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(regions, isEmpty);
    });
  });
}
