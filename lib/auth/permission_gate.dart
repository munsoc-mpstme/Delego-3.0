import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'capabilities.dart';

/// Shows [child] only to users who hold at least one of [anyOf]; everyone else gets a
/// plain "no access" screen. It watches [Capabilities], so a role change applies
/// straight away. The server enforces the same rules; this just avoids a dead screen.
class PermissionGate extends StatelessWidget {
  const PermissionGate({
    super.key,
    required this.anyOf,
    required this.child,
    this.title = 'No access',
  });

  final List<String> anyOf;
  final Widget child;
  final String title;

  @override
  Widget build(BuildContext context) {
    final caps = context.watch<Capabilities>();
    if (anyOf.any(caps.can)) return child;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 56),
              const SizedBox(height: 16),
              const Text('You do not have access to this screen.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
