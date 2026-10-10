import 'package:delego/widgets/mun_logo.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:delego/widgets/neon.dart';

class QrCode extends StatefulWidget {
  const QrCode({super.key});

  @override
  State<QrCode> createState() => _QrCodeState();
}

class _QrCodeState extends State<QrCode> {
  String? _id;
  String _name = '';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Saved at login, so the badge still works with no connection.
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final id = prefs.getString('id');
    final first = prefs.getString('firstname') ?? '';
    final last = prefs.getString('lastname') ?? '';
    setState(() {
      _id = (id == null || id.isEmpty) ? null : id;
      _name = '$first $last'.trim();
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(centerTitle: false, title: const Text('My QR Badge')),
      body: !_loaded
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text('DELEGATE PASS',
                    style: Neon.label(scheme.onSurface.withValues(alpha: 0.5),
                        size: 11, spacing: 3)),
                const SizedBox(height: 6),
                Text('Food QR Code',
                    style: TextStyle(
                      fontFamily: Neon.font,
                      fontWeight: FontWeight.w700,
                      fontSize: 28,
                      color: scheme.onSurface,
                    )),
                const SizedBox(height: 20),
                if (_id == null)
                  _Empty(scheme: scheme)
                else
                  _Ticket(id: _id!, name: _name),
              ],
            ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Icon(Icons.qr_code_rounded,
              size: 90, color: scheme.onSurface.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text('No QR code available.',
              style: TextStyle(
                  fontFamily: Neon.font,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: scheme.onSurface)),
          const SizedBox(height: 8),
          Text('Sign in again, or contact the Organizing Committee.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6))),
        ],
      ),
    );
  }
}

/// Clips one half of the ticket: rounded outer corners, semicircle bites where the
/// two halves meet.
class _HalfClipper extends CustomClipper<Path> {
  _HalfClipper({required this.top});
  final bool top;

  static const _r = 26.0;
  static const _notch = 14.0;

  @override
  Path getClip(Size s) {
    final rect = top
        ? RRect.fromRectAndCorners(Offset.zero & s,
            topLeft: const Radius.circular(_r),
            topRight: const Radius.circular(_r))
        : RRect.fromRectAndCorners(Offset.zero & s,
            bottomLeft: const Radius.circular(_r),
            bottomRight: const Radius.circular(_r));
    var path = Path()..addRRect(rect);
    final y = top ? s.height : 0.0;
    for (final x in [0.0, s.width]) {
      path = Path.combine(
          PathOperation.difference,
          path,
          Path()
            ..addOval(Rect.fromCircle(center: Offset(x, y), radius: _notch)));
    }
    return path;
  }

  @override
  bool shouldReclip(_HalfClipper old) => old.top != top;
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (double x = 22; x < size.width - 22; x += 12) {
      canvas.drawLine(Offset(x, 1), Offset(x + 6, 1), p);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

class _Ticket extends StatelessWidget {
  const _Ticket({required this.id, required this.name});
  final String id;
  final String name;

  @override
  Widget build(BuildContext context) {
    final sw = swatchFor(id);
    final mid = Color.lerp(sw.colors.first, sw.colors.last, 0.5)!;
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();

    Widget texture(Widget child, int seed) => Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter:
                    GridPainter(color: Colors.black.withValues(alpha: 0.08)),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: RingsPainter(
                    color: sw.accent.withValues(alpha: 0.55),
                    count: 10,
                    seed: seed),
              ),
            ),
            child,
          ],
        );

    final top = ClipPath(
      clipper: _HalfClipper(top: true),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [sw.colors.first, mid],
          ),
        ),
        child: texture(
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('DELEGATE PASS',
                          style: Neon.label(sw.accent, size: 11, spacing: 3)),
                    ),
                    MunLogoLink(
                      child: Image.asset('assets/images/logo_solid.webp',
                          height: 26,
                          color: sw.accent,
                          colorBlendMode: BlendMode.srcIn),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: sw.accent, width: 2),
                      ),
                      child: Text(initial,
                          style: Neon.label(sw.accent, size: 18, spacing: 0)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        name.isEmpty ? 'Delegate' : name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: Neon.font,
                          fontWeight: FontWeight.w700,
                          fontSize: 21,
                          color: sw.nameColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          2,
        ),
      ),
    );

    final bottom = ClipPath(
      clipper: _HalfClipper(top: false),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [mid, sw.colors.last],
          ),
        ),
        child: texture(
          Stack(
            fit: StackFit.passthrough,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 2,
                child: CustomPaint(painter: _DashPainter(sw.accent)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
                child: Column(
                  children: [
                    Text('SHOW THIS AT THE FOOD COUNTER',
                        textAlign: TextAlign.center,
                        style: Neon.label(sw.accent, size: 11, spacing: 2.5)),
                    const SizedBox(height: 16),
                    // White plate + dark modules keep the code readable by the
                    // scanner; only the finder squares carry the ticket colour.
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Semantics(
                        label: 'Your food QR code',
                        child: QrImageView(
                          data: id,
                          size: 176,
                          padding: EdgeInsets.zero,
                          backgroundColor: Colors.white,
                          errorCorrectionLevel: QrErrorCorrectLevel.Q,
                          eyeStyle: QrEyeStyle(
                            eyeShape: QrEyeShape.circle,
                            color: sw.eye,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.circle,
                            color: Color(0xFF111111),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('ID: $id',
                        style: TextStyle(
                          fontFamily: 'RobotoMono',
                          fontSize: 12,
                          letterSpacing: 1,
                          color: sw.accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Bon appétit! Enjoy your meal',
                        style: TextStyle(
                          fontFamily: Neon.font,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          color: sw.nameColor,
                        )),
                  ],
                ),
              ),
            ],
          ),
          9,
        ),
      ),
    );

    // stretch: both halves must take the full width, not the width of their content.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [top, bottom],
    );
  }
}
