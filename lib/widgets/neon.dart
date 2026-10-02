import 'dart:math' as math;

import 'package:flutter/material.dart';

/// MumbaiMUN '26 palette, taken from the poster set.
class Neon {
  static const black = Color(0xFF0A0A0A); // matte black, dark-mode surface
  static const navy = Color(0xFF080824);
  static const navy2 = Color(0xFF12123A);
  static const blue = Color(0xFF2342FF);
  static const lime = Color(0xFFB6FF1A);
  static const pink = Color(0xFFF01DB0);
  static const yellow = Color(0xFFFFF21A);
  static const orange = Color(0xFFFF4A22);
  static const green = Color(0xFF22C98A);
  static const cyan = Color(0xFF2AF5E0);
  static const violet = Color(0xFF7A1BFF);

  static const font = 'Rubik';

  /// Wide, tracked, heavy label used on cards and section tags.
  static TextStyle label(Color color, {double size = 16, double spacing = 0.6}) =>
      TextStyle(
        fontFamily: font,
        fontWeight: FontWeight.w900,
        fontSize: size,
        letterSpacing: spacing,
        height: 1.05,
        color: color,
      );
}

/// Faint square grid, like the halftone texture on the posters.
class GridPainter extends CustomPainter {
  GridPainter({required this.color, this.step = 12});
  final Color color;
  final double step;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 0.6;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(GridPainter old) => old.color != color || old.step != step;
}

/// Scattered outlined rings (the "o o o" dot motif).
class RingsPainter extends CustomPainter {
  RingsPainter({required this.color, this.count = 26, this.seed = 1, this.radius = 3.4});
  final Color color;
  final int count;
  final int seed;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var i = 0; i < count; i++) {
      canvas.drawCircle(
        Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
        radius,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(RingsPainter old) =>
      old.color != color || old.count != count || old.seed != seed;
}

/// Gradient tile with grid + rings texture, a tracked heavy label and a tinted icon.
class NeonCard extends StatelessWidget {
  const NeonCard({
    super.key,
    required this.colors,
    required this.label,
    required this.labelColor,
    required this.onTap,
    this.iconAsset,
    this.height = 150,
    this.seed = 1,
    this.wide = false,
  });

  final List<Color> colors;
  final String label;
  final Color labelColor;
  final VoidCallback onTap;
  final String? iconAsset;
  final double height;
  final int seed;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label.replaceAll('\n', ' '),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Ink(
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
              boxShadow: [
                BoxShadow(
                  color: colors.last.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: GridPainter(color: Colors.black.withValues(alpha: 0.10)),
                    ),
                  ),
                  if (iconAsset != null)
                    Positioned(
                      right: 14,
                      bottom: 14,
                      child: Image.asset(
                        iconAsset!,
                        width: wide ? 54 : 72,
                        height: wide ? 54 : 72,
                        color: Colors.black.withValues(alpha: 0.55),
                        colorBlendMode: BlendMode.srcIn,
                      ),
                    ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: RingsPainter(
                        color: labelColor.withValues(alpha: 0.85),
                        count: wide ? 22 : 16,
                        seed: seed,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Align(
                      alignment: wide ? Alignment.centerLeft : Alignment.topLeft,
                      child: Text(
                        label.toUpperCase(),
                        style: Neon.label(labelColor, size: wide ? 18 : 17),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Home hero: pink gradient card, the Gateway of India from the official banner
/// zoomed in on the right, event title drawn on the left.
class HeroBanner extends StatelessWidget {
  const HeroBanner({super.key});

  static const _height = 210.0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Mumbai MUN 2026. An Axiom Apart.',
      child: Container(
        height: _height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFF2BB4), Color(0xFFB0239B), Color(0xFF4A3358)],
          ),
          boxShadow: [
            BoxShadow(
              color: Neon.pink.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: GridPainter(
                      color: Colors.black.withValues(alpha: 0.12), step: 10),
                ),
              ),
              // Zoomed crop of the banner: show only its rightmost part.
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 270,
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) => const LinearGradient(
                    colors: [Colors.transparent, Colors.black],
                    stops: [0, 0.3],
                  ).createShader(rect),
                  child: ClipRect(
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: Image.asset(
                        'assets/images/banner_2026.webp',
                        height: _height * 1.12,
                        fit: BoxFit.fitHeight,
                        alignment: Alignment.bottomRight,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MUMBAI MUN',
                          style: Neon.label(Neon.yellow, size: 13, spacing: 3)),
                      const SizedBox(height: 4),
                      const Text(
                        '2026',
                        style: TextStyle(
                          fontFamily: Neon.font,
                          fontWeight: FontWeight.w900,
                          fontSize: 54,
                          height: 1,
                          letterSpacing: -1,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('AN AXIOM APART',
                          style: Neon.label(Colors.white, size: 11, spacing: 3)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size s) {
    final w = s.width, h = s.height;
    const r = 14.0;
    final tabH = h * 0.11, tabW = w * 0.40, slope = w * 0.09;
    return Path()
      ..moveTo(r, 0)
      ..lineTo(tabW, 0)
      ..lineTo(tabW + slope, tabH)
      ..lineTo(w - r, tabH)
      ..quadraticBezierTo(w, tabH, w, tabH + r)
      ..lineTo(w, h - r)
      ..quadraticBezierTo(w, h, w - r, h)
      ..lineTo(r, h)
      ..quadraticBezierTo(0, h, 0, h - r)
      ..lineTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..close();
  }

  @override
  bool shouldReclip(_FolderClipper old) => false;
}

/// Folder-shaped button. The cover artwork already carries the title, so the card
/// only adds a small tag ("PDF" / "SOON") in the corner.
class FolderCard extends StatelessWidget {
  const FolderCard({
    super.key,
    required this.title,
    required this.cover,
    required this.onTap,
    this.tag = 'PDF',
  });

  final String title;
  final String cover; // asset path
  final VoidCallback onTap;
  final String tag;

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(color: Color(0xAA000000), blurRadius: 6)];
    return Semantics(
      button: true,
      label: '$title study guide, $tag',
      child: AspectRatio(
        aspectRatio: 1.0,
        child: ClipPath(
          clipper: _FolderClipper(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: Colors.black),
              Image.asset(cover, fit: BoxFit.cover, cacheWidth: 700),
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 14, 12),
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: Text(
                        tag,
                        style: const TextStyle(
                          fontFamily: Neon.font,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 1,
                          color: Colors.white,
                          shadows: shadow,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the four poster colourways, used where a person or item gets "a colour".
class NeonSwatch {
  const NeonSwatch({
    required this.colors,
    required this.accent,
    required this.eye,
    required this.nameColor,
  });

  final List<Color> colors; // top -> bottom background
  final Color accent; // labels, rings, icons
  final Color eye; // QR finder-pattern colour (dark enough to scan on white)
  final Color nameColor;
}

const kSwatches = <NeonSwatch>[
  // lime / orange
  NeonSwatch(
    colors: [Color(0xFFD9FF1F), Color(0xFF8BC400)],
    accent: Neon.orange,
    eye: Color(0xFFE5400F),
    nameColor: Color(0xFF1A1A1A),
  ),
  // pink / yellow
  NeonSwatch(
    colors: [Color(0xFFFF2BB4), Color(0xFFB51E9A)],
    accent: Neon.yellow,
    eye: Color(0xFFB51E9A),
    nameColor: Colors.white,
  ),
  // blue / lime
  NeonSwatch(
    colors: [Color(0xFF2F55FF), Color(0xFF1226A8)],
    accent: Neon.lime,
    eye: Color(0xFF1F3FE0),
    nameColor: Colors.white,
  ),
  // green / cyan
  NeonSwatch(
    colors: [Color(0xFF22D38F), Color(0xFF1B8F63)],
    accent: Neon.cyan,
    eye: Color(0xFF14805A),
    nameColor: Colors.white,
  ),
];

/// Stable pick: the same id always gets the same colourway, ids spread evenly.
NeonSwatch swatchFor(String key) {
  var h = 0;
  for (final c in key.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return kSwatches[h % kSwatches.length];
}
