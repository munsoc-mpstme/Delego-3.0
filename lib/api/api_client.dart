import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class SessionExpired implements Exception {}

class Forbidden implements Exception {}

class ApiClient {
  ApiClient({required this.baseUrl});

  final String baseUrl; // e.g. https://mundra.onrender.com

  /// Set from main(): clear state and go to login.
  void Function()? onUnauthorized;

  /// Set from main(): refetch capabilities (access was revoked).
  void Function()? onForbidden;

  // Same key your existing login code uses. TODO: move to secure storage.
  Future<String?> get token async =>
      (await SharedPreferences.getInstance()).getString('token');
  Future<void> saveToken(String t) async =>
      (await SharedPreferences.getInstance()).setString('token', t);
  Future<void> clearToken() async =>
      (await SharedPreferences.getInstance()).remove('token');

  Future<http.Response> _send(
    String method,
    String path, {
    Object? json,
    Map<String, String>? form,
  }) async {
    final req = http.Request(method, Uri.parse('$baseUrl$path'));
    req.headers['Authorization'] = 'Bearer ${await token}';

    if (json != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(json);
    } else if (form != null) {
      req.bodyFields = form; // sets form-urlencoded content type
    }

    final res = await http.Response.fromStream(await req.send());

    if (res.statusCode == 401) {
      await clearToken();
      onUnauthorized?.call();
      throw SessionExpired();
    }
    if (res.statusCode == 403) {
      onForbidden?.call();
      throw Forbidden();
    }
    return res;
  }

  Future<http.Response> get(String path) => _send('GET', path);
  Future<http.Response> postJson(String path, Object body) =>
      _send('POST', path, json: body);
  Future<http.Response> postForm(String path, Map<String, String> form) =>
      _send('POST', path, form: form);
  Future<http.Response> patchJson(String path, Object body) =>
      _send('PATCH', path, json: body);
  Future<http.Response> delete(String path) => _send('DELETE', path);
}