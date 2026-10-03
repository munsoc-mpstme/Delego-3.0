import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_client.dart';

/// The team that scans delegate QR codes for food. Its one permission is
/// food.manage_entitlement, which the server turns into the scanner for its members.
const kHospitalityTeamName = 'Hospitality';
const kHospitalityPermission = 'food.manage_entitlement';
const kHospitalityDescription = 'Scans delegate QR codes for food';

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
class HospitalityState {
  const HospitalityState({
    required this.eventId,
    this.teamId,
    this.members = const [],
  });

  final int eventId;
  final int? teamId;
  final List<TeamMember> members;

  bool get hasTeam => teamId != null;
}

/// Creates the Hospitality team and manages who is on it, through the server's team
/// routes. Admins only: the server checks that on every call.
///
/// Throws [Forbidden] and [SessionExpired] (from [ApiClient]) untouched so the screen
/// can handle them, and [TeamApiException] for anything else the server refuses.
class HospitalityTeamApi {
  HospitalityTeamApi(this._api);

  final ApiClient _api;

  /// Find the event, then the Hospitality team and its roster, if the team exists.
  Future<HospitalityState> load() async {
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
              kHospitalityTeamName.toLowerCase(),
          orElse: () => null,
        );
    if (team == null) return HospitalityState(eventId: eventId);

    final teamId = (team['id'] as num).toInt();
    final roster = _list(await _api.get('/teams/$teamId/members'),
        'Could not load the team members');
    return HospitalityState(
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

  /// Create the team with only the food-scanning permission. A 409 means it already
  /// exists (someone else just made it), which is fine.
  Future<void> createTeam(int eventId) async {
    final res = await _api.postJson('/events/$eventId/teams', {
      'name': kHospitalityTeamName,
      'description': kHospitalityDescription,
      'permissions': [kHospitalityPermission],
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
