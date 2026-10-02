import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';

/// One team membership. Field names are a best guess: check the real shape of
/// `teams` in GET /delegates/me at /docs and adjust fromJson.
class Membership {
  Membership({
    required this.teamId,
    required this.team,
    required this.level,
    this.committee,
  });

  final int? teamId;
  final String team;
  final String level; // member | lead
  final String? committee;

  factory Membership.fromJson(Map<String, dynamic> j) => Membership(
        teamId: j['team_id'] ?? j['id'],
        team: (j['team'] ?? j['name'] ?? '').toString(),
        level: (j['level'] ?? 'member').toString(),
        committee: j['committee']?.toString(),
      );
}

class Capabilities extends ChangeNotifier {
  Capabilities(this._api);

  final ApiClient _api;

  String? userId; // goes in the delegate QR; verify the field name in /docs
  String role = 'delegate';
  bool isHead = false;
  Set<String> _perms = {};
  List<Membership> memberships = [];
  bool loaded = false;

  bool get isAdmin => role == 'admin';

  /// Gate every screen with this. Never gate on team names.
  bool can(String verb) => isAdmin || isHead || _perms.contains(verb);

  /// Committees I'm scoped to (rapporteur verbs).
  List<String> get myCommittees =>
      memberships.map((m) => m.committee).whereType<String>().toSet().toList();

  bool _refreshing = false;

  /// Why the last load failed (shown on the home screen while debugging).
  String? lastError;

  Future<void> refresh() async {
    if (_refreshing) return; // also prevents a 403 -> refresh loop
    _refreshing = true;
    try {
      final res = await _api.get('/delegates/me');
      debugPrint('ME ${res.statusCode}: ${res.body}');

      if (res.statusCode != 200) {
        lastError = 'Server returned ${res.statusCode}';
        return;
      }

      final j = jsonDecode(res.body) as Map<String, dynamic>;
      userId = j['id']?.toString();
      role = (j['role'] ?? 'delegate').toString();
      isHead = j['is_head'] == true;
      _perms = Set<String>.from(j['permissions'] ?? const []);
      memberships = (j['teams'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Membership.fromJson)
          .toList();
      lastError = null;
      loaded = true;
    } on SessionExpired {
      // ApiClient already cleared the token and redirected to login.
    } on Forbidden {
      // Shouldn't happen on /delegates/me; ignored to avoid a refresh loop.
    } catch (e) {
      lastError = 'Could not load profile: $e';
      debugPrint('Capabilities.refresh failed: $e');
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  void clear() {
    userId = null;
    role = 'delegate';
    isHead = false;
    _perms = {};
    memberships = [];
    loaded = false;
    notifyListeners();
  }
}