import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Where every Mumbai MUN logo in the app leads.
const kMumbaiMunInstagram = 'https://www.instagram.com/mumbaimun/';

Future<void> openMumbaiMunInstagram(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final ok = await launchUrl(
      Uri.parse(kMumbaiMunInstagram),
      mode: LaunchMode.externalApplication, // opens the Instagram app if installed
    );
    if (!ok) {
      messenger?.showSnackBar(
          const SnackBar(content: Text('Could not open Instagram.')));
    }
  } catch (_) {
    messenger?.showSnackBar(
        const SnackBar(content: Text('Could not open Instagram.')));
  }
}

/// Wrap any Mumbai MUN logo (or banner) with this to make it open the
/// Mumbai MUN Instagram page when tapped.
class MunLogoLink extends StatelessWidget {
  const MunLogoLink({super.key, required this.child, this.borderRadius});

  final Widget child;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open Mumbai MUN on Instagram',
      child: InkWell(
        borderRadius: borderRadius,
        onTap: () => openMumbaiMunInstagram(context),
        child: child,
      ),
    );
  }
}
