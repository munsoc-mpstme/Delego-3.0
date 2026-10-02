import 'package:flutter/material.dart';

class MyListTile extends StatelessWidget {
  final IconData icon;
  final String text;
  final void Function()? onTap;
  final Widget? trailing;

  const MyListTile({
    Key? key,
    required this.icon,
    required this.text,
    required this.onTap,
    this.trailing,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 20, 12),
        child: Row(
          children: [
            Icon(icon, color: scheme.tertiary),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                text,
                style: textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
