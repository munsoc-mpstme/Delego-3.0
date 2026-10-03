import 'dart:convert';

import 'package:delego/Pages/Login_Page/verify_email_page.dart';
import 'package:delego/api/email_verification.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeVerification extends EmailVerificationApi {
  FakeVerification() : super(baseUrl: 'http://test');

  final verifyCalls = <List<String>>[];
  int resendCalls = 0;
  String? rejectWith; // message to throw from verify
  String? resendRejectWith;

  @override
  Future<void> verify(String email, String code) async {
    verifyCalls.add([email, code]);
    if (rejectWith != null) throw VerificationException(rejectWith!);
  }

  @override
  Future<void> resend(String email) async {
    resendCalls++;
    if (resendRejectWith != null) throw VerificationException(resendRejectWith!);
  }
}

void main() {
  group('EmailVerificationApi', () {
    test('verify posts the email and code as JSON', () async {
      late http.Request seen;
      final api = EmailVerificationApi(
        baseUrl: 'http://test',
        client: MockClient((req) async {
          seen = req;
          return http.Response('{"message":"Email verified!"}', 200);
        }),
      );

      await api.verify('a+b@x.com', '123456');

      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'http://test/verify_email');
      expect(jsonDecode(seen.body), {'email': 'a+b@x.com', 'code': '123456'});
    });

    test('shows the server reason for a wrong or expired code', () async {
      final api = EmailVerificationApi(
        baseUrl: 'http://test',
        client: MockClient((_) async =>
            http.Response('{"detail":"Invalid code"}', 400)),
      );
      expect(api.verify('a@x.com', '000000'),
          throwsA(isA<VerificationException>().having(
              (e) => e.message, 'message', 'Invalid code')));
    });

    test('rate limit and validation errors become readable messages', () async {
      Future<String> msg(int status, String body) async {
        final api = EmailVerificationApi(
          baseUrl: 'http://test',
          client: MockClient((_) async => http.Response(body, status)),
        );
        try {
          await api.verify('a@x.com', '123456');
        } on VerificationException catch (e) {
          return e.message;
        }
        return '';
      }

      expect(await msg(429, 'rate limit exceeded'),
          'Too many tries. Wait a minute and try again.');
      expect(await msg(422, '{"detail":[{"msg":"bad"}]}'),
          'Enter the 6-digit code from your email.');
    });

    test('resend encodes the email in the query string', () async {
      late http.Request seen;
      final api = EmailVerificationApi(
        baseUrl: 'http://test',
        client: MockClient((req) async {
          seen = req;
          return http.Response('{}', 200);
        }),
      );

      await api.resend('a+b@x.com');

      expect(seen.method, 'GET');
      expect(seen.url.path, '/resend_verification');
      expect(seen.url.queryParameters['email'], 'a+b@x.com');
      expect(seen.url.toString(), contains('a%2Bb%40x.com'));
    });

    test('an unreachable server is reported without leaking the exception',
        () async {
      final api = EmailVerificationApi(
        baseUrl: 'http://test',
        client: MockClient((_) async => throw Exception('socket')),
      );
      expect(api.verify('a@x.com', '123456'),
          throwsA(isA<VerificationException>().having((e) => e.message,
              'message', contains('Could not reach the server'))));
    });
  });

  group('VerifyEmailPage', () {
    Future<bool?> open(WidgetTester tester, FakeVerification api,
        {bool emailSent = true}) async {
      bool? result;
      var done = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VerifyEmailPage(
                          email: 'me@x.com', emailSent: emailSent, api: api),
                    ),
                  );
                  done = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(done, isFalse);
      return result;
    }

    testWidgets('a correct code verifies and closes the screen with true',
        (tester) async {
      final api = FakeVerification();
      bool? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async => result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        VerifyEmailPage(email: 'me@x.com', api: api)),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('VERIFY EMAIL'), findsOneWidget);
      expect(find.textContaining('me@x.com'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('verify-code')), '123456');
      await tester.tap(find.byKey(const Key('verify-button')));
      await tester.pumpAndSettle();

      expect(api.verifyCalls, [
        ['me@x.com', '123456']
      ]);
      expect(result, isTrue);
      expect(find.text('VERIFY EMAIL'), findsNothing); // screen closed
    });

    testWidgets('a wrong code shows the reason and stays open', (tester) async {
      final api = FakeVerification()..rejectWith = 'Invalid code';
      await open(tester, api);

      await tester.enterText(find.byKey(const Key('verify-code')), '000000');
      await tester.tap(find.byKey(const Key('verify-button')));
      await tester.pumpAndSettle();

      expect(find.text('Invalid code'), findsOneWidget);
      expect(find.text('VERIFY EMAIL'), findsOneWidget);
    });

    testWidgets('a code that is not 6 digits never reaches the server',
        (tester) async {
      final api = FakeVerification();
      await open(tester, api);

      await tester.enterText(find.byKey(const Key('verify-code')), '123');
      await tester.tap(find.byKey(const Key('verify-button')));
      await tester.pump();

      expect(api.verifyCalls, isEmpty);
      expect(find.text('Enter the 6-digit code from your email.'),
          findsOneWidget);
    });

    testWidgets('only digits can be typed', (tester) async {
      await open(tester, FakeVerification());
      await tester.enterText(find.byKey(const Key('verify-code')), '12ab34');
      await tester.pump();
      expect(
          tester
              .widget<TextField>(find.byKey(const Key('verify-code')))
              .controller!
              .text,
          '1234');
    });

    testWidgets('resend waits out the cooldown, then sends a new code',
        (tester) async {
      final api = FakeVerification();
      await open(tester, api);

      // Just after sign-up a second email is not offered yet.
      expect(find.textContaining('Send a new code in'), findsOneWidget);
      await tester.tap(find.byKey(const Key('resend-button')));
      await tester.pump();
      expect(api.resendCalls, 0);

      await tester.pump(const Duration(seconds: 31));
      expect(find.text('Send a new code'), findsOneWidget);

      await tester.tap(find.byKey(const Key('resend-button')));
      await tester.pump();
      expect(api.resendCalls, 1);
      expect(find.textContaining('A new code is on its way'), findsOneWidget);

      // Let the new cooldown run out so no timer is left pending.
      await tester.pump(const Duration(seconds: 31));
    });

    testWidgets('if sign-up could not send the email, a new code is offered at once',
        (tester) async {
      final api = FakeVerification();
      await open(tester, api, emailSent: false);

      expect(find.textContaining('could not send the code'), findsOneWidget);
      expect(find.text('Send a new code'), findsOneWidget);

      await tester.tap(find.byKey(const Key('resend-button')));
      await tester.pump();
      expect(api.resendCalls, 1);

      await tester.pump(const Duration(seconds: 31));
    });
  });
}
