import 'package:delego/Pages/Schedule_Page/schedule_cards.dart';
import 'package:flutter/material.dart';
import 'package:delego/models/schedule.dart';
import 'package:delego/constants/separator.dart';
import 'package:delego/constants/text_style.dart';

class DetailPage extends StatelessWidget {
  final Schedule schedule;
  DetailPage(this.schedule);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Container(
        constraints: BoxConstraints.expand(),
        color: scheme.primary,
        child: Stack(
          children: <Widget>[
            _getBackground(),
            _getGradient(scheme),
            _getContent(context, scheme, textTheme),
            _getToolbar(context, scheme),
          ],
        ),
      ),
    );
  }

  Container _getBackground() {
    return Container(
      child: Image.network(
        schedule.imageUrl,
        fit: BoxFit.cover,
        height: 300.0,
      ),
      constraints: const BoxConstraints.expand(height: 295.0),
    );
  }

  Container _getGradient(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.only(top: 190.0),
      height: 110.0,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary.withValues(alpha: 0.0),
            scheme.primary.withValues(alpha: 0.95),
          ],
          stops: [0.0, 0.9],
          begin: FractionalOffset.topCenter,
          end: FractionalOffset.bottomCenter,
        ),
      ),
    );
  }

  Container _getContent(BuildContext context, ColorScheme scheme, TextTheme textTheme) {
    final _overviewTitle = "Overview".toUpperCase();
    return Container(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0.0, 72.0, 0.0, 20.0),
        children: <Widget>[
          ScheduleSummary(
            schedule,
            horizontal: false,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _overviewTitle,
                  style: textTheme.titleMedium?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Separator(),
                Text(
                  schedule.description ?? '',
                  style: textTheme.bodyLarge?.copyWith(
                    color: scheme.onPrimary.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Container _getToolbar(BuildContext context, ColorScheme scheme) {
    return Container(
      margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      child: BackButton(color: scheme.onPrimary),
    );
  }
}
