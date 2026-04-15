import 'package:flutter/material.dart';

class CanvasStage extends StatelessWidget {
  final Widget painter;

  const CanvasStage({super.key, required this.painter});

  @override
  Widget build(BuildContext context) => RepaintBoundary(child: painter);
}
