import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:delego/constants/sponsors.dart';

/// A row of sponsor logos that drifts sideways forever. It pauses while a finger is on
/// it, opens [onTap] when tapped, and holds still if the phone has animations turned
/// off (the logos are then laid out in a wrapped, centred group instead).
class SponsorMarquee extends StatefulWidget {
  const SponsorMarquee({
    super.key,
    this.onTap,
    this.speed = 36, // logical pixels per second
    this.height = 64,
  });

  final VoidCallback? onTap;
  final double speed;
  final double height;

  @override
  State<SponsorMarquee> createState() => _SponsorMarqueeState();
}

class _SponsorMarqueeState extends State<SponsorMarquee>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration now) {
    final dt = (now - _last).inMicroseconds / Duration.microsecondsPerSecond;
    _last = now;
    if (_paused || !_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.offset + widget.speed * dt);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Widget _logo(String asset) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Image.asset(
        asset,
        height: widget.height - 24,
        fit: BoxFit.contain,
        cacheHeight: 160,
        excludeFromSemantics: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;

    final Widget body = still
        ? Wrap(
            alignment: WrapAlignment.center,
            runSpacing: 8,
            children: [for (final s in kSponsors) _logo(s)],
          )
        : SizedBox(
            height: widget.height,
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => const LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.black,
                  Colors.black,
                  Colors.transparent,
                ],
                stops: [0, 0.08, 0.92, 1],
              ).createShader(rect),
              child: Listener(
                onPointerDown: (_) => _paused = true,
                onPointerUp: (_) => _paused = false,
                onPointerCancel: (_) => _paused = false,
                child: ListView.builder(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  // No itemCount: the list repeats the sponsors for as long as it runs.
                  itemBuilder: (_, i) => _logo(kSponsors[i % kSponsors.length]),
                ),
              ),
            ),
          );

    return Semantics(
      button: widget.onTap != null,
      label: 'Our sponsors. Tap to see all.',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: body,
        ),
      ),
    );
  }
}
