import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_client.dart';

/// Team roster definitions shared by the admin-managed team screens.
const kHospitalityTeamName = 'Hospitality';
const kHospitalityPermissions = [
  'food.manage_entitlement',
  'chat.view',
  'chat.post',
];
const kHospitalityDescription = 'Scans delegate QR codes for food';
const kIhlTeamName = 'IHL';
const kIhlPermissions = [
  'ihl.request_break',
  'chat.view',
  'chat.post',
];
const kIhlDescription = 'Coordinates break requests in committee chats';

class ManagedTeamConfig {
  const ManagedTeamConfig({
    required this.name,
    required this.description,
    required this.permissions,
    required this.key,
  });

  final String name;
  final String description;
  final List<String> permissions;
  final String key;
}

const kHospitalityConfig = ManagedTeamConfig(
  name: kHospitalityTeamName,
  description: kHospitalityDescription,
  permissions: kHospitalityPermissions,
  key: 'hospitality',
);
const kIhlConfig = ManagedTeamConfig(
  name: kIhlTeamName,
  description: kIhlDescription,
  permissions: kIhlPermissions,
  key: 'ihl',
);

/// A server refusal with a message that can be shown to the person using the screen.
class TeamApiException implements Exception {
  TeamApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class TeamMember {
  const TeamMember({required this.email, this.name, required this.invited});

  final String email;
  final String? name;

  /// True while they have not registered yet: they join automatically when they do.
  final bool invited;

  String get label => (name != null && name!.trim().isNotEmpty) ? name! : email;
}

/// What the screen shows: no team yet (teamId == null), or the team and its members.
class ManagedTeamState {
  const ManagedTeamState({
    required this.eventId,
    this.teamId,
    this.members = const [],
  });

  final int eventId;
  final int? teamId;
  final List<TeamMember> members;

  bool get hasTeam => teamId != null;
}

typedef HospitalityState = ManagedTeamState;

/// Manages a configured team through the server's team routes. Admins only: the server
/// checks that on every call.
///
/// Throws [Forbidden] and [SessionExpired] (from [ApiClient]) untouched so the screen
/// can handle them, and [TeamApiException] for anything else the server refuses.
class TeamRosterApi {
  TeamRosterApi(this._api, this.config);

  final ApiClient _api;
  final ManagedTeamConfig config;

  /// Find the event, then the configured team and its roster, if it exists.
  Future<ManagedTeamState> load() async {
    final events = _list(await _api.get('/events'), 'Could not load the event');
    if (events.isEmpty) {
      throw TeamApiException('The server has no event set up yet.');
    }
    final eventId = (events.first['id'] as num).toInt();

    final teams = _list(
        await _api.get('/events/$eventId/teams'), 'Could not load the teams');
    final team = teams.cast<Map<String, dynamic>?>().firstWhere(
          (t) =>
              '${t?['name']}'.trim().toLowerCase() ==
              config.name.toLowerCase(),
          orElse: () => null,
        );
    if (team == null) return ManagedTeamState(eventId: eventId);

    final teamId = (team['id'] as num).toInt();
    await _ensurePermissions(teamId, team['permissions']);
    final roster = _list(await _api.get('/teams/$teamId/members'),
        'Could not load the team members');
    return ManagedTeamState(
      eventId: eventId,
      teamId: teamId,
      members: [
        for (final m in roster)
          TeamMember(
            email: '${m['email']}',
            name: m['name']?.toString(),
            invited: m['status'] == 'invited',
          ),
      ],
    );
  }

  /// Ensure existing teams have their current permissions without removing extras.
  Future<void> _ensurePermissions(int teamId, Object? current) async {
    final have = <String>[
      if (current is List) for (final p in current) '$p',
    ];
    if (config.permissions.every(have.contains)) return;
    final res = await _api.patchJson('/teams/$teamId/permissions', {
      'permissions': {...have, ...config.permissions}.toList(),
    });
    if (res.statusCode != 200) {
      throw TeamApiException(
          _detail(res, "Could not update the team's permissions"));
    }
  }

  /// Create the configured team. A 409 means it already exists, which is fine.
  Future<void> createTeam(int eventId) async {
    final res = await _api.postJson('/events/$eventId/teams', {
      'name': config.name,
      'description': config.description,
      'permissions': config.permissions,
    });
    if (res.statusCode == 201 || res.statusCode == 409) return;
    throw TeamApiException(_detail(res, 'Could not create the team'));
  }

  /// Add someone by email. Returns true if they were added as a member now, false if
  /// they have not registered yet and were invited instead.
  Future<bool> addMember(int teamId, String email) async {
    final res = await _api.postJson(
        '/teams/$teamId/members', {'email': email, 'level': 'member'});
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw TeamApiException(_detail(res, 'Could not add $email'));
    }
    try {
      return (jsonDecode(res.body) as Map)['status'] == 'member';
    } catch (_) {
      return true;
    }
  }

  Future<void> removeMember(int teamId, String email) async {
    final res = await _api
        .delete('/teams/$teamId/members/${Uri.encodeComponent(email)}');
    if (res.statusCode != 200) {
      throw TeamApiException(_detail(res, 'Could not remove $email'));
    }
  }

  List<Map<String, dynamic>> _list(http.Response res, String failure) {
    if (res.statusCode != 200) throw TeamApiException(_detail(res, failure));
    try {
      return [
        for (final e in jsonDecode(res.body) as List)
          (e as Map).cast<String, dynamic>()
      ];
    } catch (_) {
      throw TeamApiException(failure);
    }
  }

  /// FastAPI puts the reason in `detail`: a string, or a list for validation errors.
  String _detail(http.Response res, String fallback) {
    try {
      final d = (jsonDecode(res.body) as Map)['detail'];
      if (d is String && d.isNotEmpty) return d;
      if (res.statusCode == 422) return 'Enter a valid email address.';
    } catch (_) {}
    return '$fallback (${res.statusCode}).';
  }
}

class HospitalityTeamApi extends TeamRosterApi {
  HospitalityTeamApi(ApiClient api) : super(api, kHospitalityConfig);
}

class IhlTeamApi extends TeamRosterApi {
  IhlTeamApi(ApiClient api) : super(api, kIhlConfig);
}
