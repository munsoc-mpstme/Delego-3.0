import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:delego/constants/backend.dart';
import 'package:delego/models/schedule.dart';
import 'package:delego/models/schedule_now.dart';
import 'package:delego/widgets/neon.dart';

String formatClock(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// The words (and colourway) for one moment, kept separate from the widget so the
/// wording can be tested without loading anything.
class NowText {
  const NowText(
    this.label,
    this.title,
    this.subtitle, {
    this.live = false,
    this.colors = const [Color(0xFF2F55FF), Color(0xFF1226A8)],
    this.accent = Neon.lime,
  });

  final String label;
  final String title;
  final String subtitle;
  final bool live;
  final List<Color> colors; // tile gradient, top-left to bottom-right
  final Color accent; // all text, rings and the dot, like the home tiles
}

// Same pairings as the home tiles.
const _lime = [Color(0xFFD9FF1F), Color(0xFF8BC400)]; // orange text
const _pink = [Color(0xFFFF2BB4), Color(0xFFB51E9A)]; // yellow text
const _blue = [Color(0xFF2F55FF), Color(0xFF1226A8)]; // lime text
const _green = [Color(0xFF22D38F), Color(0xFF1B8F63)]; // cyan text
const _violet = [Neon.violet, Neon.blue]; // yellow text (the Scan tile)

NowText describeNow(NowStatus s, DateTime now) {
  String where(TimedEvent e) => e.event.location;

  switch (s.kind) {
    case NowKind.live:
      final first = s.events.first;
      final more = s.events.length > 1 ? '  +${s.events.length - 1} more' : '';
      return NowText(
        'HAPPENING NOW',
        '${first.event.name}$more',
        '${where(first)} · ${formatClock(first.start)} – ${formatClock(first.end)}',
        live: true,
        colors: _lime,
        accent: Neon.orange,
      );
    case NowKind.upNext:
      final n = s.next!;
      final mins = n.start.difference(now).inMinutes;
      final when = mins < 60 ? 'starts in ${mins < 1 ? 1 : mins} min' : 'at ${formatClock(n.start)}';
      return NowText('UP NEXT', n.event.name, '${where(n)} · $when',
          colors: _blue, accent: Neon.lime);
    case NowKind.beforeEvent:
      final d = s.daysToGo;
      final n = s.next!;
      return NowText(
        'COMING UP',
        d == 1 ? 'Mumbai MUN starts tomorrow' : 'Mumbai MUN starts in $d days',
        'First up: ${n.event.name} · ${formatClock(n.start)}',
        colors: _violet,
        accent: Neon.yellow,
      );
    case NowKind.wrappedForToday:
      final n = s.next!;
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final sameAsTomorrow = n.start.year == tomorrow.year &&
          n.start.month == tomorrow.month &&
          n.start.day == tomorrow.day;
      return NowText(
        'THAT\'S A WRAP FOR TODAY',
        sameAsTomorrow ? 'See you tomorrow' : 'See you at the next session',
        '${sameAsTomorrow ? 'Tomorrow' : n.event.day}: ${n.event.name} · ${formatClock(n.start)}',
        colors: _green,
        accent: Neon.cyan,
      );
    case NowKind.over:
      return const NowText('MUMBAI MUN 2026', 'Thank you for being part of it',
          'An Axiom Apart',
          colors: _pink, accent: Neon.yellow);
  }
}

/// Presentation only: a slim tile in the same style as the home tiles (gradient, grid,
/// rings, heavy tracked type in the tile's accent colour).
class NowStripView extends StatelessWidget {
  const NowStripView({super.key, required this.text, this.onTap});

  final NowText text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = text.accent;

    return Semantics(
      button: onTap != null,
      label: '${text.label}. ${text.title}. ${text.subtitle}. Tap for the full schedule.',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: text.colors,
                ),
                boxShadow: [
                  BoxShadow(
                    color: text.colors.last.withValues(alpha: 0.35),
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
                    // Rings stay in a patch at the right edge, clear of the words, so the
                    // text never has to compete with them.
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: 40, // exactly the arrow zone: the text column ends where this starts
                      child: CustomPaint(
                        painter: RingsPainter(
                          color: accent.withValues(alpha: 0.7),
                          count: 4,
                          seed: 21,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Row(
                        children: [
                          _Dot(color: accent, pulse: text.live),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(text.label,
                                    style: Neon.label(accent, size: 10.5, spacing: 2.5)),
                                const SizedBox(height: 4),
                                Text(
                                  text.title.toUpperCase(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Neon.label(accent, size: 16),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  text.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: Neon.font,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12.5,
                                    color: accent.withValues(alpha: 0.9),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_rounded,
                              color: Colors.black.withValues(alpha: 0.55)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  const _Dot({required this.color, required this.pulse});
  final Color color;
  final bool pulse;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.of(context).disableAnimations;
    if (widget.pulse && !still) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Stack(
          alignment: Alignment.center,
          children: [
            if (widget.pulse)
              Container(
                width: 10 + 12 * _c.value,
                height: 10 + 12 * _c.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.4 * (1 - _c.value)),
                ),
              ),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Loads the public schedule (saved copy first, so it works offline) and shows what is
/// happening now. Shows nothing until it has a schedule it can read.
class NowStrip extends StatefulWidget {
  const NowStrip({super.key, this.onTap, this.clock});

  final VoidCallback? onTap;

  /// Replaceable in tests.
  final DateTime Function()? clock;

  @override
  State<NowStrip> createState() => _NowStripState();
}

class _NowStripState extends State<NowStrip> {
  // Same keys as the Schedule page, so the two share one saved copy.
  static const _cacheKey = 'fullScheduleData';
  static const _timestampKey = 'fullScheduleTimestamp';

  List<TimedEvent> _events = [];
  Timer? _tick;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _load();
    // Re-check the clock so "happening now" moves on without reopening the app.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  bool _apply(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final days = (data['conference_days'] as List)
          .map((j) => ConferenceDay.fromJson(j as Map<String, dynamic>))
          .toList();
      final events = (data['events'] as List)
          .map((j) => Schedule.fromJson(j as Map<String, dynamic>))
          .toList();
      if (!mounted) return true;
      setState(() => _events = timeEvents(days, events));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    if (cached != null) _apply(cached); // show something straight away

    try {
      final res = await http
          .get(Uri.parse('${Backend.baseUrl}/schedule'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && _apply(res.body)) {
        await prefs.setString(_cacheKey, res.body);
        await prefs.setInt(_timestampKey, DateTime.now().millisecondsSinceEpoch);
      }
    } catch (_) {
      // Offline: the saved copy (if any) is already on screen.
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = _now;
    final status = computeNow(_events, now);
    if (status == null) return const SizedBox(height: 26);
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 22),
      child: NowStripView(text: describeNow(status, now), onTap: widget.onTap),
    );
  }
}
