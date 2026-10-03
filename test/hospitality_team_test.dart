import 'dart:convert';

import 'package:delego/Pages/Admin_Page/hospitality_section.dart';
import 'package:delego/api/api_client.dart';
import 'package:delego/api/hospitality_team.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// A server stand-in: answers by "METHOD path" and records every call.
class FakeApi extends ApiClient {
  FakeApi() : super(baseUrl: 'http://test');

  final routes = <String, http.Response Function(Object? body)>{};
  final calls = <String>[];
  final bodies = <String, Object?>{};

  http.Response _answer(String method, String path, Object? body) {
    final key = '$method $path';
    calls.add(key);
    bodies[key] = body;
    final route = routes[key];
    if (route == null) return http.Response('{"detail":"no route $key"}', 404);
    return route(body);
  }

  @override
  Future<http.Response> get(String path) async => _answer('GET', path, null);
  @override
  Future<http.Response> postJson(String path, Object body) async =>
      _answer('POST', path, body);
  @override
  Future<http.Response> delete(String path) async =>
      _answer('DELETE', path, null);
}

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

void main() {
  group('HospitalityTeamApi', () {
    test('no team yet: only the event id is known', () async {
      final api = FakeApi()
        ..routes['GET /events'] = ((_) => json([{'id': 7, 'name': 'MUN'}]))
        ..routes['GET /events/7/teams'] = ((_) => json([
              {'id': 3, 'name': 'Rapporteurs'}
            ]));

      final s = await HospitalityTeamApi(api).load();

      expect(s.hasTeam, isFalse);
      expect(s.eventId, 7);
      expect(s.members, isEmpty);
    });

    test('finds the team by name and lists its roster', () async {
      final api = FakeApi()
        ..routes['GET /events'] = ((_) => json([{'id': 1}]))
        ..routes['GET /events/1/teams'] = ((_) => json([
              {'id': 3, 'name': 'Rapporteurs'},
              {'id': 9, 'name': 'hospitality'},
            ]))
        ..routes['GET /teams/9/members'] = ((_) => json([
              {'email': 'a@x.com', 'name': 'Asha Rao', 'status': 'member'},
              {'email': 'b@x.com', 'name': null, 'status': 'invited'},
            ]));

      final s = await HospitalityTeamApi(api).load();

      expect(s.teamId, 9);
      expect(s.members.map((m) => m.label), ['Asha Rao', 'b@x.com']);
      expect(s.members.map((m) => m.invited), [false, true]);
    });

    test('creating sends only the food permission; a 409 counts as done',
        () async {
      final api = FakeApi()
        ..routes['POST /events/1/teams'] = ((_) => json({'id': 9}, 201));
      await HospitalityTeamApi(api).createTeam(1);
      expect(api.bodies['POST /events/1/teams'], {
        'name': 'Hospitality',
        'description': 'Scans delegate QR codes for food',
        'permissions': ['food.manage_entitlement'],
      });

      api.routes['POST /events/1/teams'] =
          ((_) => json({'detail': 'A team with that name already exists'}, 409));
      await HospitalityTeamApi(api).createTeam(1); // does not throw
    });

    test('adding reports member vs invited, and surfaces the server reason',
        () async {
      final api = FakeApi()
        ..routes['POST /teams/9/members'] = ((b) => json(
            {'email': (b as Map)['email'], 'status': 'member'}, 201));
      final team = HospitalityTeamApi(api);

      expect(await team.addMember(9, 'a@x.com'), isTrue);
      expect(api.bodies['POST /teams/9/members'],
          {'email': 'a@x.com', 'level': 'member'});

      api.routes['POST /teams/9/members'] =
          ((_) => json({'email': 'n@x.com', 'status': 'invited'}, 201));
      expect(await team.addMember(9, 'n@x.com'), isFalse);

      api.routes['POST /teams/9/members'] = ((_) => json({
            'detail': [
              {'msg': 'value is not a valid email address'}
            ]
          }, 422));
      expect(team.addMember(9, 'nope'),
          throwsA(isA<TeamApiException>().having(
              (e) => e.message, 'message', 'Enter a valid email address.')));
    });

    test('removing encodes the email in the path', () async {
      final api = FakeApi()
        ..routes['DELETE /teams/9/members/a%2Bb%40x.com'] =
            ((_) => json({'status': 'removed'}));
      await HospitalityTeamApi(api).removeMember(9, 'a+b@x.com');
      expect(api.calls, ['DELETE /teams/9/members/a%2Bb%40x.com']);
    });

    test('a server with no event is reported, not crashed on', () async {
      final api = FakeApi()..routes['GET /events'] = ((_) => json([]));
      expect(HospitalityTeamApi(api).load(),
          throwsA(isA<TeamApiException>()));
    });
  });

  group('HospitalitySection', () {
    Future<void> show(WidgetTester tester, FakeApi api) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
              child: HospitalitySection(api: HospitalityTeamApi(api))),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('offers to create the team, then shows it after creating',
        (tester) async {
      var created = false;
      final api = FakeApi()
        ..routes['GET /events'] = ((_) => json([{'id': 1}]))
        ..routes['GET /events/1/teams'] = ((_) => json(created
            ? [{'id': 9, 'name': 'Hospitality'}]
            : <Object>[]))
        ..routes['GET /teams/9/members'] = ((_) => json([]))
        ..routes['POST /events/1/teams'] = ((_) {
          created = true;
          return json({'id': 9}, 201);
        });

      await show(tester, api);
      expect(find.byKey(const Key('create-hospitality')), findsOneWidget);
      expect(find.byKey(const Key('hospitality-email')), findsNothing);

      await tester.tap(find.byKey(const Key('create-hospitality')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('create-hospitality')), findsNothing);
      expect(find.byKey(const Key('hospitality-email')), findsOneWidget);
      expect(find.text('No one is on the team yet.'), findsOneWidget);
    });

    testWidgets('adds a member by email and shows the roster', (tester) async {
      final roster = <Map<String, Object?>>[];
      final api = FakeApi()
        ..routes['GET /events'] = ((_) => json([{'id': 1}]))
        ..routes['GET /events/1/teams'] =
            ((_) => json([{'id': 9, 'name': 'Hospitality'}]))
        ..routes['GET /teams/9/members'] = ((_) => json(roster))
        ..routes['POST /teams/9/members'] = ((b) {
          roster.add({
            'email': (b as Map)['email'],
            'name': 'Asha Rao',
            'status': 'member'
          });
          return json({'status': 'member'}, 201);
        });

      await show(tester, api);
      await tester.enterText(
          find.byKey(const Key('hospitality-email')), ' asha@x.com ');
      await tester.tap(find.byKey(const Key('add-hospitality-member')));
      await tester.pumpAndSettle();

      expect(api.bodies['POST /teams/9/members'],
          {'email': 'asha@x.com', 'level': 'member'});
      expect(find.text('Asha Rao'), findsOneWidget);
    });

    testWidgets('rejects an obviously wrong email without calling the server',
        (tester) async {
      final api = FakeApi()
        ..routes['GET /events'] = ((_) => json([{'id': 1}]))
        ..routes['GET /events/1/teams'] =
            ((_) => json([{'id': 9, 'name': 'Hospitality'}]))
        ..routes['GET /teams/9/members'] = ((_) => json([]));

      await show(tester, api);
      await tester.enterText(find.byKey(const Key('hospitality-email')), 'nope');
      await tester.tap(find.byKey(const Key('add-hospitality-member')));
      await tester.pump();

      expect(api.calls.where((c) => c.startsWith('POST')), isEmpty);
    });

    testWidgets('removing asks first, then removes and refreshes',
        (tester) async {
      final roster = <Map<String, Object?>>[
        {'email': 'asha@x.com', 'name': 'Asha Rao', 'status': 'member'}
      ];
      final api = FakeApi()
        ..routes['GET /events'] = ((_) => json([{'id': 1}]))
        ..routes['GET /events/1/teams'] =
            ((_) => json([{'id': 9, 'name': 'Hospitality'}]))
        ..routes['GET /teams/9/members'] = ((_) => json(roster))
        ..routes['DELETE /teams/9/members/asha%40x.com'] = ((_) {
          roster.clear();
          return json({'status': 'removed'});
        });

      await show(tester, api);
      expect(find.text('Asha Rao'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Remove from Hospitality?'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(api.calls, contains('DELETE /teams/9/members/asha%40x.com'));
      expect(find.text('Asha Rao'), findsNothing);
      expect(find.text('No one is on the team yet.'), findsOneWidget);
    });

    testWidgets('shows a retry when the server cannot be loaded',
        (tester) async {
      final api = FakeApi()
        ..routes['GET /events'] =
            ((_) => http.Response('{"detail":"boom"}', 500));

      await show(tester, api);

      expect(find.text('boom'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}
