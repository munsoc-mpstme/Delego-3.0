import 'package:delego/widgets/mun_logo.dart';
import 'package:flutter/material.dart';
import 'package:delego/Pages/Home_Page/my_list_tile.dart';
import 'package:delego/Pages/Sponsors_Page/sponsor_page.dart';
import 'package:delego/Pages/Policy_Page/policy_page.dart';
import 'package:delego/Pages/Admin_Page/admin_dashboard.dart';
import 'package:delego/Pages/Chat_Page/committee_chat_page.dart';
import 'package:delego/Pages/EB_Tools/eb_tools_page.dart';
import 'package:provider/provider.dart';
import 'package:delego/auth/capabilities.dart';
import 'package:delego/auth/permission_gate.dart';
import 'package:delego/widgets/neon.dart';

class MyDrawer extends StatefulWidget {
  final void Function()? onProfileTap;
  final void Function()? onSignoutTap;

  const MyDrawer({
    Key? key,
    required this.onProfileTap,
    required this.onSignoutTap,
  }) : super(key: key);

  @override
  State<MyDrawer> createState() => _MyDrawerState();
}

class _MyDrawerState extends State<MyDrawer> {
  void goToSponsorsPage() {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SponsorPage()),
    );
  }

  void openPolicy(String policyName) {
    Navigator.pop(context);

    final pdfAsset = (policyName == 'POSH Policy')
        ? 'assets/pdfs/POSH.pdf'
        : 'assets/pdfs/ConferencePolicy.pdf';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PdfViewerPage(pdfAsset: pdfAsset),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final caps = context.watch<Capabilities>();

    return Drawer(
      backgroundColor: scheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            // HEADER
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFF2BB4), Color(0xFF7A1BFF)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MunLogoLink(
                    child: Image.asset('assets/images/logo_solid.webp', height: 34),
                  ),
                  const SizedBox(height: 10),
                  Text('MUMBAI MUN',
                      style: Neon.label(Neon.yellow, size: 12, spacing: 3)),
                  const SizedBox(height: 2),
                  Text('2026',
                      style: Neon.label(Colors.white, size: 38, spacing: -1)),
                  const SizedBox(height: 6),
                  Text('AN AXIOM APART',
                      style: Neon.label(Colors.white, size: 10, spacing: 3)),
                ],
              ),
            ),

            // MAIN LIST
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  MyListTile(
                    icon: Icons.home,
                    text: 'HOME',
                    onTap: () => Navigator.pop(context),
                  ),
                  MyListTile(
                    icon: Icons.person,
                    text: 'SETTINGS',
                    onTap: widget.onProfileTap,
                  ),
                  MyListTile(
                    icon: Icons.handshake,
                    text: 'SPONSORS',
                    onTap: goToSponsorsPage,
                  ),

                  // POLICIES (Dropdown simplified)
                  ListTile(
                    leading: Icon(Icons.policy, color: scheme.onSurface),
                    title: Text('POLICIES', style: TextStyle(color: scheme.onSurface)),
                    trailing: PopupMenuButton<String>(
                      icon: Icon(Icons.arrow_drop_down, color: scheme.onSurface),
                      color: scheme.surface,
                      onSelected: openPolicy,
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'POSH Policy',
                          child: Text('POSH Policy'),
                        ),
                        const PopupMenuItem(
                          value: 'Conference Policy',
                          child: Text('Conference Policy'),
                        ),
                      ],
                    ),
                  ),
                  if (caps.can(Perm.adminRoles))
                    MyListTile(
                      icon: Icons.admin_panel_settings,
                      text: 'USER ROLES',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const PermissionGate(
                                  anyOf: [Perm.adminRoles],
                                  child: AdminDashboard())),
                        );
                      },
                    ),
                  if (caps.can(Perm.chatView))
                    MyListTile(
                      icon: Icons.chat_bubble_outline,
                      text: 'BREAK COORDINATION',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const PermissionGate(
                                  anyOf: [Perm.chatView],
                                  child: CommitteeChatPage())),
                        );
                      },
                    ),
                  if (caps.can(Perm.ebTools))
                    MyListTile(
                      icon: Icons.gavel,
                      text: 'EB TOOLS',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const PermissionGate(
                                  anyOf: [Perm.ebTools],
                                  child: EBToolsPage())),
                        );
                      },
                    ),
                ],
              ),
            ),

            // LOGOUT BUTTON (bottom aligned)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: scheme.errorContainer,
                  foregroundColor: scheme.onErrorContainer,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.logout),
                label: const Text('LOGOUT'),
                onPressed: widget.onSignoutTap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
