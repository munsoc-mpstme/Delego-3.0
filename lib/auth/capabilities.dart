import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

/// Permission strings. They mirror mundra-master/permissions.py: the server decides
/// what each role holds and sends the list in GET /delegates/me. Gate screens on
/// these, never on role names.
class Perm {
  static const guidesView = 'guides.view';
  static const badgeView = 'badge.view';
  static const ebTools = 'eb.tools';
  static const foodScan = 'food.scan';
  static const chatView = 'chat.view';
  static const chatSendRequest = 'chat.send_request';
  static const chatRespond = 'chat.respond';
  static const adminRoles = 'admin.roles';
}

/// Roles the server knows, with the label shown in the admin screen.
const kRoles = <({String value, String label})>[
  (value: 'delegate', label: 'Delegate'),
  (value: 'eb', label: 'Executive Board (EB)'),
  (value: 'oc', label: 'Organizing Committee (OC)'),
  (value: 'admin', label: 'Admin'),
];

class Capabilities extends ChangeNotifier {
  Capabilities(this._api);

  static const _roleKey = 'caps_role';
  static const _permsKey = 'caps_permissions';

  final ApiClient _api;

  String role = 'delegate';
  Set<String> _perms = {};

  /// True once a permission list is known, from the server or from the copy saved on
  /// this phone. Until then screens must not guess.
  bool loaded = false;

  /// Gate every screen with this.
  bool can(String permission) => _perms.contains(permission);

  bool get isAdmin => can(Perm.adminRoles);

  bool _refreshing = false;

  /// Why the last load failed (shown on the home screen while debugging).
  String? lastError;

  /// Use the permissions saved by the last successful refresh. Lets a delegate open
  /// their QR badge with no connection. Safe to call when nothing is saved.
  Future<void> loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_permsKey);
      if (saved == null) return;
      role = prefs.getString(_roleKey) ?? 'delegate';
      _perms = saved.toSet();
      loaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Capabilities.loadCached failed: $e');
    }
  }

  Future<void> refresh() async {
    if (_refreshing) return; // also prevents a 403 -> refresh loop
    _refreshing = true;
    try {
      final res = await _api.get('/delegates/me');

      if (res.statusCode != 200) {
        lastError = 'Server returned ${res.statusCode}';
        return;
      }

      final j = jsonDecode(res.body) as Map<String, dynamic>;
      role = (j['role'] ?? 'delegate').toString();
      _perms = {
        for (final p in (j['permissions'] as List? ?? const [])) p.toString()
      };
      lastError = null;
      loaded = true;
      await _save();
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

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_roleKey, role);
      await prefs.setStringList(_permsKey, _perms.toList()..sort());
    } catch (e) {
      debugPrint('Capabilities save failed: $e');
    }
  }

  /// Forget everything: sign-out, expired session, account deleted.
  void clear() {
    role = 'delegate';
    _perms = {};
    loaded = false;
    lastError = null;
    SharedPreferences.getInstance().then((p) {
      p.remove(_roleKey);
      p.remove(_permsKey);
    }).catchError((_) {});
    notifyListeners();
  }
}
