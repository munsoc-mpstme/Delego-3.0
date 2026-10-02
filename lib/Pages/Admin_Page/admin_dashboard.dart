import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:delego/api/api_client.dart';
import 'package:delego/auth/capabilities.dart';
import 'package:delego/widgets/neon.dart';

/// Change a user's role. Admins only (the server enforces it too, and records every
/// change in its audit log).
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final _email = TextEditingController();
  String _role = 'oc';
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  String _label(String role) =>
      kRoles.firstWhere((r) => r.value == role, orElse: () => (value: role, label: role)).label;

  void _say(String text, {bool error = false}) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? scheme.error : null,
      ));
  }

  Future<void> _apply() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      _say('Enter the email the person registered with.', error: true);
      return;
    }

    final api = context.read<ApiClient>();
    setState(() => _busy = true);
    try {
      final res = await api.patchJson(
          '/admin/users/${Uri.encodeComponent(email)}/role', {'role': _role});
      if (!mounted) return;

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final old = '${body['old_role']}';
        _say(old == _role
            ? '$email is already ${_label(_role)}.'
            : '$email: ${_label(old)} → ${_label(_role)}');
      } else {
        String detail = 'Failed (${res.statusCode})';
        try {
          detail = (jsonDecode(res.body) as Map)['detail'].toString();
        } catch (_) {}
        _say(detail, error: true);
      }
    } on Forbidden {
      if (mounted) _say('You are not allowed to change roles.', error: true);
    } on SessionExpired {
      // ApiClient already sent the user back to login.
    } catch (_) {
      if (mounted) _say('Could not reach the server.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(centerTitle: false, title: const Text('USER ROLES')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'Give someone a role. They need to have registered first. '
            'You cannot change your own role, and the last admin cannot be demoted.',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'User email'),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _role,
            decoration: const InputDecoration(labelText: 'Role'),
            items: [
              for (final r in kRoles)
                DropdownMenuItem(value: r.value, child: Text(r.label)),
            ],
            onChanged: (v) => setState(() => _role = v ?? _role),
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 54,
            child: FilledButton(
              onPressed: _busy ? null : _apply,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Text('UPDATE ROLE',
                      style: Neon.label(scheme.onPrimary, size: 14, spacing: 1)),
            ),
          ),
        ],
      ),
    );
  }
}
