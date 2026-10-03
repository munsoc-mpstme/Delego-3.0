import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:delego/api/api_client.dart';
import 'package:delego/api/hospitality_team.dart';
import 'package:delego/widgets/neon.dart';

/// Create the Hospitality team and choose who is on it. Members get the food scanner
/// (they scan delegate QR codes at meals). Shown to admins only, under the role form.
class HospitalitySection extends StatefulWidget {
  const HospitalitySection({super.key, this.api});

  /// Tests pass a fake; the app builds it from the shared [ApiClient].
  final HospitalityTeamApi? api;

  @override
  State<HospitalitySection> createState() => _HospitalitySectionState();
}

class _HospitalitySectionState extends State<HospitalitySection> {
  late final HospitalityTeamApi _api;
  final _email = TextEditingController();

  HospitalityState? _state;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? HospitalityTeamApi(context.read<ApiClient>());
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _say(String text, {bool error = false}) {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? scheme.error : null,
      ));
  }

  /// Run one server call, turning every failure into a message on screen.
  Future<T?> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on Forbidden {
      _say('You are not allowed to manage teams.', error: true);
    } on SessionExpired {
      // ApiClient already sent the user back to login.
    } on TeamApiException catch (e) {
      _say(e.message, error: true);
    } catch (_) {
      _say('Could not reach the server.', error: true);
    }
    return null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    HospitalityState? state;
    String? error;
    try {
      state = await _api.load();
    } on Forbidden {
      error = 'You are not allowed to manage teams.';
    } on SessionExpired {
      return;
    } on TeamApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not reach the server.';
    }
    if (!mounted) return;
    setState(() {
      _state = state;
      _error = error;
      _loading = false;
    });
  }

  Future<void> _create() async {
    final eventId = _state?.eventId;
    if (eventId == null || _busy) return;
    setState(() => _busy = true);
    final ok = await _guard(() async {
      await _api.createTeam(eventId);
      return true;
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == true) {
      _say('Hospitality team created.');
      await _load();
    }
  }

  Future<void> _add() async {
    final teamId = _state?.teamId;
    final email = _email.text.trim();
    if (teamId == null || _busy) return;
    if (!email.contains('@')) {
      _say('Enter the email the person registered with.', error: true);
      return;
    }
    setState(() => _busy = true);
    final added = await _guard(() => _api.addMember(teamId, email));
    if (!mounted) return;
    setState(() => _busy = false);
    if (added == null) return;
    _email.clear();
    _say(added
        ? '$email can now scan food.'
        : '$email has not registered yet. They get access when they do.');
    await _load();
  }

  Future<void> _remove(TeamMember m) async {
    final teamId = _state?.teamId;
    if (teamId == null || _busy) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from Hospitality?'),
        content: Text('${m.label} will no longer be able to scan food.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    final ok = await _guard(() async {
      await _api.removeMember(teamId, m.email);
      return true;
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == true) {
      _say('${m.label} removed.');
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.7));

    final children = <Widget>[
      const Divider(height: 48),
      Text('HOSPITALITY TEAM', style: Neon.label(scheme.onSurface, size: 16, spacing: 1.5)),
      const SizedBox(height: 8),
      Text(
        'People on this team scan delegate QR codes to serve food, and accept or '
        'reject break requests in Break Coordination. They do not need any other role.',
        style: muted,
      ),
      const SizedBox(height: 16),
    ];

    if (_loading) {
      children.add(const Center(
          child: Padding(
              padding: EdgeInsets.all(24), child: CircularProgressIndicator())));
    } else if (_error != null) {
      children.addAll([
        Text(_error!, style: TextStyle(color: scheme.error)),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _load, child: const Text('Try again')),
      ]);
    } else if (!_state!.hasTeam) {
      children.add(SizedBox(
        height: 54,
        child: FilledButton.icon(
          key: const Key('create-hospitality'),
          onPressed: _busy ? null : _create,
          icon: const Icon(Icons.groups),
          label: Text('CREATE HOSPITALITY TEAM',
              style: Neon.label(scheme.onPrimary, size: 14, spacing: 1)),
        ),
      ));
    } else {
      children.addAll([
        TextField(
          key: const Key('hospitality-email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _add(),
          decoration: const InputDecoration(labelText: 'Add by email'),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 50,
          child: FilledButton(
            key: const Key('add-hospitality-member'),
            onPressed: _busy ? null : _add,
            child: Text('ADD TO TEAM',
                style: Neon.label(scheme.onPrimary, size: 14, spacing: 1)),
          ),
        ),
        const SizedBox(height: 16),
        if (_state!.members.isEmpty)
          Text('No one is on the team yet.', style: muted)
        else
          for (final m in _state!.members)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.restaurant),
              title: Text(m.label),
              subtitle: Text(m.invited ? '${m.email} · not registered yet' : m.email),
              trailing: IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.close),
                onPressed: _busy ? null : () => _remove(m),
              ),
            ),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}
