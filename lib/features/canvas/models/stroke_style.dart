enum StrokeStyle {
  pen(opacity: 1, widthMultiplier: 1),
  brush(opacity: 1, widthMultiplier: 1.4),
  highlighter(opacity: 0.35, widthMultiplier: 2.4),
  pencil(opacity: 0.7, widthMultiplier: 0.8);

  final double opacity;
  final double widthMultiplier;

  const StrokeStyle({required this.opacity, required this.widthMultiplier});
}
