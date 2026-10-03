import 'package:delego/constants/sponsors.dart';
import 'package:delego/widgets/sponsor_marquee.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host({required bool disableAnimations, VoidCallback? onTap}) => MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MaterialApp(
        home: Scaffold(body: SponsorMarquee(onTap: onTap)),
      ),
    );

void main() {
  testWidgets('keeps drifting sideways while running', (tester) async {
    await tester.pumpWidget(host(disableAnimations: false));
    await tester.pump(const Duration(milliseconds: 100));
    final first = tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

    await tester.pump(const Duration(seconds: 2));
    final later = tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

    expect(later, greaterThan(first + 30));
  });

  testWidgets('stops while a finger is down and resumes after', (tester) async {
    await tester.pumpWidget(host(disableAnimations: false));
    await tester.pump(const Duration(milliseconds: 100));
    double offset() =>
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

    final gesture = await tester.startGesture(tester.getCenter(find.byType(SponsorMarquee)));
    await tester.pump(const Duration(milliseconds: 50));
    final held = offset();
    await tester.pump(const Duration(seconds: 1));
    expect(offset(), held);

    await gesture.up();
    await tester.pump(const Duration(seconds: 1));
    expect(offset(), greaterThan(held));
  });

  testWidgets('tapping it calls onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(disableAnimations: false, onTap: () => taps++));
    await tester.tap(find.byType(SponsorMarquee));
    expect(taps, 1);
  });

  testWidgets('with animations off it is static and shows every sponsor',
      (tester) async {
    await tester.pumpWidget(host(disableAnimations: true));
    expect(find.byType(Scrollable), findsNothing);
    expect(find.byType(Image), findsNWidgets(kSponsors.length));
  });
}
