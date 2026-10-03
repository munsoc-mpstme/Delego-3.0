import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:delego/api/email_verification.dart';
import 'package:delego/widgets/neon.dart';

/// Where someone enters the 6-digit code that was emailed when they signed up. Until the
/// code is accepted they cannot log in. Pops with `true` once the email is verified.
class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({
    super.key,
    required this.email,
    this.emailSent = true,
    this.api,
  });

  final String email;

  /// False when sign-up could not send the email (the screen then says so and offers a
  /// new code straight away).
  final bool emailSent;

  /// Tests pass a fake; the app uses the real server.
  final EmailVerificationApi? api;

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  static const _cooldownSeconds = 30;

  late final EmailVerificationApi _api = widget.api ?? EmailVerificationApi();
  final _code = TextEditingController();

  bool _busy = false;
  bool _resending = false;
  String? _error;
  String? _info;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Do not offer another email for a moment after the first one was sent.
    if (widget.emailSent) _startCooldown();
    if (!widget.emailSent) {
      _info = 'We could not send the code yet. Tap "Send a new code".';
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = _cooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _error = 'Enter the 6-digit code from your email.';
        _info = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await _api.verify(widget.email, code);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on VerificationException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  Future<void> _resend() async {
    if (_resending || _cooldown > 0) return;
    setState(() {
      _resending = true;
      _error = null;
      _info = null;
    });
    try {
      await _api.resend(widget.email);
      if (!mounted) return;
      setState(() {
        _resending = false;
        _info = 'A new code is on its way to ${widget.email}.';
      });
      _code.clear();
      _startCooldown();
    } on VerificationException catch (e) {
      if (!mounted) return;
      setState(() {
        _resending = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.7));

    return Scaffold(
      appBar: AppBar(centerTitle: false, title: const Text('VERIFY EMAIL')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Icon(Icons.mark_email_read_outlined, size: 56, color: scheme.primary),
            const SizedBox(height: 16),
            Text('Enter your code',
                style: Neon.label(scheme.onSurface, size: 20, spacing: 1)),
            const SizedBox(height: 8),
            Text(
              'We emailed a 6-digit code to ${widget.email}. '
              'You can log in once it is verified. Check your spam folder if it '
              'does not show up.',
              style: muted,
            ),
            const SizedBox(height: 24),
            TextField(
              key: const Key('verify-code'),
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 10),
              decoration: const InputDecoration(
                counterText: '',
                hintText: '------',
              ),
              onSubmitted: (_) => _verify(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  key: const Key('verify-error'),
                  style: TextStyle(color: scheme.error)),
            ],
            if (_info != null) ...[
              const SizedBox(height: 12),
              Text(_info!, key: const Key('verify-info'), style: muted),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 54,
              child: FilledButton(
                key: const Key('verify-button'),
                onPressed: _busy ? null : _verify,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Text('VERIFY',
                        style: Neon.label(scheme.onPrimary, size: 14, spacing: 1)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              key: const Key('resend-button'),
              onPressed: (_resending || _cooldown > 0) ? null : _resend,
              child: Text(_cooldown > 0
                  ? 'Send a new code in ${_cooldown}s'
                  : 'Send a new code'),
            ),
          ],
        ),
      ),
    );
  }
}
