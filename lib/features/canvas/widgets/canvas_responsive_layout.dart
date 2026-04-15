import 'package:flutter/material.dart';

class CanvasResponsiveLayout extends StatelessWidget {
  final Widget stage;
  final Widget toolbar;
  final Widget overlay;

  const CanvasResponsiveLayout({
    super.key,
    required this.stage,
    required this.toolbar,
    required this.overlay,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        stage,
        overlay,
        toolbar,
      ],
    );
  }
}
