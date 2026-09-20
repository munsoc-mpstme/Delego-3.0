import 'package:flutter/material.dart';

class Separator extends StatelessWidget {
  final double height;
  final double width;
  final Color? color;
  final EdgeInsetsGeometry margin;

  const Separator({
    Key? key,
    this.height = 2.0,
    this.width = 24.0,
    this.color,
    this.margin = const EdgeInsets.symmetric(vertical: 8.0),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: margin,
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: color ?? scheme.primary.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}
