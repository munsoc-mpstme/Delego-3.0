import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:delego/constants/backend.dart';

/// A refusal from the server, with a message that can be shown as it is.
class VerificationException implements Exception {
  VerificationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Checks the 6-digit code emailed at sign-up, and asks for a new one. These routes are
/// public (the person cannot log in yet), so no token is sent.
class EmailVerificationApi {
  EmailVerificationApi({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _base = baseUrl ?? Backend.baseUrl;

  final http.Client _client;
  final String _base;

  static const _timeout = Duration(seconds: 20);

  /// Confirm the code. Completes normally when the email is now verified.
  Future<void> verify(String email, String code) async {
    final res = await _send(() => _client.post(
          Uri.parse('$_base/verify_email'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'code': code}),
        ));
    if (res.statusCode != 200) {
      throw VerificationException(_reason(res, 'Could not verify the code'));
    }
  }

  /// Email a new code. Completes normally when it was sent.
  Future<void> resend(String email) async {
    final res = await _send(() => _client.get(
          Uri.parse('$_base/resend_verification')
              .replace(queryParameters: {'email': email}),
        ));
    if (res.statusCode != 200) {
      throw VerificationException(_reason(res, 'Could not send a new code'));
    }
  }

  Future<http.Response> _send(Future<http.Response> Function() call) async {
    try {
      return await call().timeout(_timeout);
    } on TimeoutException {
      throw VerificationException('The server took too long. Try again.');
    } catch (_) {
      throw VerificationException(
          'Could not reach the server. Check your connection.');
    }
  }

  /// FastAPI puts the reason in `detail`: a string, or a list for validation errors.
  String _reason(http.Response res, String fallback) {
    try {
      final d = (jsonDecode(res.body) as Map)['detail'];
      if (d is String && d.isNotEmpty) return d;
    } catch (_) {}
    if (res.statusCode == 429) return 'Too many tries. Wait a minute and try again.';
    if (res.statusCode == 422) return 'Enter the 6-digit code from your email.';
    return '$fallback (${res.statusCode}).';
  }
}
