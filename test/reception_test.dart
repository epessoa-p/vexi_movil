import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vexi_movil/core/api_client.dart';
import 'package:vexi_movil/screens/reception_screens.dart';

import 'app_test.dart' show json;
import 'screens_test.dart' show app, sessionWith;

const _options = {
  'professionals': [
    {'id': 4, 'name': 'Laura Vet', 'is_vet': true},
  ],
  'services': [
    {'id': 3, 'name': 'Control', 'duration_minutes': 20},
  ],
  'branches': [],
  'default_duration': 30,
};

const _luna = {
  'id': 7,
  'name': 'Luna',
  'species': 'Perro',
  'owner': {'id': 2, 'name': 'Ana Pérez'},
};

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  testWidgets('agendar envía paciente, propietario, fecha y hora; muestra el choque de horario', (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    addTearDown(tester.view.reset);

    final sent = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      if (request.method == 'GET') return json(_options);
      sent.add(jsonDecode(request.body) as Map<String, dynamic>);
      return json({
        'message': 'El profesional ya tiene una cita.',
        'errors': {
          'time': ['El profesional ya tiene una cita de 09:00 a 09:30 (Rocky).'],
        },
      }, 422);
    });
    final session = sessionWith(client, permissions: ['appointments.create'], features: ['agenda']);

    await tester.pumpWidget(app(session, AppointmentFormScreen(pet: _luna, day: DateTime(2030, 1, 15))));
    await tester.pumpAndSettle();

    expect(find.text('Luna'), findsOneWidget);
    expect(find.text('09:00'), findsOneWidget); // otro día: a primera hora
    await tester.tap(find.text('Agendar'));
    await tester.pumpAndSettle();

    expect(sent.single, containsPair('client_id', 2));
    expect(sent.single, containsPair('pet_id', 7));
    expect(sent.single, containsPair('date', '2030-01-15'));
    expect(sent.single, containsPair('time', '09:00'));
    expect(sent.single, containsPair('duration_minutes', 30));
    expect(sent.single, containsPair('confirmed', false));
    expect(find.text('El profesional ya tiene una cita de 09:00 a 09:30 (Rocky).'), findsOneWidget);
  });

  testWidgets('reprogramar conserva la hora de la veterinaria y no reenvía el paciente', (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    addTearDown(tester.view.reset);

    Map<String, dynamic>? sent;
    String? method;
    final client = MockClient((request) async {
      if (request.method == 'GET') return json(_options);
      method = request.method;
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return json({'id': 11, 'starts_at': '2026-11-12T09:00:00-04:00'});
    });
    final session = sessionWith(client, permissions: ['appointments.edit'], features: ['agenda']);

    await tester.pumpWidget(
      app(
        session,
        const AppointmentFormScreen(
          appointment: {
            'id': 11,
            'starts_at': '2026-11-12T09:00:00-04:00',
            'ends_at': '2026-11-12T09:20:00-04:00',
            'service_id': 3,
            'veterinarian': {'id': 4, 'name': 'Laura Vet'},
            'reason': 'Control anual',
            'pet': _luna,
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();

    expect(method, 'PUT');
    expect(sent, isNot(contains('pet_id')));
    expect(sent!['date'], '2026-11-12');
    expect(sent!['time'], '09:00');
    expect(sent!['duration_minutes'], 20);
    expect(sent!['service_id'], 3);
    expect(sent!['veterinarian_id'], 4);
    expect(sent!['reason'], 'Control anual');
  });

  testWidgets('registrar mascota: especie, sexo y peso con coma', (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    addTearDown(tester.view.reset);

    Map<String, dynamic>? sent;
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        return json({
          'species': [
            {
              'id': 1,
              'name': 'Perro',
              'breeds': [
                {'id': 9, 'name': 'Labrador'},
              ],
            },
          ],
          'sexes': [
            {'key': 'male', 'label': 'Macho'},
            {'key': 'female', 'label': 'Hembra'},
          ],
          'sizes': [],
          'statuses': [],
        });
      }
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return json({'id': 30, 'name': 'Toby'}, 201);
    });
    final session = sessionWith(client, permissions: ['pets.create']);

    await tester.pumpWidget(app(session, const PetFormScreen(client: {'id': 2, 'name': 'Ana Pérez'})));
    await tester.pumpAndSettle();

    expect(find.text('Propietario: Ana Pérez'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Nombre'), 'Toby');
    await tester.tap(find.text('Especie'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Perro').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hembra'));
    await tester.enterText(find.widgetWithText(TextField, 'Peso'), '12,5');
    await tester.tap(find.text('Registrar mascota'));
    await tester.pumpAndSettle();

    expect(sent!['client_id'], 2);
    expect(sent!['name'], 'Toby');
    expect(sent!['species_id'], 1);
    expect(sent!['sex'], 'female');
    expect(sent!['weight'], 12.5);
    expect(sent!['status'], 'active');
  });

  testWidgets('sala de espera: orden de llegada, sin asignar y «Llegó»', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    final posts = <String>[];
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        posts.add(request.url.path);
        return json({'id': 21, 'status': 'waiting'});
      }
      return json({
        'waiting': [
          {
            'id': 20,
            'is_walk_in': true,
            'reason': 'Cojera',
            'checked_in_at': DateTime.now().subtract(const Duration(minutes: 12)).toIso8601String(),
            'pet': {
              'name': 'Copito',
              'owner': {'name': 'Ana Pérez'},
            },
          },
        ],
        'in_progress': [],
        'upcoming': [
          {
            'id': 21,
            'starts_at': '2026-11-11T15:00:00-04:00',
            'pet': {'name': 'Rocky'},
          },
        ],
        'done_count': 2,
      });
    });
    final session = sessionWith(client, permissions: ['appointments.view', 'appointments.edit'], features: ['agenda']);

    await tester.pumpWidget(app(session, const WaitingRoomScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Copito · sin cita'), findsOneWidget);
    expect(find.text('1º · llegó hace 12 min'), findsOneWidget);
    expect(find.text('Sin asignar'), findsOneWidget);
    expect(find.text('2 citas de hoy ya se cerraron.'), findsOneWidget);

    await tester.tap(find.text('Llegó'));
    await tester.pumpAndSettle();
    expect(posts, ['/api/v1/appointments/21/check_in']);

    // Desmontar cancela la actualización automática.
    await tester.pumpWidget(const SizedBox());
  });

  test('upload manda la foto como multipart con el token y la veterinaria', () async {
    late http.BaseRequest seen;
    late String body;
    final api =
        ApiClient(
            baseUrl: 'https://vexi.test/api/v1',
            httpClient: MockClient((request) async {
              seen = request;
              body = latin1.decode(request.bodyBytes);
              return json({'id': 7, 'photo_url': 'https://vexi.test/storage/pets/1/a.jpg'});
            }),
          )
          ..token = 't1'
          ..companyId = 1;

    final result = await api.upload('/pets/7/photo', 'photo', [1, 2, 3], 'toby.jpg');

    expect(seen.method, 'POST');
    expect(seen.url.path, '/api/v1/pets/7/photo');
    expect(seen.headers['Authorization'], 'Bearer t1');
    expect(seen.headers['X-Company-Id'], '1');
    expect(seen.headers['content-type'], startsWith('multipart/form-data'));
    expect(body, contains('name="photo"; filename="toby.jpg"'));
    expect(result['photo_url'], isNotNull);
  });
}
