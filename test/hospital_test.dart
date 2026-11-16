import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vexi_movil/screens/hospital_screens.dart';

import 'app_test.dart' show json;
import 'screens_test.dart' show app, sessionWith;

const _perms = ['pets.view', 'hospitalizations.view', 'hospitalizations.create', 'hospitalizations.edit'];

Map<String, dynamic> _stay({String status = 'active', List<String> actions = const ['record', 'kennel', 'treat', 'discharge']}) => {
  'id': 4,
  'code': 'H-000004',
  'status': status,
  'status_badge': {'label': status == 'active' ? 'Internado' : 'Alta', 'color': status == 'active' ? 'info' : 'success'},
  'condition': 'observation',
  'condition_badge': {'label': 'En observación', 'color': 'warning'},
  'admitted_at': '2026-11-12T08:00:00-04:00',
  'discharged_at': status == 'active' ? null : '2026-11-14T10:00:00-04:00',
  'days': 1,
  'reason': 'Vómitos',
  'admission_diagnosis': 'Gastroenteritis',
  'kennel': 'Canil 1',
  'kennel_id': 1,
  'veterinarian': 'Laura Vet',
  'final_diagnosis': status == 'active' ? null : 'Gastroenteritis aguda',
  'home_treatment': status == 'active' ? null : 'Dieta blanda',
  'discharged_by': status == 'active' ? null : 'Laura Vet',
  'actions': actions,
  'pet': {'id': 3, 'name': 'Toby'},
  'treatments': [
    {
      'id': 9,
      'medication': 'Suero',
      'dose': '100 ml',
      'route': 'Intravenosa (IV)',
      'frequency_hours': 8,
      'ends_at': '2026-11-13T08:00:00-04:00',
      'active': true,
    },
  ],
  'doses': [],
  'records': [],
};

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  testWidgets('desde la internación se cambia el estado, se mueve de espacio y se suspende un tratamiento', (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    addTearDown(tester.view.reset);

    final posts = <String, Map<String, dynamic>>{};
    final client = MockClient((request) async {
      if (request.method == 'POST') posts[request.url.path] = request.body.isEmpty ? {} : jsonDecode(request.body) as Map<String, dynamic>;
      if (request.url.path.endsWith('/options')) {
        return json({
          'kennels': [
            {'id': 1, 'name': 'Canil 1'},
            {'id': 2, 'name': 'Jaula 2'},
          ],
        });
      }
      return json(_stay());
    });
    final session = sessionWith(client, permissions: _perms, features: ['hospitalizacion']);
    await tester.pumpWidget(app(session, const StayScreen(id: 4)));
    await tester.pumpAndSettle();

    expect(find.text('H-000004'), findsOneWidget);
    expect(find.text('Diagnóstico de ingreso: Gastroenteritis'), findsOneWidget);

    // Estado clínico: tocando el chip.
    await tester.tap(find.text('En observación'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crítico'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();
    final record = posts['/api/v1/hospitalizations/4/records']!;
    expect(record['condition'], 'critical');
    expect(record['type'], 'evolution');

    // Mover de espacio desde el menú (el aviso de arriba ya se fue).
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Acciones'));
    await tester.pumpAndSettle();
    expect(find.text('Anular ingreso'), findsNothing); // ya no está entre las acciones
    await tester.tap(find.text('Mover de espacio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jaula 2'));
    await tester.pumpAndSettle();
    expect(posts['/api/v1/hospitalizations/4/kennel'], {'kennel_id': 2});

    await tester.tap(find.byTooltip('Suspender'));
    await tester.pumpAndSettle();
    expect(find.text('¿Suspender Suero?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Suspender'));
    await tester.pumpAndSettle();
    expect(posts.keys, contains('/api/v1/hospitalizations/4/treatments/9/stop'));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('cerrada muestra el alta y no ofrece acciones', (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    addTearDown(tester.view.reset);

    final client = MockClient((request) async => json(_stay(status: 'discharged', actions: const [])));
    final session = sessionWith(client, permissions: _perms, features: ['hospitalizacion']);
    await tester.pumpWidget(app(session, const StayScreen(id: 4)));
    await tester.pumpAndSettle();

    expect(find.text('Gastroenteritis aguda'), findsOneWidget);
    expect(find.text('Dieta blanda'), findsOneWidget);
    expect(find.byTooltip('Acciones'), findsNothing);
    expect(find.text('Registrar'), findsNothing);
    expect(find.text('Tomas por aplicar'.toUpperCase()), findsNothing);
    expect(find.byTooltip('Suspender'), findsNothing);
  });

  testWidgets('el tratamiento calcula las tomas y envía frecuencia, inicio y fin', (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    addTearDown(tester.view.reset);

    Map<String, dynamic>? sent;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return json(_stay(), 201);
      }
      return json({
        'routes': [
          {'key': 'iv', 'label': 'Intravenosa (IV)'},
          {'key': 'oral', 'label': 'Oral'},
        ],
        'products': [],
      });
    });
    final session = sessionWith(client, permissions: _perms, features: ['hospitalizacion']);
    await tester.pumpWidget(app(session, const TreatmentScreen(stayId: 4)));
    await tester.pumpAndSettle();

    expect(find.textContaining('10 tomas'), findsOneWidget); // cada 8 h por 3 días

    await tester.tap(find.text('12 h'));
    await tester.tap(find.text('1 día'));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 tomas'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Medicamento'), 'Omeprazol');
    await tester.enterText(find.widgetWithText(TextField, 'Dosis'), '1 comp.');
    await tester.tap(find.text('Vía'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oral').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Programar tratamiento'));
    await tester.pumpAndSettle();

    expect(sent!['medication'], 'Omeprazol');
    expect(sent!['route'], 'oral');
    expect(sent!['frequency_hours'], 12);
    final start = DateTime.parse(sent!['starts_at'] as String);
    final end = DateTime.parse(sent!['ends_at'] as String);
    expect(end.difference(start), const Duration(days: 1));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
