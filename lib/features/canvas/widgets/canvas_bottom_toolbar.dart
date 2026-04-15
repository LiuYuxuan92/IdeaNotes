import 'package:flutter/material.dart';

class CanvasBottomToolbar extends StatelessWidget {
  final Widget child;

  const CanvasBottomToolbar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: child,
    );
  }
}
