import 'package:delego/widgets/mun_logo.dart';
import 'package:delego/Pages/Login_Page/login_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:delego/Pages/Home_Page/my_drawer.dart';
import 'package:delego/Pages/Profile_Page/profile_page.dart';
import 'package:delego/Pages/Room_Page/room_page.dart';
import 'package:delego/Pages/Schedule_Page/schedule_page.dart';
import 'package:delego/Pages/Study Guides/study_guidespage.dart';
import 'package:delego/Pages/Qr_Page/Qr_code.dart';
import 'package:delego/Theme/theme_controller.dart';
import 'package:delego/Pages/Qr_Page/Qr_scanner.dart';
import 'package:delego/auth/capabilities.dart';
import 'package:delego/auth/permission_gate.dart';
import 'package:delego/api/api_client.dart';
import 'package:delego/api/scan_queue.dart';
import 'package:delego/widgets/neon.dart';
import 'package:delego/widgets/now_strip.dart';
import 'package:delego/widgets/sponsor_marquee.dart';
import 'package:delego/Pages/Sponsors_Page/sponsor_page.dart';

class HomePage extends StatefulWidget {
  final ThemeController controller;
  const HomePage({super.key, required this.controller});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Height of the transparent top bar; the banner starts right below it.
  static const _barHeight = 40.0;

  Future<void> signOut() async {
    final caps = context.read<Capabilities>();
    final api = context.read<ApiClient>();
    final queue = context.read<ScanQueue>();

    // Saved scans stay on the phone and sync after the next login, so warn.
    final waiting = queue.pendingCount;
    if (waiting > 0) {
      final proceed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Unsynced scans'),
              content: Text(
                '$waiting meal ${waiting == 1 ? 'scan has' : 'scans have'} not '
                'reached the server yet. They stay saved on this phone and '
                'sync after you sign in again (under that account).',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Sign out anyway'),
                ),
              ],
            ),
          ) ??
          false;
      if (!proceed) return;
    }

    // Token only: prefs.clear() would also delete saved scans and the theme.
    await api.clearToken();
    caps.clear(); // forget permissions so the next login starts fresh

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
          builder: (context) => LoginPage(controller: widget.controller)),
      (route) => false,
    );
  }

  void goToPage(Widget page) async {
    // Safely close the drawer if it's open
    final scaffoldState = Scaffold.maybeOf(context);
    if (scaffoldState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }

    // Push the new page normally
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
  }

  /// The tiles this user may see. Rooms and Schedule are open to everyone; the rest
  /// follow the permissions the server sent (see permissions.py in the backend).
  List<Widget> _tiles(Capabilities caps) {
    final tiles = <Widget>[
      if (caps.can(Perm.guidesView))
        NeonCard(
          colors: const [Color(0xFFD9FF1F), Color(0xFF8BC400)],
          label: 'Study\nGuides',
          labelColor: Neon.orange,
          iconAsset: 'assets/icons/book.png',
          seed: 3,
          onTap: () => goToPage(PermissionGate(
            anyOf: const [Perm.guidesView],
            child: StudyGuidespage(),
          )),
        ),
      if (caps.can(Perm.badgeView))
        NeonCard(
          colors: const [Color(0xFFFF2BB4), Color(0xFFB51E9A)],
          label: 'My QR\nBadge',
          labelColor: Neon.yellow,
          iconAsset: 'assets/icons/qr.png',
          seed: 5,
          onTap: () => goToPage(const PermissionGate(
            anyOf: [Perm.badgeView],
            child: QrCode(),
          )),
        ),
      NeonCard(
        colors: const [Color(0xFF2F55FF), Color(0xFF1226A8)],
        label: 'Rooms',
        labelColor: Neon.lime,
        iconAsset: 'assets/icons/loc.png',
        seed: 11,
        onTap: () => goToPage(RoomPage()),
      ),
      NeonCard(
        colors: const [Color(0xFF22D38F), Color(0xFF1B8F63)],
        label: 'Schedule',
        labelColor: Neon.cyan,
        iconAsset: 'assets/icons/calendar.png',
        seed: 13,
        onTap: () => goToPage(SchedulePage()),
      ),
    ];

    // Two per row; a lone last tile keeps half width.
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 14));
      rows.add(Row(
        children: [
          Expanded(child: tiles[i]),
          const SizedBox(width: 14),
          Expanded(
              child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
        ],
      ));
    }

    if (caps.can(Perm.foodScan)) {
      rows
        ..add(const SizedBox(height: 14))
        ..add(NeonCard(
          colors: const [Neon.violet, Neon.blue],
          label: 'Scan a delegate QR',
          labelColor: Neon.yellow,
          iconAsset: 'assets/icons/qr.png',
          height: 92,
          wide: true,
          seed: 17,
          onTap: () => goToPage(const QrScanner()),
        ));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final caps = context.watch<Capabilities>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final onBg = dark ? Colors.white : Neon.navy;

    final Widget content = SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, _barHeight, 20, 28),
        children: [
          const MunLogoLink(
            borderRadius: BorderRadius.all(Radius.circular(28)),
            child: HeroBanner(),
          ),
          NowStrip(onTap: () => goToPage(SchedulePage())),
          Text('Quick Access',
              style: TextStyle(
                fontFamily: Neon.font,
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: onBg,
              )),
          const SizedBox(height: 14),
          // Until the server (or the copy saved on this phone) has told us what this
          // user may do, only the open tiles show, with a way to retry.
          if (!caps.loaded)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      caps.lastError ?? 'Loading your access…',
                      style: TextStyle(
                        color: caps.lastError != null
                            ? scheme.error
                            : onBg.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => caps.refresh().catchError((_) {}),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ..._tiles(caps),
          const SizedBox(height: 28),
          Center(
            child: Text('SPONSORED BY',
                style: Neon.label(onBg.withValues(alpha: 0.6),
                    size: 11, spacing: 3)),
          ),
          const SizedBox(height: 10),
          // Runs edge to edge (past the page padding) so the logos slide off-screen.
          SizedBox(
            height: 64,
            child: OverflowBox(
              minWidth: MediaQuery.of(context).size.width,
              maxWidth: MediaQuery.of(context).size.width,
              child: SponsorMarquee(onTap: () => goToPage(const SponsorPage())),
            ),
          ),
        ],
      ),
    );

    return PopScope(
      canPop: false,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: scheme.surface,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          toolbarHeight: _barHeight,
          title: const Text('Delego'),
          leading: Builder(
            builder: (ctx) => IconButton(
              tooltip: 'Menu',
              icon: const Icon(Icons.menu_rounded),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
        ),
        drawer: MyDrawer(
          onProfileTap: () =>
              goToPage(ProfilePage(controller: widget.controller)),
          onSignoutTap: signOut,
        ),
        body: content,
      ),
    );
  }
}
