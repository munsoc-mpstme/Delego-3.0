import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Where the sponsor's video goes. Drop the file here (same name) and rebuild:
///   assets/videos/sponsor_video.mp4
/// Until the file exists the Sponsors page shows a "coming soon" placeholder.
const kSponsorVideoAsset = 'assets/videos/sponsor_video.mp4';

/// Video card shown at the top of the Sponsors page. Tap to play / pause.
class SponsorVideoCard extends StatefulWidget {
  const SponsorVideoCard({super.key});

  @override
  State<SponsorVideoCard> createState() => _SponsorVideoCardState();
}

class _SponsorVideoCardState extends State<SponsorVideoCard> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.asset(kSponsorVideoAsset);
    try {
      await c.initialize(); // throws if the file is not there yet
      await c.setLooping(true);
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.addListener(() {
        if (mounted) setState(() {}); // keep the play icon / progress in sync
      });
      setState(() => _controller = c);
    } catch (_) {
      await c.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = _controller;

    Widget body;
    if (c != null && c.value.isInitialized) {
      body = GestureDetector(
        onTap: () => c.value.isPlaying ? c.pause() : c.play(),
        child: AspectRatio(
          aspectRatio: c.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(c),
              if (!c.value.isPlaying)
                Container(
                  decoration: const BoxDecoration(
                      color: Colors.black45, shape: BoxShape.circle),
                  padding: const EdgeInsets.all(12),
                  child: const Icon(Icons.play_arrow,
                      color: Colors.white, size: 48),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: VideoProgressIndicator(c, allowScrubbing: true),
              ),
            ],
          ),
        ),
      );
    } else {
      // Placeholder: still loading, or the video file has not been added yet.
      body = AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: scheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: _failed
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.movie_outlined,
                        size: 48, color: scheme.onSurface.withValues(alpha: 0.5)),
                    const SizedBox(height: 8),
                    Text('Sponsor video coming soon',
                        style: TextStyle(
                            color: scheme.onSurface.withValues(alpha: 0.7))),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: body,
    );
  }
}
