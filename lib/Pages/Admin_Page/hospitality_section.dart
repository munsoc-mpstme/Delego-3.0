import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:delego/api/api_client.dart';
import 'package:delego/api/hospitality_team.dart';
import 'package:delego/widgets/neon.dart';

/// Create the Hospitality team and choose who is on it.
class HospitalitySection extends StatelessWidget {
  const HospitalitySection({super.key, this.api});

  /// Tests pass a fake; the app builds it from the shared [ApiClient].
  final HospitalityTeamApi? api;

  @override
  Widget build(BuildContext context) => ManagedTeamSection(
        config: kHospitalityConfig,
        api: api,
      );
}

class IhlSection extends StatelessWidget {
  const IhlSection({super.key, this.api});

  final IhlTeamApi? api;

  @override
  Widget build(BuildContext context) =>
      ManagedTeamSection(config: kIhlConfig, api: api);
}

class ManagedTeamSection extends StatefulWidget {
  const ManagedTeamSection({super.key, required this.config, this.api});

  final ManagedTeamConfig config;
  final TeamRosterApi? api;

  @override
  State<ManagedTeamSection> createState() => _ManagedTeamSectionState();
}

class _ManagedTeamSectionState extends State<ManagedTeamSection> {
  late final TeamRosterApi _api;
  final _email = TextEditingController();

  ManagedTeamState? _state;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _api =
        widget.api ?? TeamRosterApi(context.read<ApiClient>(), widget.config);
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
    ManagedTeamState? state;
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
      _say('${widget.config.name} team created.');
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
        ? '$email added. They also need the OC role to use this team.'
        : '$email has not registered yet. They need to register and have the OC role for team access.');
    await _load();
  }

  Future<void> _remove(TeamMember m) async {
    final teamId = _state?.teamId;
    if (teamId == null || _busy) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove from ${widget.config.name}?'),
        content: Text('${m.label} will no longer have this team\'s access.'),
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
      _say('${m.label} removed from ${widget.config.name}.');
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.7));

    final children = <Widget>[
      const Divider(height: 48),
      Text('${widget.config.name.toUpperCase()} TEAM',
          style: Neon.label(scheme.onSurface, size: 16, spacing: 1.5)),
      const SizedBox(height: 8),
      Text(
        '${widget.config.description}. Each member must also have the OC role; '
        'adding someone to this team without the OC role does not grant team access.',
        style: muted,
      ),
      const SizedBox(height: 16),
    ];

    if (_loading) {
      children.add(const Center(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator())));
    } else if (_error != null) {
      children.addAll([
        Text(_error!, style: TextStyle(color: scheme.error)),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _load, child: const Text('Try again')),
      ]);
    } else if (!_state!.hasTeam) {
      children.add(FilledButton.icon(
        key: Key('create-${widget.config.key}'),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
        ),
        onPressed: _busy ? null : _create,
        icon: const Icon(Icons.groups),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('CREATE ${widget.config.name.toUpperCase()} TEAM',
              maxLines: 1,
              style: Neon.label(scheme.onPrimary, size: 14, spacing: 1)),
        ),
      ));
    } else {
      children.addAll([
        TextField(
          key: Key('${widget.config.key}-email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _add(),
          decoration: const InputDecoration(labelText: 'Add by email'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: Key('add-${widget.config.key}-member'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
          ),
          onPressed: _busy ? null : _add,
          child: Text('ADD TO TEAM',
              style: Neon.label(scheme.onPrimary, size: 14, spacing: 1)),
        ),
        const SizedBox(height: 16),
        if (_state!.members.isEmpty)
          Text('No one is on the team yet.', style: muted)
        else
          for (final m in _state!.members)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(widget.config.key == 'hospitality'
                  ? Icons.restaurant
                  : Icons.groups),
              title: Text(
                m.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                m.invited ? '${m.email} · not registered yet' : m.email,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.close),
                onPressed: _busy ? null : () => _remove(m),
              ),
            ),
      ]);
    }

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}
