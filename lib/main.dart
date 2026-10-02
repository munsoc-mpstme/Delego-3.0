import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'Pages/Login_Page/login_page.dart';
import 'Pages/Home_Page/home_page.dart';

// Centralized theming imports
import 'Theme/app_theme.dart';
import 'Theme/theme_controller.dart';

// MUNDRA access layer
import 'api/api_client.dart';
import 'api/scan_queue.dart';
import 'auth/capabilities.dart';
import 'package:delego/constants/backend.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load persisted theme mode before running the app
  final controller = ThemeController();
  await controller.loadThemeMode();

  final api = ApiClient(baseUrl:Backend.baseUrl );
  final caps = Capabilities(api);

  // Loads saved scans, listens for connectivity and syncs.
  final scanQueue = ScanQueue(api);
  await scanQueue.start();

  runApp(MyApp(
      controller: controller, api: api, caps: caps, scanQueue: scanQueue));
}

class MyApp extends StatefulWidget {
  final ThemeController controller;
  final ApiClient api;
  final Capabilities caps;
  final ScanQueue scanQueue;

  const MyApp({
    super.key,
    required this.controller,
    required this.api,
    required this.caps,
    required this.scanQueue,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool showLaunchScreen = true;
  bool? isLoggedIn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 403: access was revoked/changed -> refetch what this user can do.
    widget.api.onForbidden = widget.caps.refresh;
    // 401: token expired (12h) or invalid -> back to login.
    widget.api.onUnauthorized = _handleUnauthorized;

    _initializeApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Re-read permissions whenever the app comes back to the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && isLoggedIn == true) {
      widget.caps.refresh().catchError((_) {});
    }
  }

  void _handleUnauthorized() {
    widget.caps.clear();
    if (!mounted) return;
    setState(() => isLoggedIn = false);

    // During the splash the normal home switch will show LoginPage.
    if (!showLaunchScreen) {
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => LoginPage(controller: widget.controller),
        ),
        (_) => false,
      );
    }
  }

  Future<void> _initializeApp() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('token');
    final bool hasToken = token != null && token.isNotEmpty;

    if (hasToken) {
      try {
        // Load permissions before the first screen. A 401 here clears the
        // token and flips isLoggedIn via _handleUnauthorized.
        await widget.caps.refresh();
      } catch (_) {
        // Offline at startup: keep the session, retry on resume.
      }
    }

    // Re-read: refresh() may have cleared an expired token.
    final String? after = await widget.api.token;
    if (!mounted) return;
    setState(() {
      isLoggedIn = after != null && after.isNotEmpty;
    });

    // Keep splash for 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => showLaunchScreen = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: widget.api),
        ChangeNotifierProvider<Capabilities>.value(value: widget.caps),
        ChangeNotifierProvider<ScanQueue>.value(value: widget.scanQueue),
      ],
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            debugShowCheckedModeBanner: false,
            theme: getLightTheme(),
            darkTheme: getDarkTheme(),
            themeMode: widget.controller.mode,
            home: showLaunchScreen
                ? LaunchScreen(onLaunchComplete: _onLaunchComplete)
                : (isLoggedIn == true
                    ? HomePage(controller: widget.controller)
                    : LoginPage(controller: widget.controller)),
          );
        },
      ),
    );
  }

  void _onLaunchComplete() {
    if (!mounted) return;
    setState(() => showLaunchScreen = false);
  }
}

// ---------------------------------------------------------------------------
// LaunchScreen and _LaunchScreenState: keep your existing code unchanged here.
// ---------------------------------------------------------------------------
class LaunchScreen extends StatefulWidget {
  final VoidCallback onLaunchComplete;
  const LaunchScreen({super.key, required this.onLaunchComplete});

  @override
  _LaunchScreenState createState() => _LaunchScreenState();
}
  
class _LaunchScreenState extends State<LaunchScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _textController1;
  late AnimationController _textController2;

  @override
  void initState() {
    super.initState();

    _logoController =
    AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..forward();

    _textController1 = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _textController2 = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));

    _logoController.addStatusListener((status) {
      if (status == AnimationStatus.completed) _textController1.forward();
    });

    _textController1.addStatusListener((status) {
      if (status == AnimationStatus.completed) _textController2.forward();
    });

    _textController2.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!mounted) return;
          widget.onLaunchComplete();
        });
      }
    });
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController1.dispose();
    _textController2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FadeTransition(
              opacity: _logoController,
              child: Image.asset(
                'assets/icons/logo.png',
                height: 100,
              ),
            ),
            const SizedBox(height: 20),
            FadeTransition(
              opacity: _textController1,
              child: Text(
                'MumbaiMUN 2026',
                style: textTheme.titleLarge?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
            const SizedBox(height: 20),
            FadeTransition(
              opacity: _textController2,
              child: RichText(
                text: TextSpan(
                  style: textTheme.titleMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Poppins',
                  ),
                  children: [
                    TextSpan(
                      text: 'VOICE AMIDST THE VOID',
                      style: TextStyle(color: scheme.primary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
