import 'package:delego/Pages/Login_Page/login_page.dart';
import 'package:flutter/material.dart';
import 'package:delego/Pages/Home_Page/my_drawer.dart';
import 'package:delego/Pages/Profile_Page/profile_page.dart';
import 'package:delego/Pages/Room_Page/room_page.dart';
import 'package:delego/Pages/Schedule_Page/schedule_page.dart';
import 'package:delego/Pages/Study Guides/study_guidespage.dart';
import 'package:delego/Pages/Qr_Page/Qr_code.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delego/Theme/theme_controller.dart';
import 'package:delego/Pages/Qr_Page/Qr_scanner.dart';


class HomePage extends StatefulWidget {
  final ThemeController controller;
  const HomePage({super.key, required this.controller});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final size = MediaQuery.of(context).size;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          backgroundColor: scheme.surface,
          elevation: 0,
          foregroundColor: scheme.onSurface,
          title: Text(
            "Home",
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
            ),
          ),
          centerTitle: true,
        ),
        drawer: MyDrawer(
          onProfileTap: () =>
              goToPage(ProfilePage(controller: widget.controller)),
          onSignoutTap: signOut,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Mumbai',
                            style: textTheme.headlineSmall?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Poppins',
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'MUN',
                            style: textTheme.headlineSmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '2026',
                        style: textTheme.titleLarge?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Image.asset(
                    'assets/icons/logo.png',
                    height: size.width * 0.18,
                    width: size.width * 0.18,
                  ),
                ],
              ),

              const SizedBox(height: 10),
              Divider(
                color: scheme.primary,
                thickness: 3,
                indent: size.width * 0.05,
                endIndent: size.width * 0.05,
              ),
              const SizedBox(height: 20),

              // Home cards
              _HomeCard(
                indexText: '01.',
                titleLeft: 'Study',
                titleRight: 'Guides',
                imageAsset: 'assets/icons/book.png',
                onTap: () => goToPage(StudyGuidespage()),
              ),
              _HomeCard(
                indexText: '02.',
                titleLeft: 'My',
                titleRight: 'QR',
                imageAsset: 'assets/icons/qr.png',
                onTap: () => goToPage(QrCode()),
              ),
              _HomeCard(
                indexText: '03.',
                titleLeft: 'Rooms',
                titleRight: '',
                imageAsset: 'assets/icons/loc.png',
                onTap: () => goToPage(RoomPage()),
              ),
              _HomeCard(
                indexText: '04.',
                titleLeft: 'Schedule',
                titleRight: '',
                imageAsset: 'assets/icons/calendar.png',
                onTap: () => goToPage(SchedulePage()),
              ),
              _HomeCard(
                indexText: '05.',
                titleLeft: 'Scan',
                titleRight: 'QR',
                imageAsset: 'assets/icons/qr.png',
                onTap: () => goToPage(QrScanner()),
              ),

              const SizedBox(height: 30),

              // Optional Sponsor Section
              Center(
                child: Column(
                  children: [
                    Text(
                      "Sponsored by",
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        Image.asset('assets/icons/toshiba.png', height: 20),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  final String indexText;
  final String titleLeft;
  final String titleRight;
  final String imageAsset;
  final VoidCallback onTap;

  const _HomeCard({
    required this.indexText,
    required this.titleLeft,
    required this.titleRight,
    required this.imageAsset,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(2, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Left text
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  indexText,
                  style: textTheme.titleMedium?.copyWith(
                    color: scheme.onPrimary.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      titleLeft,
                      style: textTheme.headlineSmall?.copyWith(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (titleRight.isNotEmpty)
                      Text(
                        ' $titleRight',
                        style: textTheme.headlineSmall?.copyWith(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            // Right image
            Image.asset(
              imageAsset,
              height: 70,
              width: 70,
            ),
          ],
        ),
      ),
    );
  }
}
