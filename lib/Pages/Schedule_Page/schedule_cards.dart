import 'package:flutter/material.dart';
import 'package:delego/models/schedule.dart';
import 'package:delego/constants/fonts.dart';
import 'package:delego/constants/text_style.dart';
import 'package:delego/constants/separator.dart';
import 'package:delego/Pages/Schedule_Page/schedule_details.dart';

class ScheduleSummary extends StatelessWidget {
  final Schedule schedule;
  final bool horizontal;

  const ScheduleSummary(this.schedule, {this.horizontal = true, Key? key})
      : super(key: key);

  const ScheduleSummary.vertical(this.schedule, {Key? key})
      : horizontal = false,
        super(key: key);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    /// Thumbnail (Hero animation)
    final scheduleThumbnail = Hero(
      tag: "schedule-hero-${schedule.id}",
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: Image.network(
          schedule.imageUrl,
          height: 92.0,
          width: 92.0,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            height: 92.0,
            width: 92.0,
            color: scheme.surfaceContainerHighest,
            child: Icon(Icons.image_not_supported,
                color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );

    /// Time / icon row
    Widget _scheduleValue({required String value, required IconData icon}) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: scheme.onPrimary, size: 16.0),
          const SizedBox(width: 6.0),
          Text(
            value,
            style: TextStyle(
              fontFamily: AppFontFamilies.mainFont,
              fontSize: 13,
              color: scheme.onPrimary,
            ),
          ),
        ],
      );
    }

    /// Card content
    final scheduleCardContent = Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment:
        horizontal ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            schedule.name ?? '',
            style: Style.titleTextStyle.copyWith(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4.0),
          Text(
            schedule.location ?? '',
            style: Style.commonTextStyle.copyWith(
              color: scheme.onPrimary.withValues(alpha: 0.8),
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6.0),
          Separator(color: scheme.onPrimary.withValues(alpha: 0.2)),
          const SizedBox(height: 6.0),
          _scheduleValue(
            value: schedule.time ?? '',
            icon: Icons.access_time_filled_rounded,
          ),
        ],
      ),
    );

    /// Full card layout
    final scheduleCard = Container(
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.2),
            blurRadius: 8.0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: scheduleCardContent,
    );

    /// Combine thumbnail + card (different layout for horizontal vs vertical)
    final Widget cardLayout = horizontal
        ? Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        scheduleThumbnail,
        const SizedBox(width: 16),
        Expanded(child: scheduleCard),
      ],
    )
        : Column(
      children: [
        scheduleThumbnail,
        const SizedBox(height: 12),
        scheduleCard,
      ],
    );

    return GestureDetector(
      onTap: horizontal
          ? () {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => DetailPage(schedule),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        );
      }
          : null,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 20.0),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12.0),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            splashColor: scheme.onPrimary.withValues(alpha: 0.1),
            onTap: horizontal
                ? () {
              Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => DetailPage(schedule),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) =>
                      FadeTransition(opacity: animation, child: child),
                ),
              );
            }
                : null,
            child: cardLayout,
          ),
        ),
      ),
    );
  }
}
